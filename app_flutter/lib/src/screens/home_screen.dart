import 'package:material_ui/material_ui.dart';

import '../api_client.dart';
import '../group_book.dart';
import '../library.dart';
import 'group_screen.dart';

/// The groups on this device, with buttons to make or join 1.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.library});

  final Library library;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: library,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('splitken')),
        body: library.books.isEmpty
            ? const Center(child: Text('No groups yet. Make 1, or join 1 with its id.'))
            : ListView(
                children: [
                  for (final book in library.books)
                    ListTile(
                      title: Text(book.meta.name),
                      subtitle: Text(
                        '${book.state.members.length} members, ${book.meta.currency}'
                        '${book.pending.isEmpty ? '' : ', ${book.pending.length} not sent'}',
                      ),
                      onTap: () => _open(context, book),
                    ),
                ],
              ),
        floatingActionButton: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            FloatingActionButton.extended(
              heroTag: 'join',
              onPressed: () => _join(context),
              icon: const Icon(Icons.link),
              label: const Text('Join'),
            ),
            const SizedBox(height: 12),
            FloatingActionButton.extended(
              heroTag: 'new',
              onPressed: () => _create(context),
              icon: const Icon(Icons.group_add),
              label: const Text('New group'),
            ),
          ],
        ),
      ),
    );
  }

  void _open(BuildContext context, GroupBook book) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => GroupScreen(book: book)));
  }

  Future<void> _create(BuildContext context) async {
    final name = TextEditingController();
    final currency = TextEditingController(text: 'CAD');
    final members = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New group'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            TextField(
              controller: currency,
              decoration: const InputDecoration(labelText: 'Currency (3 letters)'),
            ),
            TextField(
              controller: members,
              decoration: const InputDecoration(labelText: 'Members, split by commas'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Make')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await _run(context, () async {
      final names = members.text
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      final book = await library.create(name.text, currency.text.trim().toUpperCase(), names);
      if (context.mounted) _open(context, book);
    });
  }

  Future<void> _join(BuildContext context) async {
    final id = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Join a group'),
        content: TextField(
          controller: id,
          decoration: const InputDecoration(labelText: 'Group id'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Join')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await _run(context, () async {
      final book = await library.join(id.text);
      if (context.mounted) _open(context, book);
    });
  }

  Future<void> _run(BuildContext context, Future<void> Function() action) async {
    final messenger = ScaffoldMessenger.of(context);
    void say(String text) => messenger.showSnackBar(SnackBar(content: Text(text)));
    try {
      await action();
    } on RefusedError catch (e) {
      say(e.message);
    } on OfflineError {
      say('Making or joining a group needs the network.');
    }
  }
}
