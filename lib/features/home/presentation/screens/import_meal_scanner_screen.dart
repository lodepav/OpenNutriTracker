import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:opennutritracker/core/domain/entity/intake_type_entity.dart';
import 'package:opennutritracker/core/presentation/scanner_orientation_mixin.dart';
import 'package:opennutritracker/features/add_meal/presentation/add_meal_type.dart';
import 'package:opennutritracker/features/home/domain/entity/shared_meal_payload.dart';
// [fork] S344 meal-paste-dialog
// import 'package:opennutritracker/features/home/presentation/widgets/shared_meal_import_dialogs.dart';
import 'package:opennutritracker/fork/scan/shared_code_dialog.dart';
// [/fork]
import 'package:opennutritracker/features/home/presentation/widgets/shared_meal_importer.dart';
import 'package:opennutritracker/fork/scan/scan_hint.dart'; // [fork] S296
import 'package:opennutritracker/fork/scan/scanner_error.dart'; // [fork] S296
import 'package:opennutritracker/generated/l10n.dart';


class ImportMealScannerArguments {
  final IntakeTypeEntity intakeTypeEntity;
  final AddMealType addMealType;
  final DateTime day;

  /// QR text already captured by the standard barcode scanner. When set,
  /// the import screen skips its own camera and goes straight to the
  /// confirm dialog so the user doesn't have to point the camera at the
  /// same QR twice.
  final String? initialCode;

  ImportMealScannerArguments(
    this.intakeTypeEntity,
    this.addMealType,
    this.day, {
    this.initialCode,
  });
}

class ImportMealScannerScreen extends StatefulWidget {
  const ImportMealScannerScreen({super.key});

  @override
  State<ImportMealScannerScreen> createState() =>
      _ImportMealScannerScreenState();
}

class _ImportMealScannerScreenState extends State<ImportMealScannerScreen>
    with WidgetsBindingObserver, ScannerOrientationMixin {
  late IntakeTypeEntity _intakeTypeEntity;
  late AddMealType _addMealType;
  late DateTime _day;
  bool _isProcessing = false;
  late final MobileScannerController _cameraController;

  @override
  void initState() {
    super.initState();
    _cameraController = MobileScannerController(
      formats: const [BarcodeFormat.qrCode],
    );
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_cameraController.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_cameraController.value.hasCameraPermission) return;
    switch (state) {
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        unawaited(_cameraController.stop());
      case AppLifecycleState.resumed:
        unawaited(_cameraController.start());
      case AppLifecycleState.inactive:
        break;
    }
  }

  bool _handledInitialCode = false;

  @override
  void didChangeDependencies() {
    final args = ModalRoute.of(context)?.settings.arguments
        as ImportMealScannerArguments;
    _intakeTypeEntity = args.intakeTypeEntity;
    _addMealType = args.addMealType;
    _day = args.day;
    super.didChangeDependencies();

    // If the standard scanner already captured the QR text, jump straight
    // to the confirm dialog instead of opening another camera.
    if (!_handledInitialCode && args.initialCode != null) {
      _handledInitialCode = true;
      _isProcessing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _processCode(args.initialCode!);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(S.of(context).importMealLabel),
        actions: [
          IconButton(
            icon: const Icon(Icons.keyboard_rounded),
            tooltip: S.of(context).pasteCodeLabel,
            onPressed: _showPasteCodeDialog,
          ),
          buildPortraitLockAction(context),
        ],
      ),
      body: MobileScanner(
        controller: _cameraController,
        onDetect: _onDetect,
        // [fork] S296 meal-scanner-camera-refused: a way on, not a black box,
        // and over the feed what to scan
        errorBuilder: (_, error) => ScannerError(
          error: error,
          controller: _cameraController,
          onPaste: _showPasteCodeDialog,
        ),
        overlayBuilder: (_, _) => ScanHint(
          text: 'Point at the QR code from Share meal',
          onPaste: _showPasteCodeDialog,
        ),
        // [/fork]
      ),
    );
  }

  void _onDetect(BarcodeCapture capture) async {
    if (_isProcessing) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null) return;
    // Flip the flag synchronously, before any await, so a second
    // onDetect call queued by mobile_scanner while the QR is still
    // in frame can't pass the gate. Without this, two detections
    // fired in the same microtask window both reach the dialog.
    _isProcessing = true;
    await _processCode(raw);
  }

  Future<void> _showPasteCodeDialog() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    // [fork] S344 meal-paste-dialog: the recipe and workout importers' dialog,
    // so the button says what it does and a bad code says what to do
    // final payload = await showDialog<SharedMealPayload>(
    //   context: context,
    //   builder: (_) => const SharedMealCodeDialog(),
    // );
    // if (!mounted) return;
    // if (payload == null) {
    //   setState(() => _isProcessing = false);
    //   return;
    // }
    // await _processImport((importer) => importer.importPayload(payload));
    final code = await showDialog<String>(
      context: context,
      builder: (_) => SharedCodeDialog(
        hint: 'Paste the shared meal code here',
        actionLabel: 'Import meal',
        invalidLabel: "This isn't a meal code",
        isValid: (code) {
          try {
            SharedMealPayload.fromJsonString(code);
            return true;
          } on SharedMealParseException {
            return false;
          }
        },
      ),
    );
    if (!mounted) return;
    if (code == null) {
      setState(() => _isProcessing = false);
      return;
    }
    await _processCode(code);
    // [/fork]
  }

  Future<void> _processCode(String raw) =>
      _processImport((importer) => importer.importCode(raw));

  Future<void> _processImport(
      Future<bool> Function(SharedMealImporter) action) async {
    setState(() => _isProcessing = true);
    var didPop = false;
    try {
      final importer = SharedMealImporter(
        context,
        _intakeTypeEntity,
        _addMealType,
        _day,
      );
      final imported = await action(importer);
      if (imported && mounted) {
        Navigator.of(context).pop();
        didPop = true;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context).importMealSuccessLabel)),
        );
      }
    } finally {
      // Keep buffered camera detections from reopening the dialog after pop.
      if (mounted && !didPop) {
        setState(() => _isProcessing = false);
      }
    }
  }
}
