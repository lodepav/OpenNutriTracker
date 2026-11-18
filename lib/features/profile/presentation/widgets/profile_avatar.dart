// [fork] S250 avatar-decode: upstream's photo imports, unused since
// import 'dart:io';
// [/fork]

import 'package:flutter/material.dart';
import 'package:opennutritracker/core/domain/entity/profile_entity.dart';
// [fork] S250 avatar-decode
// import 'package:opennutritracker/core/utils/user_image_storage.dart';
import 'package:opennutritracker/fork/profile/avatar_photo.dart';
// [/fork]

/// Round avatar for a profile: shows the profile picture when one is set,
/// otherwise the first letter of the name, falling back to a person icon
/// for an unnamed profile.
class ProfileAvatar extends StatelessWidget {
  final ProfileEntity profile;
  final double radius;

  const ProfileAvatar({super.key, required this.profile, this.radius = 20});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final imagePath = profile.imagePath;

    if (imagePath != null) {
      // [fork] S250 avatar-decode: decoded at the avatar's size, its path
      // looked up once, not the full photo on every rebuild
      return AvatarPhoto(relativePath: imagePath, radius: radius);
      // [/fork]
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: theme.colorScheme.primaryContainer,
      foregroundColor: theme.colorScheme.onPrimaryContainer,
      child: profile.name.trim().isEmpty
          ? Icon(Icons.person_outline, size: radius)
          : Text(
              profile.name.trim().characters.first.toUpperCase(),
              style: TextStyle(fontSize: radius * 0.9),
            ),
    );
  }
}
