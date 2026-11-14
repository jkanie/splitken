import 'errors.dart';

/// The largest amount 1 expense may hold, in cents: 10 million in the
/// group's currency. It keeps every sum well inside the range that a
/// JavaScript number holds exactly, which the React Native app relies on.
const int maxAmountCents = 1000000000;

/// Reads a typed amount such as `12`, `12.5` or `12.50` into cents.
///
/// A comma or a sign, more than 2 decimals, an empty text, 0 and amounts
/// above [maxAmountCents] are refused with code `bad_amount`.
int parseCents(String text) {
  final t = text.trim();
  final match = RegExp(r'^(\d{1,8})(?:\.(\d{1,2}))?$').firstMatch(t);
  if (match == null) {
    throw SplitError('bad_amount', 'Type an amount such as 12 or 12.50.');
  }
  final whole = int.parse(match.group(1)!);
  final fraction = (match.group(2) ?? '').padRight(2, '0');
  final cents = whole * 100 + int.parse(fraction);
  checkAmount(cents);
  return cents;
}

/// Refuses an amount of 0 or less, or above [maxAmountCents].
void checkAmount(int cents) {
  if (cents <= 0 || cents > maxAmountCents) {
    throw SplitError(
      'bad_amount',
      'An amount must be above 0 and at most ${formatCents(maxAmountCents)}.',
    );
  }
}

/// Writes cents with 2 decimals and no grouping: 123456 -> `1234.56`,
/// -5 -> `-0.05`.
String formatCents(int cents) {
  final sign = cents < 0 ? '-' : '';
  final abs = cents.abs();
  final whole = abs ~/ 100;
  final fraction = (abs % 100).toString().padLeft(2, '0');
  return '$sign$whole.$fraction';
}
