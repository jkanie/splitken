import 'errors.dart';
import 'model.dart';

/// What 1 operation does.
enum OpKind {
  /// Adds a member, or renames 1.
  member,

  /// Adds an expense, or replaces 1 with a new version.
  expense,

  /// Removes an expense.
  delete,
}

/// 1 change made on 1 device. Devices work offline, then exchange their
/// operations through the server. Every device folds the same set of
/// operations into the same group, whatever order they arrive in.
///
/// [lamport] is a Lamport clock: a device sets it 1 above the highest it has
/// seen. Between 2 changes to the same member or expense, the one with the
/// higher (lamport, clientId, opId) wins. [seq] is the server's order of
/// arrival, absent until the server has the operation.
class Op {
  Op({
    required this.opId,
    required this.clientId,
    required this.lamport,
    required this.kind,
    this.member,
    this.expense,
    this.expenseId,
    this.seq,
  });

  final String opId;
  final String clientId;
  final int lamport;
  final OpKind kind;
  final Member? member;
  final Expense? expense;
  final String? expenseId;
  final int? seq;

  /// The id of the member or expense this operation changes.
  String get target => switch (kind) {
    OpKind.member => member!.id,
    OpKind.expense => expense!.id,
    OpKind.delete => expenseId!,
  };

  Op withSeq(int seq) => Op(
    opId: opId,
    clientId: clientId,
    lamport: lamport,
    kind: kind,
    member: member,
    expense: expense,
    expenseId: expenseId,
    seq: seq,
  );

  /// The same operation as a device sends it, without the server's seq.
  Op withoutSeq() => Op(
    opId: opId,
    clientId: clientId,
    lamport: lamport,
    kind: kind,
    member: member,
    expense: expense,
    expenseId: expenseId,
  );

  Map<String, Object?> toJson() => {
    'opId': opId,
    'clientId': clientId,
    'lamport': lamport,
    'kind': kind.name,
    if (member != null) 'member': member!.toJson(),
    if (expense != null) 'expense': expense!.toJson(),
    if (expenseId != null) 'expenseId': expenseId,
    if (seq != null) 'seq': seq,
  };

  factory Op.fromJson(Map<String, Object?> json) {
    final kindName = json['kind'];
    final kind = OpKind.values.where((k) => k.name == kindName);
    final opId = json['opId'];
    final clientId = json['clientId'];
    final lamport = json['lamport'];
    if (kind.isEmpty ||
        opId is! String ||
        clientId is! String ||
        lamport is! int) {
      throw SplitError(
        'bad_op',
        'An operation needs opId, clientId, lamport and a known kind.',
      );
    }
    if (opId.isEmpty ||
        opId.length > 64 ||
        clientId.isEmpty ||
        clientId.length > 64) {
      throw SplitError('bad_op', 'opId and clientId are 1 to 64 characters.');
    }
    if (lamport < 1 || lamport > maxLamport) {
      throw SplitError('bad_op', 'lamport is from 1 to $maxLamport.');
    }
    final member = json['member'];
    final expense = json['expense'];
    final expenseId = json['expenseId'];
    final seq = json['seq'];
    switch (kind.single) {
      case OpKind.member:
        if (member is! Map<String, Object?>) {
          throw SplitError('bad_op', 'A member operation holds a member.');
        }
        final m = Member.fromJson(member);
        if (m.id.isEmpty ||
            m.id.length > 64 ||
            m.name.trim().isEmpty ||
            m.name.length > 60) {
          throw SplitError(
            'bad_member',
            'A member id is 1 to 64 characters and a name 1 to 60.',
          );
        }
        return Op(
          opId: opId,
          clientId: clientId,
          lamport: lamport,
          kind: OpKind.member,
          member: m,
          seq: seq as int?,
        );
      case OpKind.expense:
        if (expense is! Map<String, Object?>) {
          throw SplitError('bad_op', 'An expense operation holds an expense.');
        }
        return Op(
          opId: opId,
          clientId: clientId,
          lamport: lamport,
          kind: OpKind.expense,
          expense: Expense.fromJson(expense),
          seq: seq as int?,
        );
      case OpKind.delete:
        if (expenseId is! String || expenseId.isEmpty) {
          throw SplitError('bad_op', 'A delete operation names an expenseId.');
        }
        return Op(
          opId: opId,
          clientId: clientId,
          lamport: lamport,
          kind: OpKind.delete,
          expenseId: expenseId,
          seq: seq as int?,
        );
    }
  }
}

/// The highest Lamport value accepted: 2^53 - 1, the largest integer a
/// JavaScript number holds exactly.
const int maxLamport = 9007199254740991;

/// Orders 2 operations: the later one wins.
int compareStamps(Op a, Op b) {
  final byLamport = a.lamport.compareTo(b.lamport);
  if (byLamport != 0) return byLamport;
  final byClient = a.clientId.compareTo(b.clientId);
  if (byClient != 0) return byClient;
  return a.opId.compareTo(b.opId);
}

/// A group as the operations leave it.
class GroupState {
  GroupState(this.members, this.expenses);

  /// The founding members 1st, then members added later, in the order of
  /// the operation that 1st added each.
  final List<Member> members;

  /// Expenses that are not deleted, in the order of the operation that 1st
  /// added each.
  final List<Expense> expenses;
}

/// Folds [ops] into a group that starts with [founders]. The result is the
/// same for any order of [ops], and an operation sent twice counts once.
GroupState fold(List<Member> founders, Iterable<Op> ops) {
  final unique = <String, Op>{};
  for (final op in ops) {
    unique['${op.clientId}\u0000${op.opId}'] = op;
  }
  final sorted = unique.values.toList()..sort(compareStamps);

  final names = {for (final m in founders) m.id: m.name};
  final memberOrder = [for (final m in founders) m.id];
  final latestExpense = <String, Op>{};
  final expenseOrder = <String>[];

  for (final op in sorted) {
    switch (op.kind) {
      case OpKind.member:
        if (!names.containsKey(op.member!.id)) memberOrder.add(op.member!.id);
        names[op.member!.id] = op.member!.name;
      case OpKind.expense:
      case OpKind.delete:
        if (!latestExpense.containsKey(op.target)) expenseOrder.add(op.target);
        latestExpense[op.target] = op;
    }
  }
  return GroupState(
    [for (final id in memberOrder) Member(id, names[id]!)],
    [
      for (final id in expenseOrder)
        if (latestExpense[id]!.kind == OpKind.expense)
          latestExpense[id]!.expense!,
    ],
  );
}

/// The Lamport value for a new operation on a device that has seen [ops].
int nextLamport(Iterable<Op> ops) =>
    ops.fold<int>(0, (high, op) => op.lamport > high ? op.lamport : high) + 1;
