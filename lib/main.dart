import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const SpikeApp());
}

class SpikeApp extends StatefulWidget {
  const SpikeApp({super.key});

  @override
  State<SpikeApp> createState() => _SpikeAppState();
}

class _SpikeAppState extends State<SpikeApp> {
  late final player = Player();
  late final controller = VideoController(player);

  String? _error;

  @override
  void initState() {
    super.initState();
    player.stream.error.listen((e) => setState(() => _error = e));
    player.open(
      Media(
        'https://parlvuvod01.azureedge.net/pvvodhoc-fl/_definst_/mp4:azrhoc02/archives/PVHD/2026/2026-09-23/45728_HoC%20Sitting%20No.%20142_14-00-59_VH.mp4/playlist.m3u8?audioindex=2',
      ),
    );
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: Column(
        children: [
          Expanded(child: Video(controller: controller)),
          StreamBuilder<Duration>(
            stream: player.stream.position,
            builder: (context, snap) => Text(
              'SPIKE position=${snap.data?.inSeconds ?? -1}s '
              'buffering=${player.state.buffering} '
              'error=${_error ?? '-'}',
              style: const TextStyle(fontSize: 32),
            ),
          ),
        ],
      ),
    ),
  );
}
