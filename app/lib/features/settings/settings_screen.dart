import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../llm/prompts.dart';
import '../../providers.dart';
import '../../voice/speech_service.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CupertinoPageScaffold(
      child: CustomScrollView(
        slivers: [
          const CupertinoSliverNavigationBar(
              largeTitle: Text('Settings')),
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList.list(children: const [
              _SectionTitle('Mentor tone'),
              _ToneSelector(),
              SizedBox(height: 24),
              _SectionTitle('Budgets'),
              _BudgetEditor(),
              SizedBox(height: 24),
              _SectionTitle('On-device model'),
              _ModelCard(),
              SizedBox(height: 24),
              _SectionTitle('Voice'),
              _VoiceCard(),
              SizedBox(height: 40),
            ]),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(title,
          style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: CupertinoColors.secondaryLabel)),
    );
  }
}

class _ToneSelector extends ConsumerWidget {
  const _ToneSelector();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tone = ref.watch(mentorToneProvider).valueOrNull ?? 'strict_ramsey';
    return CupertinoSegmentedControl<String>(
      groupValue: tone,
      onValueChanged: (t) {
        ref.read(appDatabaseProvider).settingsDao.setMentorTone(t);
        ref.invalidate(mentorToneProvider);
      },
      children: const {
        'strict_ramsey': Padding(
            padding: EdgeInsets.symmetric(horizontal: 10), child: Text('Strict')),
        'neutral_analyst': Padding(
            padding: EdgeInsets.symmetric(horizontal: 10),
            child: Text('Neutral')),
        'friendly_coach': Padding(
            padding: EdgeInsets.symmetric(horizontal: 10),
            child: Text('Friendly')),
      },
    );
  }
}

class _BudgetEditor extends ConsumerStatefulWidget {
  const _BudgetEditor();

  @override
  ConsumerState<_BudgetEditor> createState() => _BudgetEditorState();
}

class _BudgetEditorState extends ConsumerState<_BudgetEditor> {
  Map<String, double> _limits = {};
  final Map<String, TextEditingController> _controllers = {};

  @override
  void initState() {
    super.initState();
    for (final c in categoryCatalog) {
      _controllers[c] = TextEditingController();
    }
    _load();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final period = _currentPeriod();
    final limits = await ref
        .read(appDatabaseProvider)
        .budgetsDao
        .limitsForPeriod(period);
    if (!mounted) return;
    setState(() {
      _limits = limits;
      for (final c in categoryCatalog) {
        final controller = _controllers[c]!;
        if (controller.text.isEmpty) {
          controller.text = _trimLimit(limits[c]);
        }
      }
    });
  }

  String _trimLimit(double? v) =>
      v == null ? '' : (v == v.roundToDouble() ? v.toInt().toString() : v.toString());

  Future<void> _save(String category) async {
    final raw = _controllers[category]?.text.trim() ?? '';
    final value = double.tryParse(raw);
    if (value == null || value <= 0) {
      _alert('Enter a valid monthly limit for $category.');
      return;
    }
    await ref
        .read(appDatabaseProvider)
        .budgetsDao
        .upsert(category, value, _currentPeriod());
    if (!mounted) return;
    setState(() => _limits = {..._limits, category: value});
    _alert('${fmtCurrency(value)} monthly cap set for $category.');
  }

  void _alert(String message) {
    showCupertinoDialog<void>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        content: Text(message),
        actions: [
          CupertinoDialogAction(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = CupertinoColors.activeBlue.withValues(alpha: 0.12);
    return Column(
      children: [
        for (final category in categoryCatalog)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 150,
                  child: Text(category,
                      style: const TextStyle(fontSize: 14),
                      overflow: TextOverflow.ellipsis),
                ),
                Expanded(
                  child: CupertinoTextField(
                    controller: _controllers[category],
                    placeholder: 'No limit',
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    textAlign: TextAlign.right,
                  ),
                ),
                const SizedBox(width: 8),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  child: const Icon(CupertinoIcons.checkmark_alt,
                      size: 20, color: CupertinoColors.activeBlue),
                  onPressed: () => _save(category),
                ),
              ],
            ),
          ),
      ],
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
  String? _error;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final ready = await ref.read(llamaServiceProvider).isModelReady();
    if (!mounted) return;
    setState(() => _ready = ready);
  }

  Future<void> _download() async {
    setState(() {
      _downloading = true;
      _error = null;
      _progress = 0;
    });
    try {
      await ref
          .read(llamaServiceProvider)
          .ensureModelDownloaded((p) {
        if (mounted) setState(() => _progress = p);
      });
      await _check();
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Download failed: $e');
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = _ready;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: CupertinoColors.systemBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: CupertinoColors.separator),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                ready == true
                    ? CupertinoIcons.checkmark_seal_fill
                    : CupertinoIcons.doc_on_doc,
                color: ready == true
                    ? CupertinoColors.systemGreen
                    : CupertinoColors.secondaryLabel,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  ready == null
                      ? 'Checking model…'
                      : ready
                          ? 'Qwen 2.5 3B ready'
                          : 'Qwen 2.5 3B not downloaded',
                  style: const TextStyle(fontSize: 15),
                ),
              ),
            ],
          ),
          if (ready == true)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('Runs fully on-device. Your data never leaves '
                  'your phone.',
                  style: TextStyle(
                      fontSize: 12,
                      color: CupertinoColors.secondaryLabel)),
            ),
          if (ready == false && !_downloading)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: CupertinoButton(
                color: CupertinoColors.activeBlue,
                borderRadius: BorderRadius.circular(8),
                onPressed: _download,
                child: const Text('Download model (~2 GB)',
                    style: TextStyle(color: CupertinoColors.white)),
              ),
            ),
          if (_downloading) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: SizedBox(
                height: 6,
                child: Row(children: [
                  Expanded(
                    flex: (_progress * 1000).round().clamp(0, 1000),
                    child: const ColoredBox(
                        color: CupertinoColors.activeBlue),
                  ),
                  Expanded(
                    flex: 1000 - (_progress * 1000).round().clamp(0, 1000),
                    child:
                        const ColoredBox(color: CupertinoColors.systemFill),
                  ),
                ]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Downloading… ${(_progress * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                      fontSize: 12, color: CupertinoColors.secondaryLabel)),
            ),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!,
                  style: const TextStyle(
                      fontSize: 12, color: CupertinoColors.systemRed)),
            ),
        ],
      ),
    );
  }
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
      if (!mounted) return;
      setState(() => _result =
          'Speech recognition works. Apple Speech is on-device, no model needed.');
    } on SpeechPermissionException catch (e) {
      if (!mounted) return;
      setState(() => _result = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _result = 'Voice check failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: CupertinoColors.systemBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: CupertinoColors.separator),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Voice capture uses on-device Apple Speech. '
              'Nothing to download.',
              style: TextStyle(fontSize: 13, height: 1.3)),
          const SizedBox(height: 10),
          CupertinoButton(
            color: CupertinoColors.systemGrey5,
            borderRadius: BorderRadius.circular(8),
            onPressed: _test,
            child: const Text('Test microphone',
                style: TextStyle(color: CupertinoColors.black)),
          ),
          if (_result != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_result!,
                  style: const TextStyle(fontSize: 12, height: 1.3)),
            ),
        ],
      ),
    );
  }
}

String _currentPeriod() {
  final now = DateTime.now();
  return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';
}