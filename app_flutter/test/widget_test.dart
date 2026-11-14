import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:splitken/main.dart';
import 'package:splitken/src/key_value_store.dart';
import 'package:splitken/src/library.dart';

import 'support.dart';

void main() {
  testWidgets('add an expense, see the split, then the settle-up', (tester) async {
    final server = TestServer();
    final library = await tester.runAsync(
      () => Library.load(server.client(), MemoryKeyValueStore()),
    );
    await tester.runAsync(() => library!.create('Trip', 'CAD', ['Ana', 'Ben', 'Cy']));
    await tester.pumpWidget(SplitkenApp(library: library!));

    expect(find.text('Trip'), findsOneWidget);
    expect(find.text('3 members, CAD'), findsOneWidget);
    await tester.tap(find.text('Trip'));
    await tester.pumpAndSettle();
    expect(find.text('No expenses yet.'), findsOneWidget);

    await tester.tap(find.byTooltip('Add an expense'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('description')), 'Pizza');
    await tester.enterText(find.byKey(const Key('amount')), '10');
    await tester.pump();
    expect(find.text('3.34 CAD'), findsOneWidget);
    expect(find.text('3.33 CAD'), findsNWidgets(2));

    await tester.tap(find.text('Shares'));
    await tester.pump();
    expect(find.byKey(const Key('problem')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('weight-m1')), '2');
    await tester.enterText(find.byKey(const Key('weight-m2')), '1');
    await tester.enterText(find.byKey(const Key('weight-m3')), '1');
    await tester.pump();
    expect(find.text('5.00 CAD'), findsOneWidget);
    expect(find.text('2.50 CAD'), findsNWidgets(2));

    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('save')));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(find.text('Pizza'), findsOneWidget);
    expect(find.text('10.00 CAD'), findsOneWidget);

    await tester.tap(find.text('Balances'));
    await tester.pumpAndSettle();
    expect(find.text('+5.00'), findsOneWidget);
    expect(find.text('-2.50'), findsNWidgets(2));
    expect(find.text('Ben pays Ana'), findsOneWidget);
    expect(find.text('Cy pays Ana'), findsOneWidget);
  });

  testWidgets('the home screen with no groups', (tester) async {
    final server = TestServer();
    final library = await tester.runAsync(
      () => Library.load(server.client(), MemoryKeyValueStore()),
    );
    await tester.pumpWidget(SplitkenApp(library: library!));
    expect(find.textContaining('No groups yet'), findsOneWidget);
    expect(find.text('New group'), findsOneWidget);
    expect(find.text('Join'), findsOneWidget);
  });
}
