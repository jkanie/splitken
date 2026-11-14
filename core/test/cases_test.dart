// Runs every case in spec/cases.json. The React Native app runs the same file
// against its TypeScript copy of these rules.
import 'dart:convert';
import 'dart:io';

import 'package:splitken_core/splitken_core.dart';
import 'package:test/test.dart';

Map<String, Object?> _cases() {
  final file = File('../spec/cases.json');
  return jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
}

List<Map<String, Object?>> _list(Map<String, Object?> all, String key) =>
    (all[key]! as List<Object?>).cast<Map<String, Object?>>();

List<Member> _members(Object? json) => (json! as List<Object?>)
    .map((m) => Member.fromJson(m! as Map<String, Object?>))
    .toList();

Matcher _splitError(String code) =>
    throwsA(isA<SplitError>().having((e) => e.code, 'code', code));

void main() {
  final all = _cases();

  group('split', () {
    for (final c in _list(all, 'split')) {
      test(c['name'], () {
        final expense = Expense.fromJson(c['expense']! as Map<String, Object?>);
        if (c.containsKey('error')) {
          expect(
            () => splitExpense(expense),
            _splitError(c['error']! as String),
          );
        } else {
          final owed = splitExpense(expense);
          expect(owed, c['owed']);
          expect(owed.fold<int>(0, (a, b) => a + b), expense.amountCents);
        }
      });
    }
  });

  group('balances and settle-up', () {
    for (final c in _list(all, 'balances')) {
      test(c['name'], () {
        final members = _members(c['members']);
        final expenses = (c['expenses']! as List<Object?>)
            .map((e) => Expense.fromJson(e! as Map<String, Object?>))
            .toList();
        if (c.containsKey('error')) {
          expect(
            () => balances(members, expenses),
            _splitError(c['error']! as String),
          );
          return;
        }
        final net = balances(members, expenses);
        expect(net, c['net']);
        expect(net.keys.toList(), members.map((m) => m.id).toList());
        final transfers = settleUp(members, net);
        expect(transfers.map((t) => t.toJson()).toList(), c['settle']);

        // Paying the suggested transfers leaves every balance at 0.
        final paid = [
          ...expenses,
          for (final (i, t) in transfers.indexed)
            Expense(
              id: 'settle-$i',
              description: 'Settle',
              amountCents: t.amountCents,
              paidBy: t.from,
              participants: [t.to],
              method: SplitMethod.exact,
              weights: [t.amountCents],
              isTransfer: true,
            ),
        ];
        expect(balances(members, paid).values, everyElement(0));
      });
    }
  });

  group('fold', () {
    for (final c in _list(all, 'fold')) {
      test(c['name'], () {
        final founders = _members(c['founders']);
        final ops = (c['ops']! as List<Object?>)
            .map((o) => Op.fromJson(o! as Map<String, Object?>))
            .toList();
        // Every rotation of the list, forwards and backwards.
        for (var k = 0; k < ops.length; k++) {
          final rotated = [...ops.sublist(k), ...ops.sublist(0, k)];
          for (final order in [rotated, rotated.reversed.toList()]) {
            final state = fold(founders, order);
            expect(state.members.map((m) => m.toJson()).toList(), c['members']);
            expect(state.expenses.map((e) => e.id).toList(), c['expenseIds']);
            expect(
              state.expenses.map((e) => e.amountCents).toList(),
              c['amounts'],
            );
            expect(balances(state.members, state.expenses), c['net']);
          }
        }
      });
    }
  });

  group('parse and format', () {
    for (final c in _list(all, 'parse')) {
      test('parse "${c['text']}"', () {
        final text = c['text']! as String;
        if (c.containsKey('error')) {
          expect(() => parseCents(text), _splitError(c['error']! as String));
        } else {
          expect(parseCents(text), c['cents']);
        }
      });
    }
    for (final c in _list(all, 'format')) {
      test('format ${c['cents']}', () {
        expect(formatCents(c['cents']! as int), c['text']);
      });
    }
  });
}
