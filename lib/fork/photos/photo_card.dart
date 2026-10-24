import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:opennutritracker/core/utils/calc/calendar_day_calc.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/fork/photos/photo_store.dart';

/// Takes or picks a photo, scaled down to keep backups small; null when
/// cancelled.
typedef PickPhoto = Future<List<int>?> Function(ImageSource source);

Future<List<int>?> _pickWithImagePicker(ImageSource source) async {
  final picked = await ImagePicker().pickImage(
    source: source,
    maxWidth: 1440,
    maxHeight: 1440,
    imageQuality: 85,
  );
  return picked?.readAsBytes();
}

/// A photo with its image file.
typedef ShownPhoto = ({ProgressPhoto photo, File file});

String _date(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Seam S40: progress photos on Trends, kept on the device and in the
/// backup. A strip of thumbnails, each opening to view or delete, and a
/// side-by-side compare of any two.
class ProgressPhotosCard extends StatefulWidget {
  final PhotoStore? store;
  final PickPhoto pick;

  const ProgressPhotosCard({
    super.key,
    this.store,
    this.pick = _pickWithImagePicker,
  });

  @override
  State<ProgressPhotosCard> createState() => _ProgressPhotosCardState();
}

class _ProgressPhotosCardState extends State<ProgressPhotosCard> {
  late final _store = widget.store ?? PhotoStore();
  late Future<List<ShownPhoto>> _photos = _load();

  @override
  void initState() {
    super.initState();
    PhotoStore.changes.addListener(_reload);
  }

  @override
  void dispose() {
    PhotoStore.changes.removeListener(_reload);
    super.dispose();
  }

  /// An unreadable store shows the empty card rather than an error.
  Future<List<ShownPhoto>> _load() async {
    try {
      return [
        for (final p in await _store.all())
          (photo: p, file: await _store.file(p)),
      ];
    } catch (_) {
      return [];
    }
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      _photos = _load();
    });
  }

  Future<void> _add() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const ValueKey('photo-camera'),
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              key: const ValueKey('photo-gallery'),
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from the gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final bytes = await widget.pick(source);
    if (bytes == null) return;
    await _store.add(DateTime.now(), bytes);
  }

  Future<void> _open(ShownPhoto shown) async {
    final delete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_date(shown.photo.date)),
        contentPadding: const EdgeInsets.all(Dimens.spacing8),
        content: Image.file(shown.file, fit: BoxFit.contain),
        actions: [
          TextButton(
            key: const ValueKey('photo-delete'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    if (delete == true) await _store.remove(shown.photo.id);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<ShownPhoto>>(
    future: _photos,
    builder: (context, snapshot) {
      final photos = snapshot.data;
      if (photos == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: Dimens.spacing16),
        child: _card(context, photos),
      );
    },
  );

  Widget _card(BuildContext context, List<ShownPhoto> photos) {
    final theme = Theme.of(context);
    return AppCard(
      padding: const EdgeInsets.all(Dimens.spacing20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Progress photos',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              if (photos.length > 1)
                TextButton(
                  key: const ValueKey('photo-compare'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ComparePhotosScreen(photos: photos),
                    ),
                  ),
                  child: const Text('Compare'),
                ),
              TextButton.icon(
                key: const ValueKey('photo-add'),
                onPressed: _add,
                icon: const Icon(Icons.add_a_photo_outlined),
                label: const Text('Add'),
              ),
            ],
          ),
          if (photos.isEmpty)
            Text(
              'Photos stay on this phone and in your backups. Take one now '
              'and then every few weeks to compare.',
              style: theme.textTheme.bodySmall,
            )
          else
            SizedBox(
              height: 150,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: photos.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                // Newest first.
                itemBuilder: (context, i) {
                  final shown = photos[photos.length - 1 - i];
                  return InkWell(
                    key: ValueKey('photo-${shown.photo.id}'),
                    onTap: () => _open(shown),
                    child: Column(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            shown.file,
                            width: 96,
                            height: 128,
                            fit: BoxFit.cover,
                            cacheWidth: 192,
                            errorBuilder: (_, _, _) => const SizedBox(
                              width: 96,
                              height: 128,
                              child: Icon(Icons.broken_image_outlined),
                            ),
                          ),
                        ),
                        Text(
                          _date(shown.photo.date),
                          style: theme.textTheme.labelSmall,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// Two progress photos side by side, each picked by date; the oldest and
/// the newest to start.
class ComparePhotosScreen extends StatefulWidget {
  final List<ShownPhoto> photos;

  const ComparePhotosScreen({super.key, required this.photos});

  @override
  State<ComparePhotosScreen> createState() => _ComparePhotosScreenState();
}

class _ComparePhotosScreenState extends State<ComparePhotosScreen> {
  late int _left = 0;
  late int _right = widget.photos.length - 1;

  @override
  Widget build(BuildContext context) {
    final photos = widget.photos;
    final days = CalendarDayCalc.daysBetween(
      photos[_left].photo.date,
      photos[_right].photo.date,
    ).abs();
    return Scaffold(
      appBar: AppBar(title: const Text('Compare photos')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(Dimens.spacing8),
              child: Text('$days days apart'),
            ),
            Expanded(
              child: Row(
                children: [
                  _side('compare-left', _left, (i) => _left = i),
                  _side('compare-right', _right, (i) => _right = i),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _side(String key, int index, void Function(int) set) => Expanded(
    child: Column(
      children: [
        DropdownButton<int>(
          key: ValueKey(key),
          value: index,
          items: [
            for (final (i, s) in widget.photos.indexed)
              DropdownMenuItem(value: i, child: Text(_date(s.photo.date))),
          ],
          onChanged: (i) {
            if (i != null) setState(() => set(i));
          },
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Image.file(
              widget.photos[index].file,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) =>
                  const Center(child: Icon(Icons.broken_image_outlined)),
            ),
          ),
        ),
      ],
    ),
  );
}
