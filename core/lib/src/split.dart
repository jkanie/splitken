import 'errors.dart';
import 'model.dart';

/// The most shares 1 expense may hand out in total. With [maxAmountCents] it
/// keeps `amount * share` below 2^53, such that the TypeScript copy computes
/// the same integers.
const int maxTotalShares = 1000000;

/// What each participant owes for [expense], in cents, in the order of
/// `expense.participants`. The parts always add up to the amount.
///
/// `equal`, `shares`, `percent` use the largest remainder method: each part
/// is rounded down, then the cents left over go 1 each to the parts with the
/// largest remainders, ties going to the participant listed 1st.
List<int> splitExpense(Expense expense) {
  final n = expense.participants.length;
  final amount = expense.amountCents;
  if (n == 0) {
    throw SplitError('bad_expense', 'An expense needs at least 1 participant.');
  }
  switch (expense.method) {
    case SplitMethod.equal:
      if (expense.weights.isNotEmpty) {
        throw SplitError('bad_split', 'An equal split takes no weights.');
      }
      return _largestRemainder(amount, List.filled(n, 1));
    case SplitMethod.exact:
      _checkCount(expense);
      if (expense.weights.any((w) => w < 0)) {
        throw SplitError('bad_split', 'An exact part may not be below 0.');
      }
      final sum = expense.weights.fold<int>(0, (a, b) => a + b);
      if (sum != amount) {
        throw SplitError(
          'bad_split',
          'The exact parts add up to $sum cents, not $amount.',
        );
      }
      return List.of(expense.weights);
    case SplitMethod.shares:
      _checkCount(expense);
      if (expense.weights.any((w) => w < 1)) {
        throw SplitError(
          'bad_split',
          'Each share is a whole number of 1 or more.',
        );
      }
      final total = expense.weights.fold<int>(0, (a, b) => a + b);
      if (total > maxTotalShares) {
        throw SplitError(
          'bad_split',
          'The shares add up to more than $maxTotalShares.',
        );
      }
      return _largestRemainder(amount, expense.weights);
    case SplitMethod.percent:
      _checkCount(expense);
      if (expense.weights.any((w) => w < 0)) {
        throw SplitError('bad_split', 'A percentage may not be below 0.');
      }
      final total = expense.weights.fold<int>(0, (a, b) => a + b);
      if (total != 10000) {
        throw SplitError(
          'bad_split',
          'The percentages add up to ${total / 100}%, not 100%.',
        );
      }
      return _largestRemainder(amount, expense.weights);
  }
}

void _checkCount(Expense expense) {
  if (expense.weights.length != expense.participants.length) {
    throw SplitError('bad_split', 'Give 1 weight per participant.');
  }
}

List<int> _largestRemainder(int amount, List<int> weights) {
  final total = weights.fold<int>(0, (a, b) => a + b);
  final parts = <int>[];
  final remainders = <int>[];
  for (final w in weights) {
    parts.add(amount * w ~/ total);
    remainders.add(amount * w % total);
  }
  var left = amount - parts.fold<int>(0, (a, b) => a + b);
  final order = List<int>.generate(weights.length, (i) => i)
    ..sort((a, b) {
      final byRemainder = remainders[b].compareTo(remainders[a]);
      return byRemainder != 0 ? byRemainder : a.compareTo(b);
    });
  for (final i in order) {
    if (left == 0) break;
    parts[i] += 1;
    left -= 1;
  }
  return parts;
}
