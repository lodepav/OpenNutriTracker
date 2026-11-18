import 'dart:io';

import 'package:flutter/material.dart';
import 'package:opennutritracker/core/utils/user_image_storage.dart';

/// A photo the app stored ([UserImageStorage]) in a [size] dp square,
/// decoded at that size rather than the photo's own (a 1024 px photo is
/// about 5 MB decoded). The path is looked up once, not on each rebuild;
/// [fallback] stands in for a photo that is gone or can't be read.
// shortcut: decoded [size] px wide, so a landscape photo's short side is
// a little under the square; decode by the short side if it looks soft.
class SizedFileImage extends StatefulWidget {
  final String relativePath;
  final double size;
  final WidgetBuilder fallback;

  const SizedFileImage({
    super.key,
    required this.relativePath,
    required this.size,
    required this.fallback,
  });

  @override
  State<SizedFileImage> createState() => _SizedFileImageState();
}

class _SizedFileImageState extends State<SizedFileImage> {
  String? _path;
  var _failed = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(SizedFileImage old) {
    super.didUpdateWidget(old);
    if (old.relativePath != widget.relativePath) _resolve();
  }

  Future<void> _resolve() async {
    final relative = widget.relativePath;
    try {
      final path = await UserImageStorage.absolutePath(relative);
      if (mounted && relative == widget.relativePath) {
        setState(() {
          _path = path;
          _failed = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return widget.fallback(context);
    final path = _path;
    if (path == null) return const SizedBox.shrink();
    final cacheWidth = (widget.size * MediaQuery.devicePixelRatioOf(context))
        .round();
    noteDecodedWidth(path, cacheWidth);
    return Image.file(
      File(path),
      fit: BoxFit.cover,
      width: widget.size,
      height: widget.size,
      cacheWidth: cacheWidth,
      errorBuilder: (context, _, _) => widget.fallback(context),
    );
  }
}

/// The widths each photo, by absolute path, was decoded at here; the
/// image cache keys a resized copy by its width.
final _decodedWidths = <String, Set<int>>{};

/// Notes that the photo at [absolutePath] was decoded [width] wide, so
/// [evictPhoto] drops that copy too.
void noteDecodedWidth(String absolutePath, int width) =>
    (_decodedWidths[absolutePath] ??= {}).add(width);

/// Drops the photo at [relativePath] from the image cache, at its own size
/// and at each size a [SizedFileImage] decoded it, so a new photo saved at
/// the same path shows at once.
Future<void> evictPhoto(String relativePath) async {
  final file = File(await UserImageStorage.absolutePath(relativePath));
  final plain = FileImage(file);
  await plain.evict();
  for (final width in _decodedWidths[file.path] ?? const <int>{}) {
    await ResizeImage(plain, width: width).evict();
  }
}
