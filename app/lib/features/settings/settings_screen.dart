import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
            const SizedBox(height: 28),
            const _Section('PRIVATE SYNC'),
            const _SyncCard(),
            const SizedBox(height: 28),
            const _Section('SUBSCRIPTIONS'),
            _SubscriptionsEntry(onTap: () => context.push('/subscriptions')),
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
              await ref
                  .read(appDatabaseProvider)
                  .settingsDao
                  .setNotificationsEnabled(v);
              ref.invalidate(notificationsEnabledProvider);
              await ref.read(notificationSchedulerProvider).refresh();
            },
          ),
        ],
      ),
    );
  }
}

class _SubscriptionsEntry extends StatelessWidget {
  final VoidCallback onTap;
  const _SubscriptionsEntry({required this.onTap});
  @override
  Widget build(BuildContext context) => _Card(
    child: InkWell(
      onTap: onTap,
      child: Row(
        children: [
          const Expanded(
            child: Text('Manage subscriptions', style: AppTextStyles.bodyMd),
          ),
          Icon(Icons.chevron_right, color: AppColors.onSurfaceVariant),
        ],
      ),
    ),
  );
}

class _SyncCard extends ConsumerStatefulWidget {
  const _SyncCard();

  @override
  ConsumerState<_SyncCard> createState() => _SyncCardState();
}

class _SyncCardState extends ConsumerState<_SyncCard> {
  final _urlController = TextEditingController();
  final _apiKeyController = TextEditingController();
  bool _loading = true;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final config = await ref
        .read(appDatabaseProvider)
        .settingsDao
        .syncConfiguration();
    if (!mounted) return;
    _urlController.text = config.baseUrl;
    _apiKeyController.text = config.apiKey;
    setState(() => _loading = false);
  }

  Future<void> _sync() async {
    if (_syncing) return;
    final baseUrl = _urlController.text.trim().replaceFirst(RegExp(r'/+$'), '');
    final apiKey = _apiKeyController.text.trim();
    if (baseUrl.isEmpty || apiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your server URL and API key.')),
      );
      return;
    }
    setState(() => _syncing = true);
    try {
      await ref
          .read(appDatabaseProvider)
          .settingsDao
          .setSyncConfiguration(baseUrl: baseUrl, apiKey: apiKey);
      final outcome = await ref.read(syncServiceProvider).sync();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Synced: ${outcome.uploaded} uploaded, ${outcome.downloaded} downloaded.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Sync failed: $error')));
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) => _Card(
    child: _loading
        ? const SizedBox(
            height: 44,
            child: Center(child: CircularProgressIndicator()),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Back up transactions to your own Moneylock server.',
                style: AppTextStyles.bodyMd.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _urlController,
                keyboardType: TextInputType.url,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: 'Server URL',
                  hintText: 'https://moneylock.example.com',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _apiKeyController,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(labelText: 'API key'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _syncing ? null : _sync,
                icon: _syncing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync),
                label: Text(_syncing ? 'Syncing…' : 'Sync transactions'),
              ),
              const SizedBox(height: 8),
              Text(
                'Only transaction records are synced. Plans, Vector chats, and model data stay on this device.',
                style: AppTextStyles.bodyMd.copyWith(
                  fontSize: 12,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
  );
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
      if (mounted) {
        setState(() => _result = 'Speech recognition works on-device.');
      }
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
