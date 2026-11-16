import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:splitken_core/splitken_core.dart';

import '../group_book.dart';
import 'expense_form.dart';

/// 1 group: its expenses, balances with settle-up payments, members.
class GroupScreen extends StatelessWidget {
  const GroupScreen({super.key, required this.book});

  final GroupBook book;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: book,
      builder: (context, _) => DefaultTabController(
        length: 3,
        child: Scaffold(
          appBar: AppBar(
            title: Text(book.meta.name),
            actions: [
              IconButton(
                tooltip: 'Copy the group id to share',
                icon: const Icon(Icons.share),
                onPressed: () => Clipboard.setData(ClipboardData(text: book.meta.id)),
              ),
              IconButton(
                tooltip: book.pending.isEmpty ? 'Sync' : 'Sync (${book.pending.length} not sent)',
                icon: Badge(
                  isLabelVisible: book.pending.isNotEmpty,
                  label: Text('${book.pending.length}'),
                  child: book.syncing
                      ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator())
                      : const Icon(Icons.sync),
                ),
                onPressed: book.syncing ? null : book.sync,
              ),
            ],
            bottom: const TabBar(
              tabs: [
                Tab(text: 'Expenses'),
                Tab(text: 'Balances'),
                Tab(text: 'Members'),
              ],
            ),
          ),
          body: Column(
            children: [
              if (book.lastProblem != null)
                MaterialBanner(
                  content: Text(book.lastProblem!),
                  actions: [TextButton(onPressed: book.sync, child: const Text('Try again'))],
                ),
              Expanded(
                child: TabBarView(
                  children: [
                    _Expenses(book: book),
                    _Balances(book: book),
                    _Members(book: book),
                  ],
                ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton(
            tooltip: 'Add an expense',
            onPressed: () =>
                Navigator.of(context)
                    .push(MaterialPageRoute<void>(builder: (_) => ExpenseForm(book: book))),
            child: const Icon(Icons.add),
          ),
        ),
      ),
    );
  }
}

class _Expenses extends StatelessWidget {
  const _Expenses({required this.book});

  final GroupBook book;

  @override
  Widget build(BuildContext context) {
    final expenses = book.state.expenses.reversed.toList();
    if (expenses.isEmpty) return const Center(child: Text('No expenses yet.'));
    return ListView(
      children: [
        for (final e in expenses)
          ListTile(
            leading: Icon(e.isTransfer ? Icons.swap_horiz : Icons.receipt_long),
            title: Text(e.description),
            subtitle: Text('${book.memberName(e.paidBy)} paid'),
            trailing: Text('${formatCents(e.amountCents)} ${book.meta.currency}'),
            onTap: e.isTransfer
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ExpenseForm(book: book, editing: e),
                    ),
                  ),
            onLongPress: () => book.deleteExpense(e.id),
          ),
      ],
    );
  }
}

class _Balances extends StatelessWidget {
  const _Balances({required this.book});

  final GroupBook book;

  @override
  Widget build(BuildContext context) {
    final settle = book.settle;
    final spent = book.spent;
    return ListView(
      children: [
        ListTile(title: Text('Spent ${formatCents(spent.spentCents)} ${book.meta.currency}')),
        for (final m in book.state.members)
          ListTile(
            title: Text(m.name),
            subtitle: Text(
              'Paid ${formatCents(spent.paid[m.id]!)}, share ${formatCents(spent.share[m.id]!)}',
            ),
            trailing: Text(
              '${book.net[m.id]! > 0 ? '+' : ''}${formatCents(book.net[m.id]!)}',
              style: TextStyle(
                color: book.net[m.id]! < 0 ? Colors.red.shade700 : Colors.green.shade700,
              ),
            ),
          ),
        const Divider(),
        ListTile(title: Text(settle.isEmpty ? 'Everyone is settled.' : 'To settle up')),
        for (final t in settle)
          ListTile(
            title: Text('${book.memberName(t.from)} pays ${book.memberName(t.to)}'),
            subtitle: Text('${formatCents(t.amountCents)} ${book.meta.currency}'),
            trailing: TextButton(
              onPressed: () => book.recordTransfer(t),
              child: const Text('Mark paid'),
            ),
          ),
      ],
    );
  }
}

class _Members extends StatefulWidget {
  const _Members({required this.book});

  final GroupBook book;

  @override
  State<_Members> createState() => _MembersState();
}

class _MembersState extends State<_Members> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        for (final m in widget.book.state.members) ListTile(title: Text(m.name)),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Add a member'),
                ),
              ),
              IconButton(
                tooltip: 'Add',
                icon: const Icon(Icons.person_add),
                onPressed: () async {
                  try {
                    await widget.book.addMember(_name.text);
                    _name.clear();
                  } on SplitError catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text(e.message)));
                    }
                  }
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}
