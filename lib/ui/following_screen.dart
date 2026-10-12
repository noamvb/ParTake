import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/library.dart';
import '../polls/polls_client.dart';
import '../polls/polls_models.dart';
import '../watch/watch_follows.dart';
import '../watch/watch_models.dart';
import 'follow_editor.dart';
import 'riding_screen.dart';

/// What the viewer follows: the chamber and/or committees, with an unfollow
/// button on each.
class FollowingScreen extends StatefulWidget {
  const FollowingScreen({
    super.key,
    required this.library,
    this.watch,
    this.polls,
  });

  final Library library;
  final WatchFollows? watch;
  final PollsClient? polls;

  @override
  State<FollowingScreen> createState() => _FollowingScreenState();
}

class _FollowingScreenState extends State<FollowingScreen> {
  Library get library => widget.library;
  WatchFollows? get watch => widget.watch;
  Set<String> _mpIds = {};
  Map<String, RidingSummary> _ridings = {};
  int _loadId = 0;

  @override
  void initState() {
    super.initState();
    watch?.addListener(_watchChanged);
    _syncRidings();
  }

  @override
  void didUpdateWidget(FollowingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.watch != watch) {
      oldWidget.watch?.removeListener(_watchChanged);
      watch?.addListener(_watchChanged);
    }
    _syncRidings(force: oldWidget.polls != widget.polls);
  }

  void _watchChanged() {
    setState(() => _syncRidings());
  }

  void _syncRidings({bool force = false}) {
    final ids = {
      for (final follow in watch?.follows ?? <WatchFollow>[])
        if (follow.kind == 'mp' && follow.mp != null) follow.mp!.personId,
    };
    if (!force && setEquals(ids, _mpIds)) return;
    _mpIds = ids;
    _ridings = {};
    final loadId = ++_loadId;
    final polls = widget.polls;
    if (polls != null && ids.isNotEmpty) _loadRidings(polls, loadId);
  }

  Future<void> _loadRidings(PollsClient polls, int loadId) async {
    try {
      final ridings = await polls.ridings();
      if (!mounted || loadId != _loadId) return;
      setState(() {
        _ridings = {
          for (final riding in ridings)
            if (riding.mp != null) riding.mp!.personId: riding,
        };
      });
    } catch (_) {
      // Seat projections are optional; Following stays usable without them.
    }
  }

  @override
  void dispose() {
    watch?.removeListener(_watchChanged);
    super.dispose();
  }

  static String _label(String key) =>
      key == 'HOC' ? 'House of Commons (chamber)' : key;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([library, ?watch]),
      builder: (context, _) {
        final keys =
            library.follows.where((key) => key != pmQuestionPeriodKey).toList()
              ..sort();
        if (watch != null) return _deckList(context, keys, watch!);
        return Column(
          children: [
            SwitchListTile(
              title: const Text('Prime Minister at Question Period'),
              subtitle: const Text(
                "Alert when Carney's itinerary says he will attend, and again when it starts.",
              ),
              value: library.follows.contains(pmQuestionPeriodKey),
              onChanged: (on) => library.setFollowed(pmQuestionPeriodKey, on),
            ),
            Expanded(
              child: keys.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'Follow the chamber or a committee with the star '
                          'on any event.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView(
                      children: [
                        for (final key in keys)
                          ListTile(
                            title: Text(_label(key)),
                            trailing: IconButton(
                              tooltip: 'Unfollow $key',
                              icon: const Icon(Icons.star),
                              onPressed: () => library.setFollowed(key, false),
                            ),
                          ),
                      ],
                    ),
            ),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Alerts for followed items arrive on Android when they go '
                'live.',
                textAlign: TextAlign.center,
              ),
            ),
          ],
        );
      },
    );
  }

  String _subtitle(WatchFollow follow) => switch (follow.kind) {
    'topic' => 'Topic',
    'bill' => 'Bill ${follow.bill?.number ?? ''}',
    'mp' => 'MP · ${follow.mp?.party ?? ''} · ${follow.mp?.riding ?? ''}',
    'votes' =>
      follow.votesFilter == 'party_split'
          ? 'Votes that split a party'
          : 'All votes',
    _ => '',
  };

  Widget _deckList(
    BuildContext context,
    List<String> keys,
    WatchFollows watch,
  ) => ListView(
    children: [
      SwitchListTile(
        title: const Text('Prime Minister at Question Period'),
        subtitle: const Text(
          "Alert when Carney's itinerary says he will attend, and again when it starts.",
        ),
        value: library.follows.contains(pmQuestionPeriodKey),
        onChanged: (on) => library.setFollowed(pmQuestionPeriodKey, on),
      ),
      if (keys.isEmpty)
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Follow the chamber or a committee with the star on any event.',
            textAlign: TextAlign.center,
          ),
        ),
      for (final key in keys)
        ListTile(
          title: Text(_label(key)),
          trailing: IconButton(
            tooltip: 'Unfollow $key',
            icon: const Icon(Icons.star),
            onPressed: () => library.setFollowed(key, false),
          ),
        ),
      const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'Alerts for followed items arrive on Android when they go live.',
          textAlign: TextAlign.center,
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(left: 16, right: 8),
        child: Row(
          children: [
            const Expanded(child: Text('On the Deck')),
            IconButton(
              tooltip: 'Add a follow',
              icon: const Icon(Icons.add),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => FollowEditor(watch: watch),
              ),
            ),
            IconButton(
              tooltip: 'Deck connection',
              icon: const Icon(Icons.settings_ethernet),
              onPressed: () => showDeckConnection(context, watch),
            ),
          ],
        ),
      ),
      if (watch.lastError != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(watch.lastError!),
        ),
      if (watch.lastSyncedAt == null && watch.follows.isEmpty)
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Connect to the Deck to follow topics, bills, MPs and votes.',
          ),
        ),
      for (final follow in watch.follows)
        if (['topic', 'bill', 'mp', 'votes'].contains(follow.kind))
          _followTile(context, watch, follow),
    ],
  );

  Widget _followTile(
    BuildContext context,
    WatchFollows watch,
    WatchFollow follow,
  ) {
    final riding = follow.kind == 'mp' ? _ridings[follow.mp?.personId] : null;
    final delete = IconButton(
      tooltip: 'Remove ${follow.label}',
      icon: const Icon(Icons.delete_outline),
      onPressed: follow.id == null ? null : () => watch.remove(follow.id!),
    );
    return ListTile(
      title: Text(follow.label),
      subtitle: Text(_subtitle(follow)),
      trailing: riding == null
          ? delete
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [RidingStatusChip(riding.status), delete],
            ),
      onTap: riding == null
          ? null
          : () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    RidingScreen(polls: widget.polls!, id: riding.id),
              ),
            ),
    );
  }
}
