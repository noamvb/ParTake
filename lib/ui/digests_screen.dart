part of 'watch_screen.dart';

String _digestTitle(WatchDigestSummary digest) {
  final morning = digest.kind == 'morning';
  final day = morning ? parliamentDate(digest.createdAt) : digest.date;
  final kind = morning ? 'Morning' : 'Evening';
  return '$kind digest, ${_weekdays[day.weekday - 1]} ${day.day} '
      '${_months[day.month - 1]}';
}

/// The digests the Deck has built, newest first.
class DigestsScreen extends StatefulWidget {
  const DigestsScreen({
    super.key,
    required this.watch,
    required this.onOpen,
    this.now,
    this.openLink,
  });

  /// Null when no Deck is set up.
  final WatchFollows? watch;
  final OpenEvent onOpen;

  /// Defaults to [DateTime.now] when null.
  final DateTime Function()? now;

  /// Defaults to opening the link in the browser.
  final Future<bool> Function(Uri uri)? openLink;

  @override
  State<DigestsScreen> createState() => _DigestsScreenState();
}

class _DigestsScreenState extends State<DigestsScreen> {
  List<WatchDigestSummary>? _digests;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.watch != null) unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _digests = null;
      _error = null;
    });
    try {
      final digests = await widget.watch!.digests();
      if (mounted) setState(() => _digests = digests);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _digests = const [];
        _error = _message(error);
      });
    }
  }

  void _openDigest(WatchDigestSummary digest) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => _DigestScreen(
        watch: widget.watch!,
        id: digest.id,
        title: _digestTitle(digest),
        now: widget.now,
        onOpen: widget.onOpen,
        openLink: widget.openLink,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Digests')),
    body: widget.watch == null ? _noDeck() : _body(),
  );

  Widget _body() {
    final digests = _digests;
    final error = _error;
    if (error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(error, textAlign: TextAlign.center),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (digests == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (digests.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(_noDigestsText, textAlign: TextAlign.center),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: digests.length,
      itemBuilder: (context, index) {
        final digest = digests[index];
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 6),
          child: ListTile(
            title: Text(_digestTitle(digest)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${digest.items} items'),
                if (digest.replaces != null)
                  const Text('Updated with the official record'),
              ],
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openDigest(digest),
          ),
        );
      },
    );
  }
}

/// One digest: a header per follow, then that follow's items as feed cards.
class _DigestScreen extends StatefulWidget {
  const _DigestScreen({
    required this.watch,
    required this.id,
    required this.title,
    required this.now,
    required this.onOpen,
    required this.openLink,
  });

  final WatchFollows watch;
  final String id;
  final String title;
  final DateTime Function()? now;
  final OpenEvent onOpen;
  final Future<bool> Function(Uri uri)? openLink;

  @override
  State<_DigestScreen> createState() => _DigestScreenState();
}

class _DigestScreenState extends State<_DigestScreen> {
  final _expanded = <String>{};
  WatchDigest? _digest;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _digest = null;
      _error = null;
    });
    try {
      final digest = await widget.watch.digest(widget.id);
      if (mounted) setState(() => _digest = digest);
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    }
  }

  Future<bool> _open(Uri uri) => (widget.openLink ?? _launchExternal)(uri);

  /// Playing a moment leaves the digests behind, so the player is not
  /// opened under them.
  void _watch(OpenRequest request) {
    final onOpen = widget.onOpen;
    Navigator.of(context).popUntil((route) => route.isFirst);
    onOpen(request);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final digest = _digest;
    final error = _error;
    final now = (widget.now ?? DateTime.now)();
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(error, textAlign: TextAlign.center),
                  TextButton(onPressed: _load, child: const Text('Retry')),
                ],
              ),
            )
          : digest == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              children: [
                if (digest.opinion != null)
                  ListTile(
                    leading: const Icon(Icons.bar_chart),
                    title: const Text('Polls'),
                    subtitle: Text(digest.opinion!),
                  ),
                for (final section in digest.sections) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 16, bottom: 4),
                    child: Text(
                      section.label,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  for (final item in section.items)
                    _FeedCard(
                      item: item,
                      follows: widget.watch.follows,
                      now: now,
                      expanded: _expanded.contains(item.id),
                      onToggle: () => setState(() {
                        if (!_expanded.remove(item.id)) _expanded.add(item.id);
                      }),
                      onWatch: _watch,
                      onOpen: (url) => _open(Uri.parse(url)),
                    ),
                ],
              ],
            ),
    );
  }
}
