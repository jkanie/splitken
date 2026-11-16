import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:splitken_core/splitken_core.dart';

import 'api_client.dart';
import 'ids.dart';
import 'key_value_store.dart';

/// 1 group on this device: the operations the server has confirmed, the ones
/// made here and not sent yet, the state both fold into.
///
/// Every change is an operation added to [pending] and saved at once, such
/// that the app works the same with no network. [sync] sends the pending
/// operations and brings back everyone else's.
class GroupBook extends ChangeNotifier {
  GroupBook({
    required this.meta,
    required this.clientId,
    required this._api,
    required this._store,
    List<Op>? confirmed,
    List<Op>? pending,
    this.seq = 0,
  }) : confirmed = confirmed ?? [],
       pending = pending ?? [] {
    _refold();
  }

  final GroupMeta meta;
  final String clientId;
  final ApiClient _api;
  final KeyValueStore _store;

  /// Operations from the server, in seq order.
  final List<Op> confirmed;

  /// Operations made on this device that the server has not confirmed.
  final List<Op> pending;

  /// The newest seq this device has from the server.
  int seq;

  bool syncing = false;

  /// Why the last sync did not finish, or null when it did.
  String? lastProblem;

  late GroupState _state;
  late Map<String, int> _net;

  GroupState get state => _state;

  Map<String, int> get net => _net;

  List<Transfer> get settle => settleUp(_state.members, _net);

  /// What the group spent and each member's part of it, pending changes
  /// included, from the core's [spending].
  Spending get spent => spending(_state.members, _state.expenses);

  String memberName(String id) =>
      _state.members.where((m) => m.id == id).map((m) => m.name).firstOrNull ?? id;

  static String storageKey(String groupId) => 'group:$groupId';

  void _refold() {
    _state = fold(meta.founders, [...confirmed, ...pending]);
    _net = balances(_state.members, _state.expenses);
  }

  Op _op(OpKind kind, {Member? member, Expense? expense, String? expenseId}) => Op(
    opId: randomId(),
    clientId: clientId,
    lamport: nextLamport([...confirmed, ...pending]),
    kind: kind,
    member: member,
    expense: expense,
    expenseId: expenseId,
  );

  /// Adds [expense], or replaces the expense with the same id. Throws a
  /// [SplitError] when it breaks a rule, and changes nothing then.
  Future<void> saveExpense(Expense expense) async {
    expense.validate({for (final m in _state.members) m.id});
    splitExpense(expense);
    await _add(_op(OpKind.expense, expense: expense));
  }

  Future<void> deleteExpense(String expenseId) => _add(_op(OpKind.delete, expenseId: expenseId));

  /// Adds a member. The id starts with this device's client id, such that 2
  /// devices adding members offline never pick the same id.
  Future<Member> addMember(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > 60) {
      throw SplitError('bad_member', 'A name is 1 to 60 characters.');
    }
    // As the server refuses for founders: Ana and ana are 1 name.
    if (state.members.any((m) => m.name.toLowerCase() == trimmed.toLowerCase())) {
      throw SplitError('bad_member', '"$trimmed" is already a member.');
    }
    final member = Member('$clientId-${randomId(6)}', trimmed);
    await _add(_op(OpKind.member, member: member));
    return member;
  }

  /// Records [transfer] as paid: a transfer expense from its payer to its
  /// receiver.
  Future<void> recordTransfer(Transfer transfer) => saveExpense(
    Expense(
      id: randomId(),
      description: '${memberName(transfer.from)} paid ${memberName(transfer.to)}',
      amountCents: transfer.amountCents,
      paidBy: transfer.from,
      participants: [transfer.to],
      method: SplitMethod.exact,
      weights: [transfer.amountCents],
      isTransfer: true,
    ),
  );

  Future<void> _add(Op op) async {
    pending.add(op);
    _refold();
    await save();
    notifyListeners();
  }

  /// Sends the pending operations and takes in everyone else's. Returns true
  /// when the device is up to date.
  ///
  /// With no network, the pending operations stay for the next try. When the
  /// server refuses 1 (it names it), that 1 is dropped, since it would be
  /// refused every time, and the rest are sent again.
  Future<bool> sync() async {
    if (syncing) return false;
    syncing = true;
    lastProblem = null;
    notifyListeners();
    try {
      for (var attempt = 0; attempt < 3; attempt++) {
        final sending = List.of(pending);
        try {
          final result = await _api.sync(meta.id, seq, sending);
          _take(result, sending);
          return true;
        } on RefusedError catch (e) {
          if (e.code == 'seq_ahead') {
            // The server has less than this device saw, such as after a
            // restore from an older back-up. Send everything again from 0:
            // the server keeps what it has once and takes the rest.
            pending.insertAll(0, [for (final op in confirmed) op.withoutSeq()]);
            confirmed.clear();
            seq = 0;
            continue;
          }
          final refused = pending.indexWhere((op) => op.opId == e.opId);
          if (refused < 0) {
            lastProblem = e.message;
            return false;
          }
          pending.removeAt(refused);
          lastProblem = 'A change was refused and removed: ${e.message}';
        }
      }
      return false;
    } on OfflineError {
      lastProblem = 'Offline. Changes are kept here and sent later.';
      return false;
    } finally {
      syncing = false;
      _refold();
      await save();
      notifyListeners();
    }
  }

  void _take(SyncResult result, List<Op> sent) {
    final known = {for (final op in confirmed) '${op.clientId}\u0000${op.opId}'};
    for (final op in result.ops) {
      if (known.add('${op.clientId}\u0000${op.opId}')) confirmed.add(op);
    }
    final sentKeys = {for (final op in sent) op.opId};
    pending.removeWhere((op) => sentKeys.contains(op.opId));
    seq = result.seq;
  }

  Future<void> save() => _store.write(
    storageKey(meta.id),
    jsonEncode({
      'meta': meta.toJson(),
      'seq': seq,
      'confirmed': [for (final op in confirmed) op.toJson()],
      'pending': [for (final op in pending) op.toJson()],
    }),
  );

  static GroupBook fromJson(
    Map<String, Object?> json, {
    required String clientId,
    required ApiClient api,
    required KeyValueStore store,
  }) {
    List<Op> ops(String key) => [
      for (final o in json[key]! as List<Object?>) Op.fromJson(o! as Map<String, Object?>),
    ];
    return GroupBook(
      meta: GroupMeta.fromJson(json['meta']! as Map<String, Object?>),
      clientId: clientId,
      api: api,
      store: store,
      confirmed: ops('confirmed'),
      pending: ops('pending'),
      seq: json['seq']! as int,
    );
  }
}
