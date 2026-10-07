import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'player_session.dart';

/// A single session's video floats above the shell's navigation bar.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key, required this.session, required this.onExpand});

  final PlayerSession session;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session,
    builder: (context, _) => SizedBox(
      width: min(MediaQuery.sizeOf(context).width * .55, 320),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Material(
          color: Colors.black,
          elevation: 8,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              InkWell(
                onTap: onExpand,
                child: IgnorePointer(child: session.video(compact: true)),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: .7),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: session.controller.playing ? 'Pause' : 'Play',
                        color: Colors.white,
                        icon: Icon(
                          session.controller.playing
                              ? Icons.pause
                              : Icons.play_arrow,
                        ),
                        onPressed: () =>
                            unawaited(session.controller.togglePlay()),
                      ),
                      IconButton(
                        tooltip: 'Close player',
                        color: Colors.white,
                        icon: const Icon(Icons.close),
                        onPressed: () => unawaited(session.close()),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
