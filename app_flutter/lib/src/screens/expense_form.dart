import 'package:material_ui/material_ui.dart';
import 'package:splitken_core/splitken_core.dart';

import '../group_book.dart';
import '../ids.dart';

/// Adds an expense, or changes [editing]. The split is worked out as the
/// user types, with the same rules the server checks.
class ExpenseForm extends StatefulWidget {
  const ExpenseForm({super.key, required this.book, this.editing});

  final GroupBook book;
  final Expense? editing;

  @override
  State<ExpenseForm> createState() => _ExpenseFormState();
}

class _ExpenseFormState extends State<ExpenseForm> {
  late final TextEditingController _description;
  late final TextEditingController _amount;
  late String _paidBy;
  late SplitMethod _method;
  late final Set<String> _participants;
  final Map<String, TextEditingController> _weights = {};

  List<Member> get _members => widget.book.state.members;

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    _description = TextEditingController(text: e?.description ?? '');
    _amount = TextEditingController(text: e == null ? '' : formatCents(e.amountCents));
    _paidBy = e?.paidBy ?? _members.first.id;
    _method = e?.method ?? SplitMethod.equal;
    _participants = {...(e?.participants ?? _members.map((m) => m.id))};
    for (final m in _members) {
      final at = e?.participants.indexOf(m.id) ?? -1;
      final weight = at >= 0 && e!.weights.isNotEmpty ? e.weights[at] : null;
      _weights[m.id] = TextEditingController(
        text: weight == null ? '' : _showWeight(e!.method, weight),
      );
    }
  }

  @override
  void dispose() {
    _description.dispose();
    _amount.dispose();
    for (final c in _weights.values) {
      c.dispose();
    }
    super.dispose();
  }

  static String _showWeight(SplitMethod method, int weight) =>
      method == SplitMethod.shares ? '$weight' : formatCents(weight);

  /// Reads 1 weight: whole shares, or an amount or percent with up to 2
  /// decimals (12.5 % is 1250 basis points, as 12.50 is 1250 cents).
  static int _readWeight(SplitMethod method, String text) {
    final t = text.trim();
    if (t.isEmpty) return 0;
    if (method == SplitMethod.shares) {
      final n = int.tryParse(t);
      if (n == null || n < 0) throw SplitError('bad_split', 'Shares are whole numbers.');
      return n;
    }
    final match = RegExp(r'^(\d{1,8})(?:\.(\d{1,2}))?$').firstMatch(t);
    if (match == null) throw SplitError('bad_split', '"$t" is not a number with up to 2 decimals.');
    return int.parse(match.group(1)!) * 100 + int.parse((match.group(2) ?? '').padRight(2, '0'));
  }

  /// The expense as typed so far. Throws a [SplitError] when it is not valid.
  Expense _build() {
    final ordered = [
      for (final m in _members)
        if (_participants.contains(m.id)) m.id,
    ];
    return Expense(
      id: widget.editing?.id ?? randomId(),
      description: _description.text.trim(),
      amountCents: parseCents(_amount.text),
      paidBy: _paidBy,
      participants: ordered,
      method: _method,
      weights: _method == SplitMethod.equal
          ? const []
          : [for (final id in ordered) _readWeight(_method, _weights[id]!.text)],
    );
  }

  Future<void> _save() async {
    try {
      await widget.book.saveExpense(_build());
      if (mounted) Navigator.of(context).pop();
    } on SplitError catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Map<String, int>? parts;
    String? problem;
    try {
      final expense = _build();
      final split = splitExpense(expense);
      parts = {for (var i = 0; i < split.length; i++) expense.participants[i]: split[i]};
    } on SplitError catch (e) {
      problem = e.message;
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.editing == null ? 'New expense' : 'Change expense'),
        actions: [TextButton(key: const Key('save'), onPressed: _save, child: const Text('Save'))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            key: const Key('description'),
            controller: _description,
            decoration: const InputDecoration(labelText: 'What was it for'),
            onChanged: (_) => setState(() {}),
          ),
          TextField(
            key: const Key('amount'),
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'Amount (${widget.book.meta.currency})'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _paidBy,
            decoration: const InputDecoration(labelText: 'Paid by'),
            items: [for (final m in _members) DropdownMenuItem(value: m.id, child: Text(m.name))],
            onChanged: (id) => setState(() => _paidBy = id!),
          ),
          const SizedBox(height: 12),
          SegmentedButton<SplitMethod>(
            segments: const [
              ButtonSegment(value: SplitMethod.equal, label: Text('Equal')),
              ButtonSegment(value: SplitMethod.exact, label: Text('Exact')),
              ButtonSegment(value: SplitMethod.shares, label: Text('Shares')),
              ButtonSegment(value: SplitMethod.percent, label: Text('%')),
            ],
            selected: {_method},
            onSelectionChanged: (s) => setState(() => _method = s.single),
          ),
          for (final m in _members)
            Row(
              children: [
                Expanded(
                  child: CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(m.name),
                    subtitle: Text(
                      parts?[m.id] == null
                          ? ''
                          : '${formatCents(parts![m.id]!)} ${widget.book.meta.currency}',
                      key: Key('part-${m.id}'),
                    ),
                    value: _participants.contains(m.id),
                    onChanged: (on) =>
                        setState(() => on! ? _participants.add(m.id) : _participants.remove(m.id)),
                  ),
                ),
                if (_method != SplitMethod.equal && _participants.contains(m.id))
                  SizedBox(
                    width: 96,
                    child: TextField(
                      key: Key('weight-${m.id}'),
                      controller: _weights[m.id],
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        hintText: switch (_method) {
                          SplitMethod.exact => '0.00',
                          SplitMethod.shares => '1',
                          _ => '%',
                        },
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
              ],
            ),
          if (problem != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                problem,
                key: const Key('problem'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    );
  }
}
