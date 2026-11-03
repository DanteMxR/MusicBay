import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../models/track.dart';

/// The cover of a track from the server, or a placeholder when it has none.
class ArtworkImage extends StatelessWidget {
  final Track track;
  final double width;
  final double height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final Widget? placeholder;

  const ArtworkImage({
    super.key,
    required this.track,
    required this.width,
    required this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.placeholder,
  });

  @override
  Widget build(BuildContext context) {
    final image = _buildImage(context);
    if (borderRadius == null) return image;
    return ClipRRect(borderRadius: borderRadius!, child: image);
  }

  Widget _buildImage(BuildContext context) {
    final cover = track.albumThumb;
    if (cover == null || !cover.startsWith('http')) {
      return _placeholder(context);
    }
    final cacheDimension = _cacheDimension(context);
    return CachedNetworkImage(
      imageUrl: cover,
      // The link is signed and changes, the picture stays the same.
      cacheKey: '${Uri.parse(cover).path}?$cacheDimension',
      width: width,
      height: height,
      fit: fit,
      memCacheWidth: cacheDimension,
      memCacheHeight: cacheDimension,
      maxWidthDiskCache: cacheDimension,
      maxHeightDiskCache: cacheDimension,
      placeholder: (_, _) => _placeholder(context),
      errorWidget: (_, _, _) => _placeholder(context),
    );
  }

  Widget _placeholder(BuildContext context) {
    if (placeholder != null) {
      return SizedBox(width: width, height: height, child: placeholder!);
    }
    final theme = Theme.of(context);
    return Container(
      width: width,
      height: height,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.album_outlined,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }

  int _cacheDimension(BuildContext context) {
    final devicePixelRatio = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 1;
    final pixels = (math.max(width, height) * devicePixelRatio).round();
    return pixels.clamp(150, 600);
  }
}
