import 'package:intl/intl.dart';

String fmtCurrency(double value) =>
    NumberFormat.currency(locale: 'en_US', symbol: r'$').format(value);

String fmtDate(DateTime d) => DateFormat('MMM d').format(d);

String fmtTime(DateTime d) => DateFormat('hh:mm a').format(d);

String fmtDayGroup(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'TODAY';
  if (diff == 1) return 'YESTERDAY';
  return '${DateFormat('EEE, MMM d').format(d).toUpperCase()}, ${diff}d AGO';
}

String fmtTimeAgo(DateTime d) {
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}
