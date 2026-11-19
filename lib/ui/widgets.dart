import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import '../theme.dart';

/// Scale-on-press wrapper: gives every tappable thing the same springy feel.
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool haptic;
  const Pressable({super.key, required this.child, this.onTap, this.onLongPress, this.haptic = false});
  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;
  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => setState(() => _down = true) : null,
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onTap == null
          ? null
          : () {
              if (widget.haptic) HapticFeedback.selectionClick();
              widget.onTap!();
            },
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: _down ? 0.95 : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: AnimatedOpacity(
          opacity: enabled ? (_down ? 0.85 : 1) : 0.45,
          duration: const Duration(milliseconds: 110),
          child: widget.child,
        ),
      ),
    );
  }
}

enum BtnKind { primary, secondary, ghost, danger }

class MBtn extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final BtnKind kind;
  final bool wide;
  final bool small;
  const MBtn(this.label, {super.key, this.icon, this.onTap, this.kind = BtnKind.secondary, this.wide = false, this.small = false});

  @override
  Widget build(BuildContext context) {
    final (bg, fg, bd) = switch (kind) {
      BtnKind.primary => (Tk.accent, Colors.white, Colors.transparent),
      BtnKind.secondary => (Tk.field, Tk.text, Tk.border),
      BtnKind.ghost => (Colors.transparent, Tk.dim, Colors.transparent),
      BtnKind.danger => (Tk.danger, const Color(0xFF1A0000), Colors.transparent),
    };
    final h = small ? 30.0 : 38.0;
    return Pressable(
      onTap: onTap,
      haptic: true,
      child: Container(
        height: h,
        width: wide ? double.infinity : null,
        padding: EdgeInsets.symmetric(horizontal: small ? 10 : 14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(Tk.r),
          border: Border.all(color: bd),
        ),
        child: Row(
          mainAxisSize: wide ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[Icon(icon, size: small ? 14 : 16, color: fg), const SizedBox(width: 6)],
            Text(label, style: ts(small ? 13 : 14, w: 500, color: fg)),
          ],
        ),
      ),
    );
  }
}

class MIconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final Color? color;
  final double size;
  const MIconBtn(this.icon, {super.key, this.onTap, this.color, this.size = 38});
  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        haptic: true,
        child: SizedBox(width: size, height: size, child: Icon(icon, size: 20, color: color ?? Tk.dim)),
      );
}

class MCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  final Color? border;
  const MCard({super.key, required this.child, this.padding = const EdgeInsets.all(14), this.color, this.border});
  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: color ?? Tk.card,
          borderRadius: BorderRadius.circular(Tk.rLg),
          border: Border.all(color: border ?? Tk.border),
        ),
        child: child,
      );
}

class Caption extends StatelessWidget {
  final String text;
  const Caption(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 18, 2, 8),
        child: Text(text.toUpperCase(), style: ts(11.5, w: 600, color: Tk.faint).copyWith(letterSpacing: 0.9)),
      );
}

class Pill extends StatelessWidget {
  final String text;
  final Color color;
  const Pill(this.text, this.color, {super.key});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(text, style: ts(11, w: 600, color: color)),
      );
}

/// Blue and red energy orbs orbiting and fusing into a violet core - the app's logo
/// and its "thinking" indicator.
class MugenOrb extends StatefulWidget {
  final double size;
  final bool active;
  const MugenOrb({super.key, this.size = 64, this.active = false});
  @override
  State<MugenOrb> createState() => _MugenOrbState();
}

class _MugenOrbState extends State<MugenOrb> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 7))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) => CustomPaint(
            size: Size.square(widget.size),
            painter: _OrbPainter(_c.value, widget.active),
          ),
        ),
      );
}

class _OrbPainter extends CustomPainter {
  final double t;
  final bool active;
  _OrbPainter(this.t, this.active);

  @override
  void paint(Canvas canvas, Size s) {
    final c = s.center(Offset.zero);
    final r = s.width / 2;
    final a = t * 2 * math.pi * (active ? 3 : 1);
    canvas.saveLayer(Offset.zero & s, Paint());
    // outer haze
    canvas.drawCircle(
        c, r, Paint()..shader = RadialGradient(colors: [Tk.violet.withValues(alpha: 0.30), Colors.transparent]).createShader(Rect.fromCircle(center: c, radius: r)));
    final spread = r * (active ? 0.34 : 0.26) + r * 0.05 * math.sin(a * 2);
    final off = Offset(math.cos(a), math.sin(a)) * spread;
    void orb(Offset p, Color col) {
      final rad = r * 0.52;
      canvas.drawCircle(
          p,
          rad,
          Paint()
            ..blendMode = BlendMode.plus
            ..shader = RadialGradient(colors: [col, col.withValues(alpha: 0.35), Colors.transparent], stops: const [0, 0.55, 1])
                .createShader(Rect.fromCircle(center: p, radius: rad)));
    }

    orb(c + off, Tk.blue);
    orb(c - off, Tk.red);
    final core = r * (0.20 + 0.03 * math.sin(a * 3));
    canvas.drawCircle(
        c,
        core * 2,
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = RadialGradient(colors: [Colors.white.withValues(alpha: 0.9), Tk.violet.withValues(alpha: 0.5), Colors.transparent])
              .createShader(Rect.fromCircle(center: c, radius: core * 2)));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OrbPainter o) => o.t != t || o.active != active;
}

/// Slow drifting blurred light blobs behind the empty chat screen.
class AuraBackground extends StatefulWidget {
  const AuraBackground({super.key});
  @override
  State<AuraBackground> createState() => _AuraState();
}

class _AuraState extends State<AuraBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 24))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: RepaintBoundary(
          child: AnimatedBuilder(animation: _c, builder: (_, __) => CustomPaint(size: Size.infinite, painter: _AuraPainter(_c.value))),
        ),
      );
}

class _AuraPainter extends CustomPainter {
  final double t;
  _AuraPainter(this.t);
  @override
  void paint(Canvas canvas, Size s) {
    final a = t * 2 * math.pi;
    void blob(double fx, double fy, double ph, double radius, Color c) {
      final p = Offset(s.width * (0.5 + 0.38 * math.sin(a * fx + ph)), s.height * (0.34 + 0.22 * math.cos(a * fy + ph)));
      canvas.drawCircle(
          p,
          radius,
          Paint()
            ..shader = RadialGradient(colors: [c.withValues(alpha: 0.20), Colors.transparent]).createShader(Rect.fromCircle(center: p, radius: radius)));
    }

    blob(1, 2, 0, s.width * 0.7, Tk.blue);
    blob(2, 1, 2, s.width * 0.6, Tk.red);
    blob(1, 1, 4, s.width * 0.8, Tk.violet);
  }

  @override
  bool shouldRepaint(_AuraPainter o) => o.t != t;
}

/// Radial shockwave + sparks, played when an APK build succeeds.
class BurstOverlay extends StatefulWidget {
  final ValueNotifier<int> trigger;
  const BurstOverlay({super.key, required this.trigger});
  @override
  State<BurstOverlay> createState() => _BurstState();
}

class _BurstState extends State<BurstOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
  final _rnd = math.Random(7);
  late List<(double, double, Color)> _sparks;

  @override
  void initState() {
    super.initState();
    _sparks = _make();
    widget.trigger.addListener(_go);
  }

  List<(double, double, Color)> _make() => List.generate(
      48, (i) => (_rnd.nextDouble() * 2 * math.pi, 0.4 + _rnd.nextDouble() * 0.6, [Tk.blue, Tk.red, Tk.violet, Colors.white][i % 4]));

  void _go() {
    _sparks = _make();
    HapticFeedback.heavyImpact();
    _c.forward(from: 0);
  }

  @override
  void dispose() {
    widget.trigger.removeListener(_go);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) => _c.isAnimating ? CustomPaint(size: Size.infinite, painter: _BurstPainter(_c.value, _sparks)) : const SizedBox.shrink(),
        ),
      );
}

class _BurstPainter extends CustomPainter {
  final double t;
  final List<(double, double, Color)> sparks;
  _BurstPainter(this.t, this.sparks);
  @override
  void paint(Canvas canvas, Size s) {
    final c = Offset(s.width / 2, s.height * 0.55);
    final e = Curves.easeOutCubic.transform(t);
    final maxR = s.longestSide * 0.7;
    canvas.drawCircle(
        c,
        maxR * e,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 14 * (1 - t) + 1
          ..color = Tk.violet.withValues(alpha: (1 - t) * 0.8));
    canvas.drawCircle(c, maxR * 0.5 * e, Paint()..color = Tk.blue.withValues(alpha: (1 - t) * 0.12));
    for (final (ang, sp, col) in sparks) {
      final d = maxR * 0.9 * sp * e;
      final p = c + Offset(math.cos(ang), math.sin(ang)) * d;
      canvas.drawCircle(p, 3.2 * (1 - t) + 0.5, Paint()..color = col.withValues(alpha: (1 - t)));
    }
  }

  @override
  bool shouldRepaint(_BurstPainter o) => o.t != t;
}

class TypingDots extends StatefulWidget {
  const TypingDots({super.key});
  @override
  State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, __) => Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final v = math.sin((_c.value * 2 * math.pi) - i * 0.9);
            return Container(
              margin: const EdgeInsets.only(right: 4),
              width: 6,
              height: 6,
              transform: Matrix4.translationValues(0, -3 * v.clamp(0, 1), 0),
              decoration: BoxDecoration(color: Color.lerp(Tk.faint, Tk.accentInk, (v + 1) / 2), shape: BoxShape.circle),
            );
          }),
        ),
      );
}

void toast(BuildContext c, String msg, {bool error = false}) {
  ScaffoldMessenger.of(c)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(msg, style: ts(14, color: error ? Tk.danger : Tk.text)),
      duration: Duration(seconds: error ? 6 : 2),
    ));
}
