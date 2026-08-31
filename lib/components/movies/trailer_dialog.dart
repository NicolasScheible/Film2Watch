import 'package:flutter/material.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

import '../../theme/app_theme.dart';

/// Zeigt einen YouTube-Trailer als kleines Popup (§9: "öffnet den
/// YouTube-Trailer als kleines Popup") - eingebettet über
/// `youtube_player_flutter`, kein externes Öffnen der YouTube-App/des
/// Browsers.
class TrailerDialog extends StatefulWidget {
  const TrailerDialog({super.key, required this.youtubeKey});

  final String youtubeKey;

  static Future<void> show(BuildContext context, String youtubeKey) {
    return showDialog<void>(
      context: context,
      builder: (_) => TrailerDialog(youtubeKey: youtubeKey),
    );
  }

  @override
  State<TrailerDialog> createState() => _TrailerDialogState();
}

class _TrailerDialogState extends State<TrailerDialog> {
  late final YoutubePlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = YoutubePlayerController.fromVideoId(
      videoId: widget.youtubeKey,
      autoPlay: true,
    );
  }

  @override
  void dispose() {
    _controller.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.all(20),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: YoutubePlayer(controller: _controller),
        ),
      ),
    );
  }
}
