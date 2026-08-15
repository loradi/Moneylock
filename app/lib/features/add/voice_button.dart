import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';
import '../../voice/speech_service.dart';
import '../../theme/app_theme.dart';

/// Botón de voz: mantén/haz tap para escuchar (Apple Speech on-device).
/// Al llegar el resultado final se ejecuta AddTransactionFlow con source
/// 'voice' y se muestra el estado (escuchando / error / resultado).
class VoiceButton extends ConsumerStatefulWidget {
  final void Function(String status)? onStatus;
  const VoiceButton({super.key, this.onStatus});

  @override
  ConsumerState<VoiceButton> createState() => _VoiceButtonState();
}

enum _VoiceState { idle, listening, error }

class _VoiceButtonState extends ConsumerState<VoiceButton> {
  late final SpeechToTextService _speech;
  _VoiceState _state = _VoiceState.idle;
  String? _error;

  @override
  void initState() {
    super.initState();
    _speech = ref.read(speechServiceProvider);
  }

  @override
  void dispose() {
    _speech.stop();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() => _state = _VoiceState.listening);
    try {
      await _speech.init();
      await _speech.listen((text) {
        if (!mounted) return;
        setState(() => _state = _VoiceState.idle);
        final result = ref
            .read(addFlowProvider)
            .run(rawText: text, source: 'voice');
        result.then((r) {
          if (!mounted) return;
          if (r.inserted) {
            widget.onStatus?.call('Recorded: $text');
          } else {
            widget.onStatus?.call(r.error ?? 'Duplicate: already recorded.');
          }
        });
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _VoiceState.error;
        _error = e is SpeechPermissionException
            ? e.message
            : 'Voice capture failed: $e';
      });
    }
  }

  Future<void> _stop() async {
    await _speech.stop();
  }

  @override
  Widget build(BuildContext context) {
    final listening = _state == _VoiceState.listening;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () {
            if (listening) {
              _stop();
            } else {
              _start();
            }
          },
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: listening
                  ? AppColors.primary
                  : AppColors.surfaceContainerHigh,
            ),
            child: listening
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: const CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(
                    Icons.mic,
                    size: 28,
                    color: AppColors.onSurfaceVariant,
                  ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          listening ? 'Listening… tap to stop' : 'Tap to speak a transaction',
          style: AppTextStyles.bodyMd.copyWith(
            fontSize: 13,
            color: AppColors.onSurfaceVariant,
          ),
        ),
        if (_state == _VoiceState.error && _error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: AppColors.primary),
            ),
          ),
      ],
    );
  }
}
