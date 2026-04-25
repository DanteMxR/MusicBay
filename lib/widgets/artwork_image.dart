import 'dart:convert';
import 'dart:math' as math;
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
  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
    ),
  );
  static const int _maxCacheSize = 100;
  static const Duration _cacheTtl = Duration(hours: 24);
  static final Map<String, _FallbackEntry> _fallbackCache = {};

  bool _useFallback = false;
  late Future<String?> _fallbackFuture;

  @override
  void initState() {
    super.initState();
    _fallbackFuture = _resolveFallbackArtwork(
      widget.track,
      requestedSize: _fallbackArtworkSize(),
    );
  }

  @override
  void didUpdateWidget(covariant ArtworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_trackSignature(oldWidget.track) == _trackSignature(widget.track)) {
      return;
    }
    _useFallback = false;
    _fallbackFuture = _resolveFallbackArtwork(
      widget.track,
      requestedSize: _fallbackArtworkSize(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final image = _buildImage(context);
    if (widget.borderRadius == null) return image;
    return ClipRRect(borderRadius: widget.borderRadius!, child: image);
  }

  Widget _buildImage(BuildContext context) {
    if (!_useFallback && _isValidHttp(widget.track.albumThumb)) {
      return _buildCachedNetworkImage(
        context,
        widget.track.albumThumb!,
        errorWidget: (_, _, _) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_useFallback) {
              setState(() => _useFallback = true);
            }
          });
          return _placeholder(context);
        },
      );
    }

    return FutureBuilder<String?>(
      future: _fallbackFuture,
      builder: (context, snapshot) {
        final url = snapshot.data;
        if (_isValidHttp(url)) {
          return _buildCachedNetworkImage(
            context,
            url!,
            errorWidget: (_, _, _) => _placeholder(context),
          );
        }
        return _placeholder(context);
      },
    );
  }

  Widget _buildCachedNetworkImage(
    BuildContext context,
    String imageUrl, {
    required LoadingErrorWidgetBuilder errorWidget,
  }) {
    final cacheDimension = _cacheDimension(context);
    return CachedNetworkImage(
      imageUrl: imageUrl,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      memCacheWidth: cacheDimension,
      memCacheHeight: cacheDimension,
      maxWidthDiskCache: cacheDimension,
      maxHeightDiskCache: cacheDimension,
      placeholder: (_, _) => _placeholder(context),
      errorWidget: errorWidget,
    );
  }

  Widget _placeholder(BuildContext context) {
    if (widget.placeholder != null) {
      return SizedBox(
        width: widget.width,
        height: widget.height,
        child: widget.placeholder!,
      );
    }
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

  static Future<String?> _resolveFallbackArtwork(
    Track track, {
    required int requestedSize,
  }) async {
    final cacheKey = '${track.artist}|${track.title}|$requestedSize'
        .toLowerCase();
    final now = DateTime.now();
    final existing = _fallbackCache[cacheKey];
    if (existing != null && now.difference(existing.cachedAt) < _cacheTtl) {
      return existing.url;
    }

    if (_fallbackCache.length >= _maxCacheSize) {
      final keysToRemove = _fallbackCache.keys
          .take(_maxCacheSize ~/ 4)
          .toList();
      for (final key in keysToRemove) {
        _fallbackCache.remove(key);
      }
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
        _fallbackCache[cacheKey] = _FallbackEntry(null, now);
        return null;
      }

      String? url = results.first['artworkUrl100']?.toString();
      if (url != null) {
        final size = requestedSize.clamp(100, 600);
        url = url
            .replaceAll('100x100bb', '${size}x${size}bb')
            .replaceAll('100x100', '${size}x$size');
      }

      _fallbackCache[cacheKey] = _FallbackEntry(url, now);
      return url;
    } catch (_) {
      _fallbackCache[cacheKey] = _FallbackEntry(null, now);
      return null;
    }
  }

  String _trackSignature(Track track) {
    return '${track.ownerId}_${track.id}|${track.artist}|${track.title}|${track.albumThumb ?? ''}';
  }

  int _cacheDimension(BuildContext context) {
    final devicePixelRatio = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 1;
    final logicalSize = math.max(widget.width, widget.height);
    final pixels = (logicalSize * devicePixelRatio).round();
    return pixels.clamp(150, 600);
  }

  int _fallbackArtworkSize() {
    final logicalSize = math.max(widget.width, widget.height);
    return (logicalSize * 2).round().clamp(150, 600);
  }
}

class _FallbackEntry {
  final String? url;
  final DateTime cachedAt;
  const _FallbackEntry(this.url, this.cachedAt);
}
