import 'package:intl/intl.dart';

String fmtCurrency(double value) =>
    NumberFormat.currency(locale: 'en_US', symbol: r'$').format(value);

String fmtDate(DateTime d) => DateFormat('MMM d').format(d);