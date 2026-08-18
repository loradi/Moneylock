import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';
import '../../theme/app_theme.dart';
import '../../voice/speech_service.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.margin,
            12,
            AppSpacing.margin,
            40,
          ),
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back),
                ),
                const Text('Settings', style: AppTextStyles.headlineLgMobile),
              ],
            ),
            const SizedBox(height: 20),
            const _Section('MENTOR TONE'),
            const _ToneSelector(),
            const SizedBox(height: 28),
            const _Section('ON-DEVICE MODEL'),
            const _ModelCard(),
            const SizedBox(height: 28),
            const _Section('VOICE'),
            const _VoiceCard(),
            const SizedBox(height: 28),
            const _Section('NOTIFICATIONS'),
            const _NotificationsCard(),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  const _Section(this.title);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      title,
      style: AppTextStyles.labelCaps.copyWith(
        color: AppColors.onSurfaceVariant,
      ),
    ),
  );
}

class _ToneSelector extends ConsumerWidget {
  const _ToneSelector();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tone = ref.watch(mentorToneProvider).valueOrNull ?? 'strict_ramsey';
    return SegmentedButton<String>(
      segments: const [
        ButtonSegment(value: 'strict_ramsey', label: Text('Strict')),
        ButtonSegment(value: 'neutral_analyst', label: Text('Neutral')),
        ButtonSegment(value: 'friendly_coach', label: Text('Friendly')),
      ],
      selected: {tone},
      onSelectionChanged: (v) {
        ref.read(appDatabaseProvider).settingsDao.setMentorTone(v.first);
        ref.invalidate(mentorToneProvider);
      },
    );
  }
}

class _NotificationsCard extends ConsumerWidget {
  const _NotificationsCard();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabledAsync = ref.watch(notificationsEnabledProvider);
    final enabled = enabledAsync.valueOrNull ?? true;
    return _Card(
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Daily reminders and spending check-ins',
              style: AppTextStyles.bodyMd,
            ),
          ),
          Switch(
            value: enabled,
            onChanged: (v) async {
              await ref.read(appDatabaseProvider).settingsDao.setNotificationsEnabled(v);
              ref.invalidate(notificationsEnabledProvider);
            },
          ),
        ],
      ),
    );
  }
}

class _ModelCard extends ConsumerStatefulWidget {
  const _ModelCard();
  @override
  ConsumerState<_ModelCard> createState() => _ModelCardState();
}

class _ModelCardState extends ConsumerState<_ModelCard> {
  bool? _ready;
  double _progress = 0;
  bool _downloading = false;
  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final ready = await ref.read(llamaServiceProvider).isModelReady();
    if (mounted) setState(() => _ready = ready);
  }

  Future<void> _download() async {
    setState(() => _downloading = true);
    try {
      await ref.read(llamaServiceProvider).ensureModelDownloaded((p) {
        if (mounted) setState(() => _progress = p);
      });
      await _check();
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) => _Card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              _ready == true ? Icons.verified : Icons.download,
              color: _ready == true ? Colors.green : AppColors.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _ready == true
                    ? 'Qwen 2.5 3B ready'
                    : _ready == false
                    ? 'Qwen 2.5 3B not downloaded'
                    : 'Checking model…',
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Runs fully on-device. Your data never leaves your phone.',
          style: AppTextStyles.bodyMd.copyWith(
            fontSize: 13,
            color: AppColors.onSurfaceVariant,
          ),
        ),
        if (_ready == false && !_downloading)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: OutlinedButton(
              onPressed: _download,
              child: const Text('Download model (~2 GB)'),
            ),
          ),
        if (_downloading)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: LinearProgressIndicator(value: _progress),
          ),
      ],
    ),
  );
}

class _VoiceCard extends ConsumerStatefulWidget {
  const _VoiceCard();
  @override
  ConsumerState<_VoiceCard> createState() => _VoiceCardState();
}

class _VoiceCardState extends ConsumerState<_VoiceCard> {
  String? _result;
  Future<void> _test() async {
    setState(() => _result = 'Checking permission…');
    try {
      final speech = ref.read(speechServiceProvider);
      await speech.init();
      await speech.stop();
      if (mounted)
        setState(() => _result = 'Speech recognition works on-device.');
    } on SpeechPermissionException catch (e) {
      if (mounted) setState(() => _result = e.message);
    } catch (e) {
      if (mounted) setState(() => _result = 'Voice check failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) => _Card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Voice capture uses on-device Apple Speech. Nothing to download.',
          style: AppTextStyles.bodyMd.copyWith(
            color: AppColors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _test,
          icon: const Icon(Icons.mic),
          label: const Text('Test microphone'),
        ),
        if (_result != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(_result!),
          ),
      ],
    ),
  );
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadii.full),
      border: Border.all(color: AppColors.borderSubtle),
    ),
    child: child,
  );
}
