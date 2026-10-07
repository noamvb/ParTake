import 'package:flutter/material.dart';

import '../core/library.dart';

/// What the viewer follows: the chamber and/or committees, with an unfollow
/// button on each.
class FollowingScreen extends StatelessWidget {
  const FollowingScreen({super.key, required this.library});

  final Library library;

  static String _label(String key) =>
      key == 'HOC' ? 'House of Commons (chamber)' : key;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: library,
      builder: (context, _) {
        final keys =
            library.follows.where((key) => key != pmQuestionPeriodKey).toList()
              ..sort();
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
}
