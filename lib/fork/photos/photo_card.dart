import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:opennutritracker/core/utils/ai_credential_storage.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/add_meal/domain/meal_photo_interpreter.dart';
import 'package:opennutritracker/fork/photos/body_compare.dart';
import 'package:opennutritracker/fork/photos/body_compare_sheet.dart';
import 'package:opennutritracker/core/utils/calc/calendar_day_calc.dart';
import 'package:opennutritracker/core/presentation/widgets/app_card.dart';
import 'package:opennutritracker/core/styles/dimens.dart';
import 'package:opennutritracker/fork/photos/photo_store.dart';
import 'package:opennutritracker/fork/recipe/recipe_delete.dart'
    show destructiveFilledStyle;
import 'package:opennutritracker/fork/trends/card_title.dart';

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

const _thumbWidth = 96.0;

/// A photo with its image file.
typedef ShownPhoto = ({ProgressPhoto photo, File file});

String _date(BuildContext context, DateTime d) =>
    DateFormat.yMMMd(Localizations.localeOf(context).toLanguageTag()).format(d);

/// A photo's spoken name: "Progress photo, Nov 1, 2026".
String _photoName(BuildContext context, DateTime d) =>
    'Progress photo, ${_date(context, d)}';

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
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Dimens.spacing24,
                0,
                Dimens.spacing24,
                Dimens.spacing8,
              ),
              child: Semantics(
                header: true,
                child: Text(
                  'Add a progress photo',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
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
    if (source == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await widget.pick(source);
      if (bytes == null || !mounted) return;
      var date = DateTime.now();
      // A photo from the gallery can be of any day.
      if (source == ImageSource.gallery) {
        final picked = await showDatePicker(
          context: context,
          initialDate: date,
          firstDate: DateTime(2000),
          lastDate: date,
          helpText: 'Photo taken on',
        );
        if (picked == null) return;
        date = picked;
      }
      await _store.add(date, bytes);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't add the photo. Try again.")),
      );
    }
  }

  Future<void> _open(ShownPhoto shown) async {
    final delete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_date(context, shown.photo.date)),
        contentPadding: const EdgeInsets.all(Dimens.spacing8),
        // Decoded no wider than the screen: a full 12 MP photo is about
        // 48 MB. The dialog sizes to its content, which a LayoutBuilder
        // can't report, so the screen's width bounds it.
        // Pinch to zoom: the dialog is small for a body photo.
        content: InteractiveViewer(
          maxScale: 4,
          child: Image.file(
            shown.file,
            semanticLabel: _photoName(context, shown.photo.date),
            cacheWidth: switch ((MediaQuery.sizeOf(context).width *
                    MediaQuery.devicePixelRatioOf(context))
                .round()) {
              > 0 && final width => width,
              _ => null,
            },
            fit: BoxFit.contain,
          ),
        ),
        actions: [
          TextButton(
            key: const ValueKey('photo-delete'),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
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
    if (delete != true || !mounted) return;
    // a photo of a past day can't be taken again
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('Delete this photo?'),
        content: const Text("A photo of that day can't be taken again."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('photo-delete-confirm'),
            style: destructiveFilledStyle(context),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _store.remove(shown.photo.id);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't delete the photo. Try again.")),
      );
    }
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
    // The strip as tall as a photo and its tallest date, wrapped to the
    // photo's width at the user's font: a fixed height cut it at large text.
    var dateHeight = 0.0;
    for (final shown in photos) {
      final dateLine = TextPainter(
        text: TextSpan(
          text: _date(context, shown.photo.date),
          style: theme.textTheme.labelSmall,
        ),
        textScaler: MediaQuery.textScalerOf(context),
        textDirection: Directionality.of(context),
      )..layout(maxWidth: _thumbWidth);
      if (dateLine.height > dateHeight) dateHeight = dateLine.height;
      dateLine.dispose();
    }
    final stripHeight = 128 + dateHeight;
    return AppCard(
      padding: const EdgeInsets.all(Dimens.spacing20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: CardTitle(
                  child: Text(
                    'Progress photos',
                    style: theme.textTheme.titleMedium,
                  ),
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
              if (photos.length > 1) const SizedBox(width: Dimens.spacing8),
              TextButton.icon(
                key: const ValueKey('photo-add'),
                onPressed: _add,
                icon: const Icon(Icons.add_a_photo_outlined),
                label: const Text('Add', semanticsLabel: 'Add photo'),
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
              height: stripHeight,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: photos.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                // Newest first.
                itemBuilder: (context, i) {
                  final shown = photos[photos.length - 1 - i];
                  // One button that says it is a photo, not a bare date.
                  return Semantics(
                    container: true,
                    button: true,
                    label: _photoName(context, shown.photo.date),
                    onTap: () => _open(shown),
                    excludeSemantics: true,
                    child: InkWell(
                      key: ValueKey('photo-${shown.photo.id}'),
                      onTap: () => _open(shown),
                      // The date wraps under its photo: at 200% it ran into the next.
                      child: SizedBox(
                        width: _thumbWidth,
                        child: Column(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.file(
                                shown.file,
                                width: _thumbWidth,
                                height: 128,
                                fit: BoxFit.cover,
                                // At the tile's pixels: 192 wide blurred it
                                // on a dense screen. Height, as body photos
                                // are portrait and the tile covers.
                                cacheHeight:
                                    (128 *
                                            MediaQuery.devicePixelRatioOf(
                                              context,
                                            ))
                                        .round(),
                                errorBuilder: (_, _, _) => const SizedBox(
                                  width: _thumbWidth,
                                  height: 128,
                                  child: Icon(Icons.broken_image_outlined),
                                ),
                              ),
                            ),
                            Text(
                              _date(context, shown.photo.date),
                              style: theme.textTheme.labelSmall,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
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

/// Under this page height (a phone in landscape) Compare photos scrolls.
const _scrollBelowHeight = 480.0;

/// Two progress photos side by side, each picked by date; the oldest and
/// the newest to start. With a model set up, "Ask AI" judges how body
/// composition changed between them.
class ComparePhotosScreen extends StatefulWidget {
  final List<ShownPhoto> photos;

  /// For tests; the app's from the locator, none without its services.
  final CompareBodiesUseCase? useCase;
  final Future<BodyDay> Function(DateTime day) loadDay;

  const ComparePhotosScreen({
    super.key,
    required this.photos,
    this.useCase,
    this.loadDay = loadBodyDay,
  });

  @override
  State<ComparePhotosScreen> createState() => _ComparePhotosScreenState();
}

class _ComparePhotosScreenState extends State<ComparePhotosScreen> {
  late int _left = 0;
  late int _right = widget.photos.length - 1;

  late final _useCase =
      widget.useCase ??
      (locator.isRegistered<AiCredentialStorage>()
          ? CompareBodiesUseCase(locator(), locator<http.Client>())
          : null);
  AiProvider? _provider;
  bool _busy = false;

  /// Asking already, its dialog open or its request out: a second tap
  /// does nothing.
  bool _asking = false;

  /// Each pair's answer, by the earlier and the later photo's ids.
  final _answers = <(String, String), BodyComparison>{};

  @override
  void initState() {
    super.initState();
    _useCase?.selection.then((selection) {
      if (mounted) setState(() => _provider = selection?.provider);
    });
  }

  (ShownPhoto, ShownPhoto) get _pair {
    final a = widget.photos[_left], b = widget.photos[_right];
    return a.photo.date.isAfter(b.photo.date) ? (b, a) : (a, b);
  }

  Future<void> _ask() async {
    if (_asking) return;
    _asking = true;
    try {
      await _askOnce();
    } finally {
      _asking = false;
    }
  }

  Future<void> _askOnce() async {
    final (earlier, later) = _pair;
    final key = (earlier.photo.id, later.photo.id);
    final known = _answers[key];
    if (known != null) return showBodyComparison(context, known);
    final messenger = ScaffoldMessenger.of(context);
    if (earlier.photo.id == later.photo.id) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Pick two different photos.')),
      );
      return;
    }
    final earlierDay = await widget.loadDay(earlier.photo.date);
    final laterDay = await widget.loadDay(later.photo.date);
    if (!mounted ||
        !await confirmBodyCompare(
          context,
          provider: _provider!,
          earlier: earlierDay,
          later: laterDay,
        )) {
      return;
    }
    setState(() => _busy = true);
    try {
      Future<MealPhoto> read(File f) async =>
          MealPhoto(bytes: await f.readAsBytes(), mediaType: 'image/jpeg');
      final (earlierPhoto, laterPhoto) = await (
        read(earlier.file),
        read(later.file),
      ).wait;
      final result = await _useCase!.compare(
        earlier: earlierPhoto,
        later: laterPhoto,
        earlierDay: earlierDay,
        laterDay: laterDay,
      );
      if (!mounted) return;
      if (result == null) {
        // The model was taken off in Settings meanwhile.
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Set up an AI model in Settings to compare.'),
          ),
        );
        return;
      }
      setState(() {
        _answers[key] = result;
        _busy = false;
      });
      await showBodyComparison(context, result);
    } on MealInterpreterException catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            e.failure == MealInterpreterFailure.auth
                ? 'The AI key was refused: check it in Settings.'
                : "Couldn't compare the photos. Try again.",
          ),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text("Couldn't compare the photos. Try again."),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final photos = widget.photos;
    final days = CalendarDayCalc.daysBetween(
      photos[_left].photo.date,
      photos[_right].photo.date,
    ).abs();
    final (earlier, later) = _pair;
    final answered = _answers.containsKey((earlier.photo.id, later.photo.id));
    // At large text the AI label pushes the title into "Compare ph…".
    final aiBelow = MediaQuery.textScalerOf(context).scale(10) >= 13;
    final stacked = _datesCut(context);
    final ai = _provider == null
        ? null
        : TextButton.icon(
            key: const ValueKey('compare-ai'),
            onPressed: _busy ? null : _ask,
            icon: const Icon(Icons.auto_awesome_outlined),
            label: Text(answered ? 'AI result' : 'Ask AI'),
          );
    // Stacked, each picker shows the photo it sets; side by side, it is
    // only spoken.
    final left = _picker(
      'compare-left',
      _left,
      _right,
      (i) => _left = i,
      label: 'Left photo',
      shown: stacked,
    );
    final right = _picker(
      'compare-right',
      _right,
      _left,
      (i) => _right = i,
      label: 'Right photo',
      shown: stacked,
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Compare photos'),
        actions: [if (!aiBelow) ?ai],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) =>
              _body(box, days, ai, aiBelow, stacked, left, right),
        ),
      ),
    );
  }

  /// Short, as in landscape, the page scrolls and each photo is given the
  /// page's height; else the photos fill what the pickers leave.
  Widget _body(
    BoxConstraints box,
    int days,
    Widget? ai,
    bool aiBelow,
    bool stacked,
    Widget left,
    Widget right,
  ) {
    final scrolls = box.maxHeight < _scrollBelowHeight;
    final photos = Padding(
      padding: const EdgeInsets.symmetric(horizontal: Dimens.spacing16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _side(_left, stacked ? null : left),
          const SizedBox(width: Dimens.spacing12),
          _side(_right, stacked ? null : right),
        ],
      ),
    );
    final column = Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(Dimens.spacing8),
          child: Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: Dimens.spacing8,
            children: [Text('$days days apart'), if (aiBelow) ?ai],
          ),
        ),
        if (_busy)
          const LinearProgressIndicator(semanticsLabel: 'Comparing the photos'),
        if (stacked)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Dimens.spacing16,
              0,
              Dimens.spacing16,
              Dimens.spacing8,
            ),
            child: Column(
              children: [
                left,
                const SizedBox(height: Dimens.spacing8),
                right,
              ],
            ),
          ),
        if (scrolls)
          SizedBox(height: box.maxHeight, child: photos)
        else
          Expanded(child: photos),
      ],
    );
    return scrolls
        ? SingleChildScrollView(
            key: const ValueKey('compare-scroll'),
            child: column,
          )
        : column;
  }

  /// Whether the longest date overflows a half-width picker at the user's
  /// text size; a wrapped date was cut to "Nov 1," on a phone.
  bool _datesCut(BuildContext context) {
    final style = Theme.of(context).textTheme.titleMedium;
    final scaler = MediaQuery.textScalerOf(context);
    final widest = widget.photos
        .map((s) {
          final painter = TextPainter(
            text: TextSpan(text: _date(context, s.photo.date), style: style),
            textScaler: scaler,
            textDirection: Directionality.of(context),
            maxLines: 1,
          )..layout();
          final width = painter.width;
          painter.dispose();
          return width;
        })
        .fold(0.0, math.max);
    // The page's gutters and the gap, then the field's padding and arrow.
    final half =
        (MediaQuery.sizeOf(context).width -
                2 * Dimens.spacing16 -
                Dimens.spacing12) /
            2 -
        2 * Dimens.spacing12 -
        24 -
        Dimens.spacing8;
    return widest > half;
  }

  /// The date picker of one side, without [other]'s photo: comparing a
  /// photo with itself says nothing.
  Widget _picker(
    String key,
    int index,
    int other,
    void Function(int) set, {
    required String label,
    required bool shown,
  }) => Semantics(
    // Once: a shown label is the field's own name already.
    label: shown ? null : label,
    child:
        // Aligned, the menu opens as wide as its field instead of past it to
        // the screen edge.
        ButtonTheme(
          alignedDropdown: true,
          child: DropdownButtonFormField<int>(
            key: ValueKey(key),
            // Within its half of the page: a long date overflowed it at 200%.
            isExpanded: true,
            // Unset, a date wraps to two lines at large text instead of cutting.
            itemHeight: null,
            initialValue: index,
            // Outlined, so the two pickers read as separate controls.
            decoration: InputDecoration(
              labelText: shown ? label : null,
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: Dimens.spacing12,
                vertical: Dimens.spacing8,
              ),
            ),
            items: [
              for (final (i, s) in widget.photos.indexed)
                // Its own value stays, as the picker must hold it.
                if (i == index || i != other)
                  DropdownMenuItem(
                    value: i,
                    child: Text(_date(context, s.photo.date)),
                  ),
            ],
            onChanged: (i) {
              if (i != null) setState(() => set(i));
            },
          ),
        ),
  );

  Widget _side(int index, Widget? picker) => Expanded(
    child: Column(
      children: [
        ?picker,
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: Dimens.spacing8),
            // Decoded at the width shown, not the photo's full size.
            child: LayoutBuilder(
              builder: (context, box) => Image.file(
                widget.photos[index].file,
                semanticLabel: _photoName(
                  context,
                  widget.photos[index].photo.date,
                ),
                cacheWidth: box.maxWidth.isFinite && box.maxWidth > 0
                    ? (box.maxWidth * MediaQuery.devicePixelRatioOf(context))
                          .round()
                    : null,
                fit: BoxFit.contain,
                alignment: Alignment.topCenter,
                errorBuilder: (_, _, _) =>
                    const Center(child: Icon(Icons.broken_image_outlined)),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
