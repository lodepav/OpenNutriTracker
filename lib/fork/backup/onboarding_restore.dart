import 'package:flutter/material.dart';
import 'package:opennutritracker/core/data/data_source/user_data_source.dart';
import 'package:opennutritracker/core/domain/usecase/add_config_usecase.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/core/utils/url_const.dart';
import 'package:opennutritracker/features/profile/presentation/utils/profile_switch_coordinator.dart';
import 'package:opennutritracker/features/settings/domain/export_import_failure.dart';
import 'package:opennutritracker/features/settings/domain/usecase/export_data_usecase.dart';
import 'package:opennutritracker/features/settings/presentation/bloc/export_import_bloc.dart';
import 'package:opennutritracker/features/settings/presentation/widgets/export_import_error_text.dart';
import 'package:opennutritracker/fork/backup/after_restore.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// What a restore from onboarding does, apart from the screen.
class OnboardingRestore {
  /// Imports a JSON backup the user picks, as Settings' import does: true
  /// when it was imported, false when the picker was dismissed. Throws when
  /// the file could not be restored.
  Future<bool> importBackup() async {
    final bloc = locator<ExportImportBloc>();
    try {
      bloc.add(const ImportDataEvent(format: ExportFormat.json));
      final done = await bloc.stream.firstWhere(
        (state) => state is! ExportImportLoadingState,
      );
      if (done is ExportImportError) {
        throw ExportImportFailure(done.reason, 'onboarding restore');
      }
      return done is ExportImportSuccess;
    } finally {
      await bloc.close();
    }
  }

  Future<bool> hasProfile() => locator<UserDataSource>().hasUserData();

  /// What finishing onboarding records and a backup leaves out: the policy
  /// the user just accepted, and their crash-report choice.
  Future<void> accept({required bool dataCollection}) async {
    final config = locator<AddConfigUsecase>();
    await config.setConfigHasAcceptedPolicy(true);
    await config.setConfigPolicyNoticeRevisionSeen(URLConst.policyRevision);
    await config.setConfigHasAcceptedAnonymousData(dataCollection);
    // Left set when onboarding was reached from the demo's "Set up your
    // profile"; restored data is the user's own.
    await config.setConfigIsDemoData(false);
  }
}

/// "Restore a backup" on onboarding's first page (seam S37; upstream #1355,
/// ported after review from theoleuthardt's #155, which restores from their
/// WebDAV server; this restores a backup file). Behind the policy checkbox,
/// like "Try demo". A backup with a profile skips the rest of onboarding;
/// one without keeps its data and the setup goes on.
class RestoreBackupButton extends StatefulWidget {
  final bool acceptedPolicy;
  final bool acceptedDataCollection;
  final OnboardingRestore? restore;

  /// Into the app; by default the tab blocs reload and the main route opens.
  final VoidCallback? onRestored;

  /// Something else on the page is running (Try demo): the button is off.
  final bool busy;

  /// Told when a restore starts and ends, so the page can turn Try demo off.
  final ValueChanged<bool>? onBusy;

  const RestoreBackupButton({
    super.key,
    required this.acceptedPolicy,
    required this.acceptedDataCollection,
    this.restore,
    this.onRestored,
    this.busy = false,
    this.onBusy,
  });

  @override
  State<RestoreBackupButton> createState() => _RestoreBackupButtonState();
}

class _RestoreBackupButtonState extends State<RestoreBackupButton> {
  late final _restore = widget.restore ?? OnboardingRestore();
  bool _busy = false;

  void _say(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  Future<void> _run() async {
    setState(() => _busy = true);
    widget.onBusy?.call(true);
    try {
      if (!await _restore.importBackup()) return;
      if (!await _restore.hasProfile()) {
        if (mounted) {
          _say('Restored. The backup has no profile, so finish the setup.');
        }
        return;
      }
      await _restore.accept(dataCollection: widget.acceptedDataCollection);
      if (!mounted) return;
      (widget.onRestored ?? _intoApp)();
    } on ExportImportFailure catch (failure) {
      if (mounted) _say(exportImportErrorText(S.of(context), failure.reason));
    } catch (_) {
      if (mounted) _say('That file could not be restored.');
    } finally {
      if (mounted) setState(() => _busy = false);
      widget.onBusy?.call(false);
    }
  }

  void _intoApp() {
    afterRestore(context);
    ProfileSwitchCoordinator.reloadTabBlocs();
    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil(NavigationOptions.mainRoute, (route) => false);
  }

  @override
  Widget build(BuildContext context) => Semantics(
    identifier: 'onboarding-restore-backup',
    child: SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        key: const Key('fork-onboarding-restore'),
        onPressed: _busy || widget.busy
            ? null
            : (widget.acceptedPolicy
                  ? _run
                  : () =>
                        _say('Accept the privacy policy to restore a backup')),
        icon: _busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.restore_rounded),
        label: const Text('Restore a backup'),
      ),
    ),
  );
}
