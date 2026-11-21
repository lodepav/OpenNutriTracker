// [fork] S408 food-photo-local: a food's own photo is a file
import 'dart:io';

// [/fork]
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/user_image_storage.dart'; // [fork] S408
import 'package:opennutritracker/features/meal_detail/presentation/widgets/meal_placeholder.dart';

class ImageFullScreen extends StatefulWidget {
  static const fullScreenHeroTag = 'fullScreenTag';

  const ImageFullScreen({super.key});

  @override
  State<ImageFullScreen> createState() => _ImageFullScreenState();
}

class _ImageFullScreenState extends State<ImageFullScreen> {
  late String imageUrl;
  // [fork] S408 food-photo-local: the photo's file, when it is the user's
  Future<String>? _localPath;
  // [/fork]

  @override
  void didChangeDependencies() {
    final args =
        ModalRoute.of(context)?.settings.arguments as ImageFullScreenArguments;
    imageUrl = args.imageUrl;
    // [fork] S408 food-photo-local
    final local = args.localImagePath;
    // kept across rebuilds, so a MediaQuery change doesn't reload the file
    if (local != null) _localPath ??= UserImageStorage.absolutePath(local);
    // [/fork]
    super.didChangeDependencies();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(elevation: 0, backgroundColor: Colors.transparent),
      body: InteractiveViewer(
        child: Hero(
          tag: ImageFullScreen.fullScreenHeroTag,
          // [fork] S408 food-photo-local
          // child: CachedNetworkImage(
          child: _localPath != null
              ? FutureBuilder<String>(
                  future: _localPath,
                  builder: (context, snapshot) => snapshot.hasData
                      ? Image.file(
                          File(snapshot.data!),
                          width: double.infinity,
                          height: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const MealPlaceholder(),
                        )
                      : const MealPlaceholder(),
                )
              : CachedNetworkImage(
          // [/fork]
            width: double.infinity,
            height: double.infinity,
            cacheManager: locator<CacheManager>(),
            imageUrl: imageUrl,
            fit: BoxFit.cover,
            placeholder: (context, string) => const MealPlaceholder(),
            errorWidget: (context, url, error) => const MealPlaceholder(),
          ),
        ),
      ),
    );
  }
}

class ImageFullScreenArguments {
  final String imageUrl;
  // [fork] S408 food-photo-local: the user's photo, relative to the app's
  // documents (`UserImageStorage`); shown instead of [imageUrl]
  final String? localImagePath;
  // [/fork]

  // [fork] S408 food-photo-local
  // ImageFullScreenArguments(this.imageUrl);
  ImageFullScreenArguments(this.imageUrl, {this.localImagePath});
  // [/fork]
}
