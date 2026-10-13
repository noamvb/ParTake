import 'package:flutter/foundation.dart';

/// What this build offers. Windows is viewer only: it has no Deck (so no
/// Watch or Polls tab) and no Android alerts (so no Following tab or follow
/// stars), and it checks GitHub for newer releases.
class AppFeatures {
  const AppFeatures({
    this.deck = true,
    this.following = true,
    this.updateCheck = false,
  });

  /// The viewer-only set used on Windows.
  static const viewerOnly = AppFeatures(
    deck: false,
    following: false,
    updateCheck: true,
  );

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
