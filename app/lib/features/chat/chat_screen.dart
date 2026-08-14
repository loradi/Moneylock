import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../llm/mentor_agent.dart';
import '../../providers.dart';

final _amountRe = RegExp(r'\$\s?\d+(?:\.\d{1,2})?|\d+\.\d{2}');

/// True si el texto contiene un monto explícito (con `$` o con dos
/// decimales). Evita que frases habladas como "meet me at 5" disparen
/// el flujo de transacción.
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
      _scheduleScroll(messages.length);
    }
    return CupertinoPageScaffold(
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const _ChatHeader(),
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                itemCount: messages.length + (_thinking ? 1 : 0),
                itemBuilder: (context, i) {
                  if (i == messages.length) {
                    return const _Bubble(
                        role: 'mentor', content: '', thinking: true);
                  }
                  final m = messages[i];
                  return _Bubble(role: m.role, content: m.content);
                },
              ),
            ),
            _Composer(
              controller: _controller,
              onSend: _send,
            ),
          ],
        ),
      ),
    );
  }

  void _scheduleScroll(int count) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final target = _scroll.position.maxScrollExtent;
      if (count == 0) return;
      if (count == 1) {
        _scroll.jumpTo(target);
      } else {
        _scroll.animateTo(target,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut);
      }
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _thinking) return;
    _controller.clear();
    final db = ref.read(appDatabaseProvider);
    await db.messagesDao.add('user', text);
    setState(() => _thinking = true);
    if (hasMonetaryAmount(text)) {
      await _handleTransaction(text);
    } else {
      await _handleChat(text);
    }
    if (mounted) setState(() => _thinking = false);
  }

  Future<void> _handleTransaction(String text) async {
    final result =
        await ref.read(addFlowProvider).run(rawText: text, source: 'manual');
    if (!mounted) return;
    if (result.error != null) {
      await ref
          .read(appDatabaseProvider)
          .messagesDao.add('mentor', 'Could not record that: ${result.error}');
    }
  }

  Future<void> _handleChat(String text) async {
    final db = ref.read(appDatabaseProvider);
    final tone = await db.settingsDao.mentorTone();
    try {
      final reply = await ref
          .read(llmProviderProvider)
          .complete(mentorPromptFor(tone), text);
      await db.messagesDao.add('mentor', reply);
    } catch (_) {
      await db.messagesDao
          .add('mentor', 'I could not reach my model right now.');
    }
  }
}

class _ChatHeader extends StatelessWidget {
  const _ChatHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border(
            bottom: BorderSide(color: CupertinoColors.separator)),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(CupertinoIcons.chat_bubble_2_fill,
              size: 18, color: CupertinoColors.activeBlue),
          SizedBox(width: 6),
          Text('Your money mentor',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final String role;
  final String content;
  final bool thinking;
  const _Bubble({required this.role, required this.content, this.thinking = false});

  @override
  Widget build(BuildContext context) {
    final isUser = role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: isUser
              ? CupertinoColors.activeBlue
              : CupertinoColors.systemGrey5,
          borderRadius: BorderRadius.circular(18),
        ),
        child: thinking
            ? const CupertinoActivityIndicator()
            : Text(
                content,
                style: TextStyle(
                  fontSize: 15,
                  color: isUser
                      ? CupertinoColors.white
                      : CupertinoColors.black,
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
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Row(
        children: [
          Expanded(
            child: CupertinoTextField(
              controller: controller,
              placeholder: 'Ask your mentor… (or type "Starbucks 12.50")',
              onSubmitted: (_) => onSend(),
            ),
          ),
          const SizedBox(width: 8),
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: onSend,
            child: const Icon(CupertinoIcons.arrow_up_circle_fill,
                size: 30, color: CupertinoColors.activeBlue),
          ),
        ],
      ),
    );
  }
}