import 'package:flutter/material.dart';

/// System Back in onboarding (seam S332): past the first page it steps back
/// a page, as the on-screen arrow does, so the answers stay. On the first
/// page it leaves the route, or runs [onFirstPage] when one is given (adding
/// a profile, which cancels the add).
class OnboardingBack extends StatelessWidget {
  final int page;
  final VoidCallback onPrevious;
  final VoidCallback? onFirstPage;
  final Widget child;

  const OnboardingBack({
    super.key,
    required this.page,
    required this.onPrevious,
    this.onFirstPage,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    // One PopScope for both routes: nested ones would all fire on one Back.
    return PopScope(
      canPop: page == 0 && onFirstPage == null,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (page > 0) {
          onPrevious();
        } else {
          onFirstPage?.call();
        }
      },
      child: child,
    );
  }
}
