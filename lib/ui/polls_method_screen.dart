import 'package:flutter/material.dart';

import '../polls/polls_method.dart';

class PollsMethodScreen extends StatefulWidget {
  const PollsMethodScreen({super.key, this.section});
  final String? section;

  @override
  State<PollsMethodScreen> createState() => _PollsMethodScreenState();
}

class _PollsMethodScreenState extends State<PollsMethodScreen> {
  final _keys = [for (final _ in pollsMethod) GlobalKey()];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.section == null) return;
      final index = pollsMethod.indexWhere(
        (section) => section.title.startsWith(widget.section!),
      );
      if (index < 0) return;
      final context = _keys[index].currentContext;
      if (context != null) Scrollable.ensureVisible(context, alignment: 0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('How this works')),
      body: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < pollsMethod.length; i++)
                    Padding(
                      key: _keys[i],
                      padding: const EdgeInsets.only(bottom: 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(pollsMethod[i].title, style: theme.titleMedium),
                          for (final block in pollsMethod[i].blocks)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: block.paragraph != null
                                  ? Text(
                                      block.paragraph!,
                                      style: theme.bodyMedium,
                                    )
                                  : Column(
                                      children: [
                                        for (final bullet in block.bullets)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 6,
                                            ),
                                            child: Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  '•  ',
                                                  style: theme.bodyMedium,
                                                ),
                                                Expanded(
                                                  child: Text.rich(
                                                    TextSpan(
                                                      children: [
                                                        if (bullet
                                                            .label
                                                            .isNotEmpty)
                                                          TextSpan(
                                                            text: bullet.label,
                                                            style: TextStyle(
                                                              fontWeight:
                                                                  bullet.bold
                                                                  ? FontWeight
                                                                        .bold
                                                                  : FontWeight
                                                                        .normal,
                                                            ),
                                                          ),
                                                        TextSpan(
                                                          text: bullet.text,
                                                        ),
                                                      ],
                                                    ),
                                                    style: theme.bodyMedium,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                            ),
                        ],
                      ),
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
