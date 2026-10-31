import 'package:flutter/material.dart';

/// Horizontal page slide that only moves already-painted layers.
///
/// A route keeps its page in a [RepaintBoundary], so a translation never
/// repaints page content. Opacity, shadows and blur are left out on purpose:
/// each of those would make every frame of the transition more expensive.
class SlidePageTransitionsBuilder extends PageTransitionsBuilder {
  const SlidePageTransitionsBuilder();

  static const _curve = Curves.easeOutCubic;
  static final _enter = Tween(
    begin: const Offset(1, 0),
    end: Offset.zero,
  ).chain(CurveTween(curve: _curve));
  static final _exit = Tween(
    begin: Offset.zero,
    end: const Offset(-0.25, 0),
  ).chain(CurveTween(curve: _curve));

  @override
  Duration get transitionDuration => const Duration(milliseconds: 240);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 200);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return SlideTransition(
      position: secondaryAnimation.drive(_exit),
      child: SlideTransition(position: animation.drive(_enter), child: child),
    );
  }
}
