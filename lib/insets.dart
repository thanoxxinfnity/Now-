import 'dart:math' as math;
import 'package:material_ui/material_ui.dart';

/// Android 15+ always draws apps edge to edge, and some phones and launchers still report
/// no insets at all, which put buttons under the status bar and the gesture / 3-button bar.
/// Everything about that lives here so it can be tested with simulated bars.

/// Margin used when the system reports no status bar / navigation bar inset at all.
const double fallbackTopInset = 28;
const double fallbackBottomInset = 16;

class ResolvedInsets {
  final EdgeInsets padding;
  final EdgeInsets viewPadding;
  const ResolvedInsets(this.padding, this.viewPadding);
}

/// [rawViewPadding] is the view's own padding in logical pixels (View.viewPadding / devicePixelRatio),
/// the most direct report of the bars when MediaQuery was zeroed by an ancestor.
ResolvedInsets resolveInsets({
  required EdgeInsets padding,
  required EdgeInsets viewPadding,
  required EdgeInsets viewInsets,
  EdgeInsets rawViewPadding = EdgeInsets.zero,
}) {
  var top = math.max(padding.top, math.max(viewPadding.top, rawViewPadding.top));
  var bottom = math.max(padding.bottom, math.max(viewPadding.bottom, rawViewPadding.bottom));
  final keyboard = viewInsets.bottom > 0;
  if (top < 1) top = fallbackTopInset;
  if (bottom < 1 && !keyboard) bottom = fallbackBottomInset;
  return ResolvedInsets(
    // While the keyboard is up it already covers the navigation bar: do not add the bar's height again.
    padding.copyWith(top: top, bottom: keyboard ? padding.bottom : bottom),
    viewPadding.copyWith(top: top, bottom: bottom),
  );
}

/// MaterialApp.builder: gives every route (screens, sheets, dialogs, the drawer) safe margins.
Widget guardInsets(BuildContext context, Widget? child) {
  final mq = MediaQuery.of(context);
  final view = View.of(context);
  final dpr = view.devicePixelRatio;
  final r = resolveInsets(
    padding: mq.padding,
    viewPadding: mq.viewPadding,
    viewInsets: mq.viewInsets,
    rawViewPadding: EdgeInsets.fromLTRB(
      view.viewPadding.left / dpr,
      view.viewPadding.top / dpr,
      view.viewPadding.right / dpr,
      view.viewPadding.bottom / dpr,
    ),
  );
  return MediaQuery(data: mq.copyWith(padding: r.padding, viewPadding: r.viewPadding), child: child ?? const SizedBox.shrink());
}

/// Padding for a scrolling list or sheet body that is NOT inside a SafeArea: keeps the last item
/// above the navigation bar / keyboard and away from a display cutout in landscape.
EdgeInsets scrollPadding(BuildContext context, {double horizontal = 16, double top = 0, double bottom = 24}) {
  final mq = MediaQuery.of(context);
  return EdgeInsets.fromLTRB(
    horizontal + mq.padding.left,
    top,
    horizontal + mq.padding.right,
    bottom + math.max(mq.viewInsets.bottom, mq.padding.bottom),
  );
}
