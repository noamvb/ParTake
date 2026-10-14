import 'package:flutter/foundation.dart';

final pollsSnapshotUrl = Uri.parse(
  'https://raw.githubusercontent.com/noamvb/ParTake/polls-data/',
);

/// What this build offers. Windows is viewer only: no Watch tab, Polls from
/// the public snapshot, and no Android alerts (so no Following tab or follow
/// stars), and it checks GitHub for newer releases.
class AppFeatures {
  const AppFeatures({
    this.deck = true,
    this.following = true,
    this.updateCheck = false,
    this.pollsSnapshot,
  });

  /// The viewer-only set used on Windows.
  static final viewerOnly = AppFeatures(
    deck: false,
    following: false,
    updateCheck: true,
    pollsSnapshot: pollsSnapshotUrl,
  );

  /// When set, the Polls tab reads this public snapshot instead of the Deck
  /// and is shown even without [deck].
  final Uri? pollsSnapshot;

  /// Watch and Polls tabs, and the Deck connection behind them.
  final bool deck;

  /// The Following tab and the follow star on event tiles.
  final bool following;

  /// The "update available" banner.
  final bool updateCheck;

  static AppFeatures forPlatform() =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows
      ? viewerOnly
      : const AppFeatures();
}
