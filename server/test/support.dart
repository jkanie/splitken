import 'dart:convert';

import 'package:shelf/shelf.dart';

/// Calls [handler] in process and decodes the JSON answer.
Future<(int, Map<String, Object?>)> call(
  Handler handler,
  String method,
  String path, [
  Object? body,
]) async {
  final response = await handler(
    Request(
      method,
      Uri.parse('http://localhost$path'),
      body: body == null ? null : (body is String ? body : jsonEncode(body)),
    ),
  );
  final text = await response.readAsString();
  return (
    response.statusCode,
    text.isEmpty
        ? <String, Object?>{}
        : jsonDecode(text) as Map<String, Object?>,
  );
}

Map<String, Object?> expenseOp(
  String opId,
  String clientId,
  int lamport,
  String id,
  int cents,
  String paidBy,
  List<String> participants,
) => {
  'opId': opId,
  'clientId': clientId,
  'lamport': lamport,
  'kind': 'expense',
  'expense': {
    'id': id,
    'description': 'Expense $id',
    'amountCents': cents,
    'paidBy': paidBy,
    'participants': participants,
    'method': 'equal',
    'weights': <int>[],
    'isTransfer': false,
  },
};

Map<String, Object?> memberOp(
  String opId,
  String clientId,
  int lamport,
  String id,
  String name,
) => {
  'opId': opId,
  'clientId': clientId,
  'lamport': lamport,
  'kind': 'member',
  'member': {'id': id, 'name': name},
};
