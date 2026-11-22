import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart'; // [fork] S334
import 'package:opennutritracker/core/presentation/sources_screen.dart';
import 'package:opennutritracker/core/presentation/widgets/app_banner_version.dart';
import 'package:opennutritracker/core/utils/app_const.dart';
import 'package:opennutritracker/core/utils/demo/demo_seeder.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/core/utils/url_const.dart';
import 'package:opennutritracker/features/profile/presentation/utils/profile_switch_coordinator.dart';
// [fork] S37 onboarding-restore
import 'package:opennutritracker/fork/backup/onboarding_restore.dart';
// [/fork]
// [fork] S430 demo-one-profile
import 'package:opennutritracker/fork/onboarding/demo_one_profile.dart';
// [/fork]
// [fork] S501 restore-failed-notice
import 'package:opennutritracker/fork/backup/storage_rescue.dart';
// [/fork]
// [fork] S502 policy-link-accent
import 'package:opennutritracker/fork/display/contrast.dart';
// [/fork]
import 'package:opennutritracker/generated/l10n.dart';
import 'package:opennutritracker/core/utils/safe_url_launcher.dart';
// [fork] S590 S591 fork English for stale strings
import 'package:opennutritracker/fork/onboarding/onboarding_copy.dart'
    as fork_copy;
// [/fork]

class OnboardingIntroPageBody extends StatefulWidget {
  const OnboardingIntroPageBody({
    super.key,
    required this.setPageContent,
    this.initialAcceptedPolicy = false,
    this.initialAcceptedDataCollection = false,
    this.onBusy, // [fork] S543
  });

  final Function(bool active, bool acceptedDataCollection) setPageContent;
  final bool initialAcceptedPolicy;
  final bool initialAcceptedDataCollection;

  // [fork] S543 intro-busy-start: told while the demo seeds or a backup
  // restores, so the footer's Start waits too
  final ValueChanged<bool>? onBusy;
  // [/fork]

  @override
  State<OnboardingIntroPageBody> createState() =>
      _OnboardingIntroPageBodyState();
}

class _OnboardingIntroPageBodyState extends State<OnboardingIntroPageBody> {
  late bool _acceptedPolicy = widget.initialAcceptedPolicy;
  late bool _acceptedDataCollection = widget.initialAcceptedDataCollection;
  bool _seedingDemo = false;
  // [fork] S532 intro-one-busy: a restore in flight turns Try demo off
  bool _forkRestoring = false;
  // [/fork]

  // [fork] S470 intro-init: made once, not on every checkbox tap's rebuild
  late final Future<String> _forkVersion = AppConst.getVersionNumber();
  late final TapGestureRecognizer _forkPolicyTap = TapGestureRecognizer()
    ..onTap = _launchUrl;

  @override
  void dispose() {
    _forkPolicyTap.dispose();
    super.dispose();
  }
  // [/fork]

  // [fork] S543 intro-busy-start
  void _forkReportBusy() => widget.onBusy?.call(_seedingDemo || _forkRestoring);
  // [/fork]

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      // [fork] S470 intro-init
      future: _forkVersion,
      // future: AppConst.getVersionNumber(),
      // [/fork]
      builder: (BuildContext context, AsyncSnapshot<dynamic> snapshot) {
        if (snapshot.hasData) {
          // Scroll so the demo CTA + checkboxes still fit on shorter
          // viewports (e.g. the 800×600 surface used by widget tests).
          return SingleChildScrollView(
            child: Column(
              children: [
                // [fork] S501 restore-failed-notice: a backup the recovery
                // screen chose that would not restore is said once
                const RestoreFailedNotice(),
                // [/fork]
                AppBannerVersion(versionNumber: snapshot.requireData),
                const SizedBox(height: 32.0),
                Text(
                  S.of(context).appDescription,
                  style: Theme.of(context).textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32.0),
                Text(
                  S.of(context).onboardingIntroDescription,
                  style: Theme.of(context).textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16.0),
                // Policy first: both Start (footer) and Try Demo require it.
                // [fork] S334 consent-rows: each checkbox and its sentence
                // are one labelled control; the policy link is its action
                MergeSemantics(
                  child: Semantics(
                    customSemanticsActions: {
                      const CustomSemanticsAction(label: 'Open privacy policy'):
                          _launchUrl,
                    },
                    child:
                // [/fork]
                ListTile(
                  onTap: () => _togglePolicy(),
                  title: Text.rich(
                    // [fork] S334 S591: the link is the row's action, not a
                    // node; S591 names the policy once
                    semanticsLabel: fork_copy.policySentence,
                    // [/fork]
                    textAlign: TextAlign.center,
                    TextSpan(
                      // [fork] S543 S591 policy-link-space: the underline began
                      // on the space before the link; S591: the row named the
                      // policy twice ("…privacy policy. Privacy policy")
                      // text: S.of(context).readLabel,
                      text: fork_copy.policyLead,
                      // [/fork]
                      style: Theme.of(context).textTheme.bodySmall,
                      children: [
                        TextSpan(
                          // [fork] S543 S591 policy-link-space
                          // text: ' ${S.of(context).privacyPolicyLabel}',
                          text: fork_copy.policyLink,
                          // [/fork]
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                // [fork] S502 policy-link-accent: a picked
                                // yellow was 1.27:1 on the canvas
                                // color: Theme.of(context).colorScheme.primary,
                                color: textAccent(context),
                                // [/fork]
                                decoration: TextDecoration.underline,
                              ),
                          // [fork] S470 intro-init
                          recognizer: _forkPolicyTap,
                          // recognizer: TapGestureRecognizer()
                          //   ..onTap = () {
                          //     _launchUrl();
                          //   },
                          // [/fork]
                        ),
                        const TextSpan(text: '.'), // [fork] S591
                      ],
                    ),
                  ),
                  leading: Semantics(
                    identifier: 'onboarding-checkbox-privacy',
                    child: Checkbox(
                      value: _acceptedPolicy,
                      onChanged: (value) {
                        if (value != null) {
                          _togglePolicy();
                        }
                      },
                    ),
                  ),
                ),
                // [fork] S334
                  ),
                ),
                MergeSemantics(
                  child:
                // [/fork]
                ListTile(
                  onTap: () => _toggleDataCollection(),
                  title: Text(
                    S.of(context).dataCollectionLabel,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  leading: Semantics(
                    identifier: 'onboarding-checkbox-data',
                    child: Checkbox(
                      value: _acceptedDataCollection,
                      onChanged: (value) => _toggleDataCollection(),
                    ),
                  ),
                ),
                ), // [fork] S334
                const SizedBox(height: 16.0),
                // [fork] S430 demo-one-profile: the demo wipe clears boxes
                // every profile shares, so only a lone profile gets it
                if (canOfferDemo()) ...[
                // [/fork]
                Semantics(
                  identifier: 'onboarding-try-demo',
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      // Stays tappable without the policy so the tap can
                      // explain itself; only the in-flight seed truly
                      // disables it.
                      // [fork] S532 intro-one-busy
                      onPressed: _seedingDemo || _forkRestoring
                          ? null
                          : (_acceptedPolicy ? _tryDemo : _policyRequired),
                      // onPressed: _seedingDemo
                      //     ? null
                      //     : (_acceptedPolicy ? _tryDemo : _policyRequired),
                      // [/fork]
                      // [fork] S451 intro-buttons-contrast: live, so drawn
                      // live; the tap's snackbar names the policy
                      // style: _acceptedPolicy
                      //     ? null
                      //     : OutlinedButton.styleFrom(
                      //         foregroundColor: Theme.of(
                      //           context,
                      //         ).colorScheme.onSurface.withValues(alpha: 0.38),
                      //       ),
                      // [/fork]
                      icon: _seedingDemo
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.visibility_outlined),
                      label: Text(S.of(context).onboardingTryDemoLabel),
                    ),
                  ),
                ),
                const SizedBox(height: 4.0),
                Text(
                  // [fork] S590 demo-caption: it asked for the policy after
                  // the tick
                  // S.of(context).onboardingTryDemoSubtitle,
                  fork_copy.tryDemoSubtitle(acceptedPolicy: _acceptedPolicy),
                  // [/fork]
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4.0),
                Text(
                  S.of(context).onboardingTryDemoDisclaimer,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                ], // [fork] S430
                // [fork] S37 onboarding-restore: start from a backup (#1355)
                const SizedBox(height: 12.0),
                RestoreBackupButton(
                  acceptedPolicy: _acceptedPolicy,
                  acceptedDataCollection: _acceptedDataCollection,
                  // [fork] S532 intro-one-busy: one runs at a time
                  busy: _seedingDemo,
                  onBusy: (busy) {
                    if (mounted) setState(() => _forkRestoring = busy);
                    if (mounted) _forkReportBusy(); // [fork] S543
                  },
                  // [/fork]
                ),
                // [/fork]
                const SizedBox(height: 8.0),
                TextButton.icon(
                  onPressed: () => _openSources(context),
                  icon: const Icon(Icons.menu_book_outlined),
                  label: Text(S.of(context).onboardingIntroSourcesLinkLabel),
                ),
              ],
            ),
          );
        } else {
          return const SizedBox();
        }
      },
    );
  }

  void _togglePolicy() {
    setState(() {
      _acceptedPolicy = !_acceptedPolicy;
      widget.setPageContent(_acceptedPolicy, _acceptedDataCollection);
    });
  }

  void _toggleDataCollection() {
    setState(() {
      _acceptedDataCollection = !_acceptedDataCollection;
      widget.setPageContent(_acceptedPolicy, _acceptedDataCollection);
    });
  }

  void _openSources(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SourcesScreen()));
  }

  /// Says why the demo is unavailable instead of letting the tap fall on the
  /// floor. The subtitle under the button already states the requirement;
  /// this is for the user who tapped anyway.
  void _policyRequired() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(S.of(context).onboardingBlockedDemoPolicySnack)),
      );
  }

  /// Seeds the active profile with sample data and jumps straight to Home.
  /// Requires the privacy-policy checkbox (same bar as Start) so demo entry
  /// still records legal acceptance; anonymous crash reporting stays off
  /// unless the user opts in later from Settings (and is locked while demo
  /// data is active). Data-collection checkbox is intentionally independent.
  Future<void> _tryDemo() async {
    if (!_acceptedPolicy) return;
    setState(() => _seedingDemo = true);
    _forkReportBusy(); // [fork] S543
    try {
      await seedDemoData(DemoSeedOptions.onboarding);
      if (!mounted) return;
      // The screen-persistent tab BLoCs were created before the demo profile
      // existed (or hold another profile's data). Refresh them against the
      // freshly seeded active profile before landing on the main screen —
      // same as the normal onboarding start path (onboarding_screen.dart).
      ProfileSwitchCoordinator.reloadTabBlocs();
      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil(NavigationOptions.mainRoute, (route) => false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _seedingDemo = false);
      _forkReportBusy(); // [fork] S543
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.of(context).onboardingTryDemoError)),
      );
    }
  }

  Future<void> _launchUrl() async {
    // Read the locale before the await; the context must not be touched
    // afterwards without a mounted check.
    final policy = URLConst.privacyPolicyFor(
      Localizations.localeOf(context).languageCode,
    );

    // A device with no browser is the case worth reporting: this link is the
    // only way to read the policy the checkbox below asks you to accept, and
    // silently doing nothing reads as a broken tap.
    final opened = await tryLaunchExternalUrl(policy);

    if (opened || !mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(S.of(context).errorOpeningBrowser)));
  }
}
