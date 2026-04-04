import 'package:intl/intl.dart';

/// Formats a [DateTime] as "DD/MM/YYYY".
String formatDate(DateTime d) {
  return DateFormat('dd/MM/yyyy').format(d);
}

/// Formats [amount] as "R$ 1.000,00" (BRL) or "€1.000,00" (EUR).
String formatCurrency(double amount, String currency) {
  if (currency == 'EUR') {
    final formatter = NumberFormat.currency(
      locale: 'pt_BR',
      symbol: '€',
      decimalDigits: 2,
    );
    return formatter.format(amount).replaceAll('\u00a0', ' ');
  } else {
    final formatter = NumberFormat.currency(
      locale: 'pt_BR',
      symbol: 'R\$',
      decimalDigits: 2,
    );
    return formatter.format(amount).replaceAll('\u00a0', ' ');
  }
}

/// Returns the full month name in pt_BR (e.g., "Janeiro", "Fevereiro").
String monthName(int month) {
  const names = [
    'Janeiro', 'Fevereiro', 'Março', 'Abril',
    'Maio', 'Junho', 'Julho', 'Agosto',
    'Setembro', 'Outubro', 'Novembro', 'Dezembro',
  ];
  assert(month >= 1 && month <= 12, 'month must be 1–12');
  return names[month - 1];
}

/// Returns the abbreviated month name in pt_BR (e.g., "Jan", "Fev").
String monthAbbr(int month) {
  const abbrs = [
    'Jan', 'Fev', 'Mar', 'Abr',
    'Mai', 'Jun', 'Jul', 'Ago',
    'Set', 'Out', 'Nov', 'Dez',
  ];
  assert(month >= 1 && month <= 12, 'month must be 1–12');
  return abbrs[month - 1];
}
