import 'package:flutter/material.dart';

import '../watch/watch_client.dart';
import '../watch/watch_follows.dart';
import '../watch/watch_models.dart';

class FollowEditor extends StatefulWidget {
  const FollowEditor({super.key, required this.watch});
  final WatchFollows watch;

  @override
  State<FollowEditor> createState() => _FollowEditorState();
}

class _FollowEditorState extends State<FollowEditor> {
  final _english = TextEditingController();
  final _french = TextEditingController();
  final _keywords = TextEditingController();
  final _query = TextEditingController();
  String? _choice;
  String? _error;
  bool _busy = false;
  List<WatchBill> _bills = [];
  List<WatchMember> _members = [];

  @override
  void dispose() {
    _english.dispose();
    _french.dispose();
    _keywords.dispose();
    _query.dispose();
    super.dispose();
  }

  Future<void> _add(WatchFollow follow) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    await widget.watch.add(follow);
    if (!mounted) return;
    if (widget.watch.lastError == null) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _busy = false;
        _error = widget.watch.lastError;
      });
    }
  }

  Future<void> _search(String query) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_choice == 'Bill') {
        final bills = await widget.watch.bills(query.trim());
        if (!mounted) return;
        setState(() => _bills = bills);
      } else {
        final members = await widget.watch.members(query.trim());
        if (!mounted) return;
        setState(() => _members = members);
      }
    } on WatchHttpException catch (error) {
      if (mounted) {
        setState(
          () => _error = error.status == 0
              ? 'Deck unreachable'
              : 'Deck error ${error.status}',
        );
      }
    } on WatchUnauthorized {
      if (mounted) setState(() => _error = 'Wrong token');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _topic() {
    final phrase = _english.text.trim();
    if (phrase.isEmpty) {
      setState(() => _error = 'English phrase is required');
      return;
    }
    _add(
      WatchFollow(
        kind: 'topic',
        label: phrase,
        topic: WatchTopic(
          en: phrase,
          fr: _french.text.trim(),
          keywords: _keywords.text
              .split(',')
              .map((k) => k.trim())
              .where((k) => k.isNotEmpty)
              .toList(),
          threshold: 0.55,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(_choice == null ? 'Add a follow' : 'Follow $_choice'),
    scrollable: true,
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_choice == null)
            for (final choice in ['Topic', 'Bill', 'MP', 'Votes'])
              ListTile(
                title: Text(choice),
                onTap: () => setState(() => _choice = choice),
              ),
          if (_choice == 'Topic') ...[
            TextField(
              controller: _english,
              decoration: const InputDecoration(labelText: 'English phrase'),
            ),
            TextField(
              controller: _french,
              decoration: const InputDecoration(labelText: 'French phrase'),
            ),
            TextField(
              controller: _keywords,
              decoration: const InputDecoration(
                labelText: 'Keywords (comma-separated)',
              ),
            ),
          ],
          if (_choice == 'Bill' || _choice == 'MP')
            TextField(
              controller: _query,
              decoration: const InputDecoration(labelText: 'Search'),
              textInputAction: TextInputAction.search,
              onSubmitted: _busy ? null : _search,
            ),
          if (_choice == 'Bill')
            for (final bill in _bills)
              ListTile(
                title: Text(bill.number),
                subtitle: Text(bill.title),
                onTap: _busy
                    ? null
                    : () => _add(
                        WatchFollow(
                          kind: 'bill',
                          label: bill.number,
                          bill: WatchBillRef(
                            id: bill.id,
                            number: bill.number,
                            title: bill.title,
                          ),
                        ),
                      ),
              ),
          if (_choice == 'MP')
            for (final member in _members)
              ListTile(
                title: Text(member.name),
                subtitle: Text('${member.party} · ${member.riding}'),
                onTap: _busy
                    ? null
                    : () => _add(
                        WatchFollow(
                          kind: 'mp',
                          label: member.name,
                          mp: WatchMpRef(
                            personId: member.personId,
                            name: member.name,
                            party: member.party,
                            riding: member.riding,
                          ),
                        ),
                      ),
              ),
          if (_choice == 'Votes')
            for (final entry in {
              'all': 'All votes',
              'party_split': 'Votes that split a party',
            }.entries)
              ListTile(
                title: Text(entry.value),
                onTap: _busy
                    ? null
                    : () => _add(
                        WatchFollow(
                          kind: 'votes',
                          label: entry.value,
                          votesFilter: entry.key,
                        ),
                      ),
              ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(12),
              child: CircularProgressIndicator(),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      if (_choice == 'Topic')
        TextButton(onPressed: _busy ? null : _topic, child: const Text('Add')),
    ],
  );
}

Future<void> showDeckConnection(BuildContext context, WatchFollows watch) =>
    showDialog<void>(
      context: context,
      builder: (_) => _DeckConnection(watch: watch),
    );

class _DeckConnection extends StatefulWidget {
  const _DeckConnection({required this.watch});
  final WatchFollows watch;
  @override
  State<_DeckConnection> createState() => _DeckConnectionState();
}

class _DeckConnectionState extends State<_DeckConnection> {
  late final _address = TextEditingController(text: widget.watch.address);
  late final _token = TextEditingController(text: widget.watch.token);
  bool _saving = false;

  @override
  void dispose() {
    _address.dispose();
    _token.dispose();
    super.dispose();
  }

  String get _status {
    final watch = widget.watch;
    if (watch.lastError != null) return watch.lastError!;
    final at = watch.lastSyncedAt;
    if (at == null) return 'Not connected';
    return 'Synced ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.watch,
    builder: (context, _) => AlertDialog(
      title: const Text('Deck connection'),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _address,
            decoration: const InputDecoration(labelText: 'Deck address'),
            keyboardType: TextInputType.url,
          ),
          TextField(
            controller: _token,
            decoration: const InputDecoration(labelText: 'Token'),
            obscureText: true,
          ),
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(_status),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _saving
              ? null
              : () async {
                  setState(() => _saving = true);
                  await widget.watch.configure(
                    address: _address.text,
                    token: _token.text,
                  );
                  if (!mounted) return;
                  setState(() => _saving = false);
                },
          child: const Text('Save'),
        ),
      ],
    ),
  );
}
