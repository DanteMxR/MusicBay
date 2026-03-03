import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../models/track.dart';

class ArtworkImage extends StatefulWidget {
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
  State<ArtworkImage> createState() => _ArtworkImageState();
}

class _ArtworkImageState extends State<ArtworkImage> {
  static final Dio _dio = Dio();
  static final Map<String, String?> _fallbackCache = {};

  bool _useFallback = false;

  @override
  Widget build(BuildContext context) {
    final image = _buildImage(context);
    if (widget.borderRadius == null) return image;
    return ClipRRect(borderRadius: widget.borderRadius!, child: image);
  }

  Widget _buildImage(BuildContext context) {
    if (!_useFallback && _isValidHttp(widget.track.albumThumb)) {
      return CachedNetworkImage(
        imageUrl: widget.track.albumThumb!,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        placeholder: (_, _) => _placeholder(context),
        errorWidget: (_, _, _) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _useFallback = true);
          });
          return _placeholder(context);
        },
      );
    }

    return FutureBuilder<String?>(
      future: _resolveFallbackArtwork(widget.track),
      builder: (context, snapshot) {
        final url = snapshot.data;
        if (_isValidHttp(url)) {
          return CachedNetworkImage(
            imageUrl: url!,
            width: widget.width,
            height: widget.height,
            fit: widget.fit,
            placeholder: (_, _) => _placeholder(context),
            errorWidget: (_, _, _) => _placeholder(context),
          );
        }
        return _placeholder(context);
      },
    );
  }

  Widget _placeholder(BuildContext context) {
    if (widget.placeholder != null) return widget.placeholder!;
    final theme = Theme.of(context);
    return Container(
      width: widget.width,
      height: widget.height,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.album_outlined,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }

  static bool _isValidHttp(String? value) {
    if (value == null || value.isEmpty) return false;
    final lower = value.toLowerCase();
    return lower.startsWith('https://') || lower.startsWith('http://');
  }

  static Future<String?> _resolveFallbackArtwork(Track track) async {
    final cacheKey = '${track.artist}|${track.title}'.toLowerCase();
    if (_fallbackCache.containsKey(cacheKey)) {
      return _fallbackCache[cacheKey];
    }

    try {
      final query = Uri.encodeQueryComponent('${track.artist} ${track.title}');
      final response = await _dio.get(
        'https://itunes.apple.com/search?term=$query&entity=song&limit=1',
        options: Options(responseType: ResponseType.plain),
      );

      final raw = response.data;
      final body = raw is String ? jsonDecode(raw) : raw;
      final results = (body['results'] as List?) ?? const [];
      if (results.isEmpty) {
        _fallbackCache[cacheKey] = null;
        return null;
      }

      String? url = results.first['artworkUrl100']?.toString();
      if (url != null) {
        url = url
            .replaceAll('100x100bb', '600x600bb')
            .replaceAll('100x100', '600x600');
      }

      _fallbackCache[cacheKey] = url;
      return url;
    } catch (_) {
      _fallbackCache[cacheKey] = null;
      return null;
    }
  }
}
