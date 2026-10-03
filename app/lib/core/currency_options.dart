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
  'BOB': 'Bolivian Boliviano',
  'CRC': 'Costa Rican Colón',
  'CZK': 'Czech Koruna',
  'DKK': 'Danish Krone',
  'DOP': 'Dominican Peso',
  'EGP': 'Egyptian Pound',
  'HKD': 'Hong Kong Dollar',
  'HUF': 'Hungarian Forint',
  'IDR': 'Indonesian Rupiah',
  'ILS': 'Israeli New Shekel',
  'KRW': 'South Korean Won',
  'MAD': 'Moroccan Dirham',
  'MYR': 'Malaysian Ringgit',
  'NGN': 'Nigerian Naira',
  'NOK': 'Norwegian Krone',
  'PHP': 'Philippine Peso',
  'PKR': 'Pakistani Rupee',
  'PLN': 'Polish Zloty',
  'QAR': 'Qatari Riyal',
  'RON': 'Romanian Leu',
  'RUB': 'Russian Ruble',
  'SAR': 'Saudi Riyal',
  'SEK': 'Swedish Krona',
  'SGD': 'Singapore Dollar',
  'THB': 'Thai Baht',
  'TRY': 'Turkish Lira',
  'TWD': 'Taiwan Dollar',
  'UAH': 'Ukrainian Hryvnia',
  'VND': 'Vietnamese Dong',
  'ZAR': 'South African Rand',
};

bool isCurrencyCode(String value) => RegExp(r'^[A-Z]{3}$').hasMatch(value);

String normalizeCurrencyCode(String value) => value.trim().toUpperCase();

class CurrencySelector extends StatelessWidget {
  final String value;
  final String label;
  final ValueChanged<String> onSubmitted;

  const CurrencySelector({
    super.key,
    required this.value,
    required this.label,
    required this.onSubmitted,
  });

  @override
  @override
  Widget build(BuildContext context) {
    final options = {...commonCurrencies};
    if (!options.containsKey(value)) options[value] = value;
    return DropdownButtonFormField<String>(
      initialValue: options.containsKey(value) ? value : null,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.currency_exchange),
        helperText: 'Select the currency used for new entries and plans.',
      ),
      items: [
        for (final entry in options.entries)
          DropdownMenuItem(
            value: entry.key,
            child: Text('${entry.key} · ${entry.value}'),
          ),
      ],
      onChanged: (code) {
        if (code != null && isCurrencyCode(code)) onSubmitted(code);
      },
    );
  }
}
