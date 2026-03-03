import 'package:flutter/material.dart';
import '../models/track.dart';
import 'artwork_image.dart';

class TrackTile extends StatelessWidget {
  final Track track;
  final bool isPlaying;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Widget? trailing;

  const TrackTile({
    super.key,
    required this.track,
    this.isPlaying = false,
    required this.onTap,
    this.onLongPress,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      tileColor: isPlaying
          ? theme.colorScheme.primary.withValues(alpha: 0.12)
          : Colors.transparent,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 48,
          height: 48,
          child: ArtworkImage(
            track: track,
            width: 48,
            height: 48,
            placeholder: Container(
              color: theme.colorScheme.surfaceContainerHighest,
              child: const Icon(Icons.music_note, size: 24),
            ),
          ),
        ),
      ),
      title: Text(
        track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: isPlaying ? theme.colorScheme.primary : Colors.white,
          fontWeight: isPlaying ? FontWeight.w600 : null,
        ),
      ),
      subtitle: Text(
        track.artist,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: isPlaying
              ? theme.colorScheme.primary.withValues(alpha: 0.7)
              : null,
        ),
      ),
      trailing:
          trailing ??
          Text(
            track.durationFormatted,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}
