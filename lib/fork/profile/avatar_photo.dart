import 'dart:io';

import 'package:flutter/material.dart';
import 'package:opennutritracker/core/utils/user_image_storage.dart';

/// Seam S250: a profile photo in a [radius] circle, decoded at the circle's
/// size rather than the photo's (about 5 MB for a 1024 px photo), its path
/// looked up once rather than on every rebuild. A plain circle until then.
// A CircleAvatar's background, not an Image: it resolves again as it
// paints, so a photo picked anew at the same path (S251 clears the cache)
// should show without a restart; not checked on a device.
// shortcut: decoded [radius] * 2 px wide, so a landscape photo's short side
// is a little under the circle; decode by the short side if it looks soft.
class AvatarPhoto extends StatefulWidget {
  final String relativePath;
  final double radius;

  const AvatarPhoto({
    super.key,
    required this.relativePath,
    required this.radius,
  });

  @override
  State<AvatarPhoto> createState() => _AvatarPhotoState();
}

class _AvatarPhotoState extends State<AvatarPhoto> {
  late Future<String> _path = UserImageStorage.absolutePath(
    widget.relativePath,
  );

  @override
  void didUpdateWidget(AvatarPhoto old) {
    super.didUpdateWidget(old);
    if (old.relativePath != widget.relativePath) {
      _path = UserImageStorage.absolutePath(widget.relativePath);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final width = (widget.radius * 2 * MediaQuery.devicePixelRatioOf(context))
        .round();
    return FutureBuilder<String>(
      future: _path,
      builder: (context, snapshot) => CircleAvatar(
        radius: widget.radius,
        backgroundColor: colors.primaryContainer,
        backgroundImage: switch (snapshot.data) {
          final path? => ResizeImage(FileImage(File(path)), width: width),
          null => null,
        },
      ),
    );
  }
}
