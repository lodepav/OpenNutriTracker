import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:opennutritracker/core/utils/ai_credential_storage.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/add_meal/domain/meal_photo_interpreter.dart';
import 'package:opennutritracker/features/add_meal/util/meal_photo_encoder.dart';
import 'package:opennutritracker/fork/label/label_scan.dart';

/// "Read label" in the custom-meal form's app bar (seam S29): a photo of
/// the nutrition label fills the form. Hidden when no model is set up.
/// [onRead] also gets the photo as a JPEG, kept in memory only, which
/// Open Food Facts may get as the nutrition picture if the user agrees (S33).
class LabelScanButton extends StatefulWidget {
  final void Function(LabelReading reading, Uint8List? photoJpeg) onRead;
  final ReadLabelUseCase? useCase;

  const LabelScanButton({super.key, required this.onRead, this.useCase});

  @override
  State<LabelScanButton> createState() => _LabelScanButtonState();
}

class _LabelScanButtonState extends State<LabelScanButton> {
  // None where the app's services are not set up, as in widget tests.
  late final _useCase =
      widget.useCase ??
      (locator.isRegistered<AiCredentialStorage>()
          ? ReadLabelUseCase(locator(), locator<http.Client>())
          : null);
  bool _available = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _useCase?.selection.then((selection) {
      if (mounted) setState(() => _available = selection != null);
    });
  }

  Future<void> _scan() async {
    final useCase = _useCase!;
    final selection = await useCase.selection;
    if (selection == null) return;
    final picked = await ImagePicker().pickImage(source: ImageSource.camera);
    if (picked == null || !mounted) return;
    setState(() => _busy = true);
    String? message;
    try {
      final jpeg = await MealPhotoEncoder.encode(
        picked.path,
        format: MealPhotoFormat.jpeg,
      );
      final photo = await MealPhotoEncoder.encodeAndDiscardSource(
        picked.path,
        format: MealPhotoFormat.forProvider(selection.provider),
      );
      final reading = photo == null ? null : await useCase.read(photo);
      if (reading == null || reading.isEmpty) {
        message = 'No nutrition label could be read in the photo';
      } else {
        widget.onRead(reading, jpeg?.bytes);
      }
    } on MealInterpreterException {
      message = 'Could not read the label; try again';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (message != null && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) => !_available
      ? const SizedBox.shrink()
      : IconButton(
          key: const Key('fork-label-scan'),
          tooltip: 'Read nutrition label',
          icon: _busy
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.document_scanner_outlined),
          onPressed: _busy ? null : _scan,
        );
}
