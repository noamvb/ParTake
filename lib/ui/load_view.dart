import 'package:flutter/material.dart';
import 'package:parlvu/parlvu.dart';

/// Loads (and reloads, with `refresh: true`) some data of type [T].
typedef AsyncLoader<T> = Future<T> Function({bool refresh});

/// Builds the content shown once [loader] has resolved.
typedef LoadViewBuilder<T> = Widget Function(BuildContext context, T data);

/// Runs [loader], showing a spinner while it is in flight, the built content
/// on success, and an error message with a retry button on failure. Supports
/// pull-to-refresh.
class LoadView<T> extends StatefulWidget {
  const LoadView({super.key, required this.loader, required this.builder});

  final AsyncLoader<T> loader;
  final LoadViewBuilder<T> builder;

  @override
  State<LoadView<T>> createState() => LoadViewState<T>();
}

class LoadViewState<T> extends State<LoadView<T>> {
  bool _loading = true;
  T? _data;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _run(widget.loader());
  }

  /// Reruns the loader and shows its result (or error) once it resolves.
  /// Exposed so a parent holding a `GlobalKey<LoadViewState<T>>` can trigger
  /// a reload from outside (e.g. a periodic timer), in addition to the
  /// built-in retry button and pull-to-refresh.
  void reload({bool refresh = false}) {
    setState(() {
      _loading = true;
      _error = null;
    });
    _run(widget.loader(refresh: refresh));
  }

  /// Runs [future] and applies its outcome, catching any error in the same
  /// synchronous step the future is created in so nothing is ever left
  /// unattended between one microtask and the next.
  Future<void> _run(Future<T> future) async {
    try {
      final data = await future;
      if (!mounted) return;
      setState(() {
        _loading = false;
        _data = data;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  Future<void> _pullToRefresh() => _run(widget.loader(refresh: true));

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final error = _error;
    if (error != null) {
      return _ErrorView(error: error, onRetry: () => reload(refresh: true));
    }
    return RefreshIndicator(
      onRefresh: _pullToRefresh,
      child: widget.builder(context, _data as T),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final err = error;
    String message;
    String? detail;
    if (err is ParlVuFormatException) {
      message = 'ParlVU changed its page format. ParTake needs an update.';
      detail = err.message;
    } else if (err is ParlVuHttpException) {
      message = 'ParlVU returned HTTP ${err.statusCode}.';
    } else {
      message = 'Could not reach ParlVU. Check your connection.';
    }

    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(message, textAlign: TextAlign.center),
                  if (detail != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      detail,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: onRetry,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
