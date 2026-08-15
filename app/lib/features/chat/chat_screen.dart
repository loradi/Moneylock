import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../llm/mentor_agent.dart';
import '../../providers.dart';
import '../../theme/app_theme.dart';

final _amountRe = RegExp(r'\$\s?\d+(?:\.\d{1,2})?|\d+\.\d{2}');
bool hasMonetaryAmount(String text) => _amountRe.hasMatch(text);

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});
  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  bool _thinking = false;
  int _lastCount = -1;
  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(messagesStreamProvider).value ?? const [];
    if (messages.length != _lastCount) {
      _lastCount = messages.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients)
          _scroll.animateTo(
            _scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
          );
      });
    }
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      body: SafeArea(
        child: Column(
          children: [
            const _ChatHeader(),
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.all(AppSpacing.md),
                itemCount: messages.length + (_thinking ? 1 : 0),
                itemBuilder: (_, i) {
                  if (i == messages.length)
                    return const _Bubble(
                      role: 'mentor',
                      content: '',
                      thinking: true,
                    );
                  final m = messages[i];
                  return _Bubble(role: m.role, content: m.content);
                },
              ),
            ),
            _Composer(controller: _controller, onSend: _send),
          ],
        ),
      ),
    );
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _thinking) return;
    _controller.clear();
    final db = ref.read(appDatabaseProvider);
    await db.messagesDao.add('user', text);
    if (mounted) setState(() => _thinking = true);
    if (hasMonetaryAmount(text)) {
      final result = await ref
          .read(addFlowProvider)
          .run(rawText: text, source: 'manual');
      if (result.error != null)
        await db.messagesDao.add(
          'mentor',
          'Could not record that: ${result.error}',
        );
    } else {
      final tone = await db.settingsDao.mentorTone();
      try {
        final reply = await ref
            .read(llmProviderProvider)
            .complete(mentorPromptFor(tone), text);
        await db.messagesDao.add('mentor', reply);
      } catch (_) {
        await db.messagesDao.add(
          'mentor',
          'I could not reach my model right now.',
        );
      }
    }
    if (mounted) setState(() => _thinking = false);
  }
}

class _ChatHeader extends StatelessWidget {
  const _ChatHeader();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.margin,
      16,
      AppSpacing.margin,
      14,
    ),
    decoration: const BoxDecoration(
      color: AppColors.darkSurface,
      border: Border(
        bottom: BorderSide(color: AppColors.darkSurfaceContainerHighest),
      ),
    ),
    child: Row(
      children: [
        IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.close, color: AppColors.darkOnSurface),
        ),
        const SizedBox(width: 8),
        Container(
          width: 34,
          height: 34,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.primary,
          ),
          child: const Icon(Icons.smart_toy, color: Colors.white, size: 18),
        ),
        const SizedBox(width: 10),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'VECTOR',
              style: TextStyle(
                color: AppColors.darkOnSurface,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
              ),
            ),
            Text(
              'Your money mentor',
              style: TextStyle(
                color: AppColors.darkOnSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _Bubble extends StatelessWidget {
  final String role;
  final String content;
  final bool thinking;
  const _Bubble({
    required this.role,
    required this.content,
    this.thinking = false,
  });
  @override
  Widget build(BuildContext context) {
    final user = role == 'user';
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * .78,
        ),
        decoration: BoxDecoration(
          color: user ? AppColors.primary : AppColors.darkSurfaceContainerHigh,
          borderRadius: BorderRadius.circular(16),
        ),
        child: thinking
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.darkOnSurfaceVariant,
                ),
              )
            : Text(
                content,
                style: TextStyle(
                  color: user ? Colors.white : AppColors.darkOnSurface,
                  height: 1.35,
                ),
              ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  const _Composer({required this.controller, required this.onSend});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
    child: Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            style: const TextStyle(color: AppColors.darkOnSurface),
            decoration: InputDecoration(
              hintText: 'Ask Vector anything…',
              hintStyle: const TextStyle(color: AppColors.darkOnSurfaceVariant),
              prefixIcon: const Icon(
                Icons.mic_none,
                color: AppColors.darkOnSurfaceVariant,
              ),
              filled: true,
              fillColor: AppColors.darkSurfaceContainerHigh,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
            onSubmitted: (_) => onSend(),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: onSend,
          icon: const Icon(
            Icons.arrow_upward_rounded,
            color: AppColors.primaryBright,
            size: 28,
          ),
        ),
      ],
    ),
  );
}
