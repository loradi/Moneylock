import 'package:flutter/material.dart';

const commonCurrencies = <String, String>{
  'USD': 'US Dollar',
  'CAD': 'Canadian Dollar',
  'EUR': 'Euro',
  'GBP': 'British Pound',
  'JPY': 'Japanese Yen',
  'AUD': 'Australian Dollar',
  'NZD': 'New Zealand Dollar',
  'CHF': 'Swiss Franc',
  'CNY': 'Chinese Yuan',
  'INR': 'Indian Rupee',
  'MXN': 'Mexican Peso',
  'BRL': 'Brazilian Real',
  'COP': 'Colombian Peso',
  'ARS': 'Argentine Peso',
  'CLP': 'Chilean Peso',
  'PEN': 'Peruvian Sol',
};

bool isCurrencyCode(String value) => RegExp(r'^[A-Z]{3}$').hasMatch(value);

String normalizeCurrencyCode(String value) => value.trim().toUpperCase();

class CurrencyCodeField extends StatefulWidget {
  final String value;
  final String label;
  final ValueChanged<String> onSubmitted;

  const CurrencyCodeField({
    super.key,
    required this.value,
    required this.label,
    required this.onSubmitted,
  });

  @override
  State<CurrencyCodeField> createState() => _CurrencyCodeFieldState();
}

class _CurrencyCodeFieldState extends State<CurrencyCodeField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant CurrencyCodeField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && _controller.text != widget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _controller,
    textCapitalization: TextCapitalization.characters,
    textInputAction: TextInputAction.done,
    maxLength: 3,
    decoration: InputDecoration(
      labelText: widget.label,
      counterText: '',
      suffixIcon: const Icon(Icons.currency_exchange),
      helperText: 'Any ISO 4217 code, such as USD or COP',
    ),
    onSubmitted: (raw) {
      final code = normalizeCurrencyCode(raw);
      if (isCurrencyCode(code)) widget.onSubmitted(code);
    },
  );
}
