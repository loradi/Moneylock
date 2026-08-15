import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';
import '../../theme/app_theme.dart';

/// Formulario de captura manual: texto libre -> AddTransactionFlow.
/// Cierra el sheet devolviendo true si la transacción se insertó.
class ManualForm extends ConsumerStatefulWidget {
  final void Function(String status)? onStatus;
  const ManualForm({super.key, this.onStatus});

  @override
  ConsumerState<ManualForm> createState() => _ManualFormState();
}

class _ManualFormState extends ConsumerState<ManualForm> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await ref
        .read(addFlowProvider)
        .run(rawText: text, source: 'manual');
    if (!mounted) return;
    setState(() => _busy = false);
    if (result.inserted) {
      widget.onStatus?.call('Recorded');
      Navigator.of(context).maybePop(true);
    } else {
      setState(
        () => _error =
            result.error ?? 'Duplicate: this transaction was already recorded.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _controller,
            decoration: InputDecoration(
              hintText: 'e.g. Starbucks 12.50',
              suffixIcon: _busy
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton(
                      onPressed: _submit,
                      icon: const Icon(
                        Icons.arrow_circle_right,
                        color: AppColors.primary,
                      ),
                    ),
            ),
            keyboardType: TextInputType.text,
            autocorrect: true,
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _error!,
                style: const TextStyle(fontSize: 12, color: AppColors.primary),
              ),
            ),
        ],
      ),
    );
  }
}
