import 'errors.dart';
import 'money.dart';

/// How an expense is shared out among its participants.
enum SplitMethod {
  /// The same amount each. Cents left over go 1 each to the 1st
  /// participants, in the order given.
  equal,

  /// Each participant's amount is given, and they must add up to the total.
  exact,

  /// Whole-number shares, such as 2 for an adult and 1 for a child.
  shares,

  /// Percentages in basis points (1% is 100), adding up to 10000.
  percent,
}

/// 1 person in a group. The id never changes. The name may.
class Member {
  const Member(this.id, this.name);

  final String id;
  final String name;

  Map<String, Object?> toJson() => {'id': id, 'name': name};

  factory Member.fromJson(Map<String, Object?> json) =>
      Member(json['id']! as String, json['name']! as String);

  @override
  bool operator ==(Object other) =>
      other is Member && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);
}

/// An expense, or a transfer when [isTransfer] is true: [paidBy] paid
/// [amountCents], and [participants] each owe their part of it.
///
/// A transfer records 1 member paying another back. It has exactly 1
/// participant, the member who got the money, and its method is `exact`.
class Expense {
  Expense({
    required this.id,
    required this.description,
    required this.amountCents,
    required this.paidBy,
    required this.participants,
    this.method = SplitMethod.equal,
    this.weights = const [],
    this.isTransfer = false,
  });

  final String id;
  final String description;
  final int amountCents;
  final String paidBy;

  /// Member ids, in the order the split gives out left-over cents.
  final List<String> participants;
  final SplitMethod method;

  /// 1 number per participant: cents for `exact`, shares for `shares`,
  /// basis points for `percent`. Empty for `equal`.
  final List<int> weights;
  final bool isTransfer;

  Map<String, Object?> toJson() => {
    'id': id,
    'description': description,
    'amountCents': amountCents,
    'paidBy': paidBy,
    'participants': participants,
    'method': method.name,
    'weights': weights,
    'isTransfer': isTransfer,
  };

  factory Expense.fromJson(Map<String, Object?> json) {
    T field<T>(String name) {
      final value = json[name];
      if (value is! T) {
        throw SplitError(
          'bad_expense',
          'The expense field "$name" is missing or of the wrong type.',
        );
      }
      return value;
    }

    final methodName = json['method'] ?? 'equal';
    final method = SplitMethod.values.where((m) => m.name == methodName);
    if (method.isEmpty) {
      throw SplitError('bad_expense', 'Unknown split method "$methodName".');
    }
    return Expense(
      id: field<String>('id'),
      description: field<String>('description'),
      amountCents: field<int>('amountCents'),
      paidBy: field<String>('paidBy'),
      participants: field<List<Object?>>('participants').map((p) {
        if (p is! String) {
          throw SplitError('bad_expense', 'A participant must be a member id.');
        }
        return p;
      }).toList(),
      method: method.single,
      weights: (json['weights'] as List<Object?>? ?? const []).map((w) {
        if (w is! int) {
          throw SplitError('bad_expense', 'A weight must be a whole number.');
        }
        return w;
      }).toList(),
      isTransfer: json['isTransfer'] as bool? ?? false,
    );
  }

  /// Checks the expense against the group's members. The split itself is
  /// checked by `splitExpense`.
  void validate(Set<String> memberIds) {
    if (id.isEmpty || id.length > 64) {
      throw SplitError('bad_expense', 'An expense id is 1 to 64 characters.');
    }
    if (description.trim().isEmpty || description.length > 200) {
      throw SplitError('bad_expense', 'A description is 1 to 200 characters.');
    }
    checkAmount(amountCents);
    if (!memberIds.contains(paidBy)) {
      throw SplitError(
        'unknown_member',
        'The payer "$paidBy" is not in the group.',
      );
    }
    if (participants.isEmpty) {
      throw SplitError(
        'bad_expense',
        'An expense needs at least 1 participant.',
      );
    }
    if (participants.toSet().length != participants.length) {
      throw SplitError('bad_expense', 'A participant is listed twice.');
    }
    for (final p in participants) {
      if (!memberIds.contains(p)) {
        throw SplitError(
          'unknown_member',
          'The participant "$p" is not in the group.',
        );
      }
    }
    if (isTransfer) {
      if (participants.length != 1 || participants.single == paidBy) {
        throw SplitError(
          'bad_transfer',
          'A transfer goes from 1 member to 1 other member.',
        );
      }
      if (method != SplitMethod.exact ||
          weights.length != 1 ||
          weights.single != amountCents) {
        throw SplitError(
          'bad_transfer',
          'A transfer has the method exact and 1 weight equal to its amount.',
        );
      }
    }
  }
}
