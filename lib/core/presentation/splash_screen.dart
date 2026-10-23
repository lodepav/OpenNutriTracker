import 'dart:async';

import 'package:flutter/material.dart';
// [fork] S35 brand: upstream's logo import, unused since
// import 'package:flutter_svg/flutter_svg.dart';
// [/fork]
import 'package:opennutritracker/core/utils/navigation_options.dart';
// [fork] S35 brand
import 'package:opennutritracker/fork/brand/openbite_logo.dart';
// [/fork]

/// First screen shown on launch: the OpenNutriTracker logo with the spoon
/// making a single accelerating-then-settling spin, after which it routes on
/// to the main screen (returning user) or onboarding (first run).
///
/// The native launch screen (Android `launch_background`, iOS
/// `LaunchScreen.storyboard`) paints the same canvas colour behind the Flutter
/// engine while it boots, so the hand-off into this animated splash is seamless.
class SplashScreen extends StatefulWidget {
  /// Whether the user has already completed onboarding. Decides where the
  /// splash routes once the animation finishes.
  final bool userInitialized;

  const SplashScreen({super.key, required this.userInitialized});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  static const _logoSize = 168.0;
  static const _startDelay = Duration(milliseconds: 350);
  static const _spinDuration = Duration(milliseconds: 1700);

  late final AnimationController _controller;
  late final Animation<double> _spin;
  Timer? _startTimer;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _spinDuration);

    // Accelerate in, then decelerate to a stop — mirrors the design mock's
    // cubic-bezier easing (0.45, 0, 0.12, 1). A single full turn (turns: 0 → 1)
    // leaves the spoon back in its original upright position.
    _spin = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(
        parent: _controller, curve: const Cubic(0.45, 0.0, 0.12, 1.0)));

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) _goNext();
    });

    // Honour the OS "reduce motion" setting: skip the spin and move on.
    final reduceMotion = WidgetsBinding.instance.platformDispatcher
        .accessibilityFeatures.disableAnimations;
    if (reduceMotion) {
      _startTimer = Timer(const Duration(milliseconds: 600), _goNext);
    } else {
      // A short beat on the upright logo before the spin begins.
      _startTimer = Timer(_startDelay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  void _goNext() {
    if (_navigated || !mounted) return;
    _navigated = true;
    Navigator.of(context).pushReplacementNamed(widget.userInitialized
        ? NavigationOptions.mainRoute
        : NavigationOptions.onboardingRoute);
  }

  @override
  void dispose() {
    _startTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Center(
        child: SizedBox(
          width: _logoSize,
          height: _logoSize,
          // [fork] S35 brand: OpenBite's page, bitten as the splash plays
          // (was the rings with the spinning spoon)
          child: OpenBiteLogo(bite: _spin),
          // [/fork]
        ),
      ),
    );
  }
}
