import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import '../theme.dart';

/// Original, abstract take on the signature moves of two anime duelists:
/// Limitless (blue / red / hollow purple) and the King of Curses (dismantle / cleave / shrine).
enum Technique {
  blue('Cursed Technique: Blue', Color(0xFF3D8BFF)),
  red('Reversal: Red', Color(0xFFFF4D5E)),
  purple('Hollow Purple', Color(0xFF9B6BFF)),
  dismantle('Dismantle', Color(0xFFFFFFFF)),
  cleave('Cleave', Color(0xFFFF6A5A)),
  shrine('Malevolent Shrine', Color(0xFFFF2D3D));

  final String label;
  final Color color;
  const Technique(this.label, this.color);
}

double _ease(double t) => Curves.easeOutCubic.transform(t.clamp(0.0, 1.0));
double _seg(double t, double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0);

void _glow(Canvas c, Offset p, double r, Color col, double a) {
  if (r <= 0 || a <= 0) return;
  c.drawCircle(
      p,
      r,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = RadialGradient(colors: [col.withValues(alpha: a), col.withValues(alpha: a * 0.35), Colors.transparent], stops: const [0, 0.5, 1])
            .createShader(Rect.fromCircle(center: p, radius: r)));
}

void _slash(Canvas c, Offset a, Offset b, double width, Color col, double alpha) {
  if (alpha <= 0) return;
  final d = b - a;
  final n = Offset(-d.dy, d.dx) / d.distance;
  final mid = (a + b) / 2;
  final path = Path()
    ..moveTo(a.dx, a.dy)
    ..quadraticBezierTo(mid.dx + n.dx * width, mid.dy + n.dy * width, b.dx, b.dy)
    ..quadraticBezierTo(mid.dx - n.dx * width * 0.2, mid.dy - n.dy * width * 0.2, a.dx, a.dy);
  c.drawPath(path, Paint()..color = col.withValues(alpha: alpha * 0.5)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
  c.drawPath(path, Paint()..color = Colors.white.withValues(alpha: alpha));
}

class TechniquePainter extends CustomPainter {
  final Technique tech;
  final double t; // 0..1
  TechniquePainter(this.tech, this.t);

  @override
  void paint(Canvas canvas, Size s) {
    final c = s.center(Offset.zero);
    final R = s.shortestSide / 2;
    canvas.saveLayer(Offset.zero & s, Paint());
    switch (tech) {
      case Technique.blue:
        _blue(canvas, s, c, R);
      case Technique.red:
        _red(canvas, s, c, R);
      case Technique.purple:
        _purple(canvas, s, c, R);
      case Technique.dismantle:
        _dismantle(canvas, s, c, R);
      case Technique.cleave:
        _cleave(canvas, s, c, R);
      case Technique.shrine:
        _shrine(canvas, s, c, R);
    }
    canvas.restore();
  }

  // Everything is pulled into a point.
  void _blue(Canvas g, Size s, Offset c, double R) {
    const n = 54;
    final pull = _ease(t);
    for (var i = 0; i < n; i++) {
      final base = (i % 9) / 9;
      final r = R * (0.25 + 0.95 * base) * (1 - pull * 0.85) + 6;
      final a = i * 2.399 + t * 9 * (1.4 - base) + pull * 6;
      final p = c + Offset(math.cos(a), math.sin(a)) * r;
      g.drawCircle(p, 1.6 + 1.6 * (1 - base), Paint()..color = Tk.blue.withValues(alpha: 0.35 + 0.65 * (1 - base)));
    }
    for (var k = 0; k < 3; k++) {
      final q = ((t * 1.6 + k / 3) % 1);
      g.drawCircle(c, R * (1 - q), Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = Tk.blue.withValues(alpha: (1 - q) * 0.5 * (t < 0.9 ? 1 : (1 - t) * 10)));
    }
    _glow(g, c, R * (0.25 + 0.35 * pull), Tk.blue, 0.95);
    _glow(g, c, R * 0.14, Colors.white, 0.9);
  }

  // Charge, then burst outward.
  void _red(Canvas g, Size s, Offset c, double R) {
    final charge = _seg(t, 0, 0.4), burst = _seg(t, 0.4, 1);
    _glow(g, c, R * (0.15 + 0.22 * charge) * (1 + 0.12 * math.sin(t * 60)), Tk.red, 0.95);
    if (burst > 0) {
      final e = _ease(burst);
      g.drawCircle(c, R * 1.25 * e, Paint()..style = PaintingStyle.stroke..strokeWidth = 8 * (1 - burst) + 1..color = Tk.red.withValues(alpha: 1 - burst));
      for (var i = 0; i < 28; i++) {
        final a = i / 28 * 2 * math.pi + (i % 2) * 0.1;
        final len = R * (0.35 + 0.6 * ((i * 7) % 5) / 5);
        final from = c + Offset(math.cos(a), math.sin(a)) * R * 0.2 * e;
        final to = c + Offset(math.cos(a), math.sin(a)) * (R * 0.2 + len * e);
        g.drawLine(from, to, Paint()..strokeWidth = 2.4 * (1 - burst) + 0.5..strokeCap = StrokeCap.round..color = Color.lerp(Colors.white, Tk.red, burst)!.withValues(alpha: 1 - burst * 0.8));
      }
      _glow(g, c, R * (0.6 * (1 - burst) + 0.1), Tk.red, 0.6 * (1 - burst));
    }
  }

  // Blue and red meet, merge and fire a violet beam.
  void _purple(Canvas g, Size s, Offset c, double R) {
    final meet = _ease(_seg(t, 0, 0.42));
    final fire = _seg(t, 0.5, 1);
    final dx = R * 0.85 * (1 - meet);
    if (fire == 0) {
      _glow(g, c + Offset(-dx, 0), R * 0.4, Tk.blue, 0.95);
      _glow(g, c + Offset(dx, 0), R * 0.4, Tk.red, 0.95);
    }
    if (t > 0.42 && fire == 0) _glow(g, c, R * 0.7, Tk.violet, 0.9);
    if (fire > 0) {
      final e = _ease(fire);
      final len = s.width * e;
      final h = (R * 0.42) * (1 - fire * 0.6) + 4;
      final beam = Rect.fromCenter(center: c, width: len, height: h * 2);
      g.drawRRect(
          RRect.fromRectAndRadius(beam, Radius.circular(h)),
          Paint()
            ..blendMode = BlendMode.plus
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14)
            ..color = Tk.violet.withValues(alpha: 0.85 * (1 - fire * 0.7)));
      g.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: c, width: len, height: h * 0.55), Radius.circular(h)), Paint()..color = Colors.white.withValues(alpha: 1 - fire * 0.6));
      g.drawCircle(c, R * 1.1 * e, Paint()..style = PaintingStyle.stroke..strokeWidth = 5 * (1 - fire) + 0.5..color = Tk.violet.withValues(alpha: 1 - fire));
      _glow(g, c, R * 0.5 * (1 - fire * 0.5), Colors.white, 0.8 * (1 - fire));
    }
  }

  // Many fast invisible cuts.
  void _dismantle(Canvas g, Size s, Offset c, double R) {
    final rnd = math.Random(11);
    for (var i = 0; i < 16; i++) {
      final start = i / 16 * 0.7;
      final life = _seg(t, start, start + 0.3);
      if (life <= 0 || life >= 1) continue;
      final p = c + Offset((rnd.nextDouble() - 0.5) * R * 1.6, (rnd.nextDouble() - 0.5) * R * 1.6);
      final ang = (rnd.nextDouble() - 0.5) * 1.6 + (i.isEven ? 0.6 : -0.6);
      final len = R * (0.5 + rnd.nextDouble() * 0.7);
      final dir = Offset(math.cos(ang), math.sin(ang));
      final grow = _ease(_seg(life, 0, 0.35));
      _slash(g, p - dir * len * 0.5, p - dir * len * 0.5 + dir * len * grow, 5, Tk.red, (1 - life));
    }
  }

  // One enormous cut that parts the air.
  void _cleave(Canvas g, Size s, Offset c, double R) {
    final a = Offset(s.width * 0.08, s.height * 0.12), b = Offset(s.width * 0.92, s.height * 0.88);
    final draw = _ease(_seg(t, 0, 0.22));
    final fade = _seg(t, 0.35, 1);
    final end = Offset.lerp(a, b, draw)!;
    _slash(g, a, end, 16 * (1 - fade * 0.8), Tk.red, 1 - fade);
    if (t > 0.22) {
      final d = (b - a);
      final nrm = Offset(-d.dy, d.dx) / d.distance;
      final gap = nrm * (R * 0.45 * _ease(_seg(t, 0.22, 0.7)));
      for (final sgn in [-1.0, 1.0]) {
        g.drawLine(a + gap * sgn, b + gap * sgn, Paint()..strokeWidth = 2..color = Tk.red.withValues(alpha: (1 - fade) * 0.8));
      }
      _glow(g, c, R * 0.6, Tk.red, 0.35 * (1 - fade));
    }
  }

  // A domain unfolds: crimson sphere, a shrine rising, a storm of cuts.
  void _shrine(Canvas g, Size s, Offset c, double R) {
    final e = _ease(_seg(t, 0, 0.5));
    g.drawCircle(c, R * 1.3 * e, Paint()..color = const Color(0xFF3A0008).withValues(alpha: 0.85 * (t < 0.85 ? 1 : (1 - t) * 6.6)));
    g.drawCircle(c, R * 1.3 * e, Paint()..style = PaintingStyle.stroke..strokeWidth = 2.5..color = Tk.red.withValues(alpha: 0.9));
    final rise = _ease(_seg(t, 0.15, 0.6));
    final bw = R * 0.9, base = c.dy + R * 0.45, top = base - R * 0.7 * rise;
    final col = Paint()..color = const Color(0xFF0B0003);
    final edge = Paint()..style = PaintingStyle.stroke..strokeWidth = 1.8..color = Tk.red;
    // pillars
    for (final x in [-0.32, 0.32]) {
      final r = Rect.fromLTRB(c.dx + bw * x - 5, top + R * 0.2, c.dx + bw * x + 5, base);
      g.drawRect(r, col);
      g.drawRect(r, edge);
    }
    // upturned roofs
    for (var k = 0; k < 2; k++) {
      final y = top + k * R * 0.17, w = bw * (0.62 + k * 0.28);
      final roof = Path()
        ..moveTo(c.dx - w, y + 6)
        ..quadraticBezierTo(c.dx, y - 14 - k * 4, c.dx + w, y + 6)
        ..lineTo(c.dx + w * 0.82, y + 16)
        ..quadraticBezierTo(c.dx, y + 2, c.dx - w * 0.82, y + 16)
        ..close();
      g.drawPath(roof, col);
      g.drawPath(roof, edge);
    }
    // storm of cuts
    final rnd = math.Random(5);
    for (var i = 0; i < 22; i++) {
      final st = 0.35 + i / 22 * 0.45;
      final life = _seg(t, st, st + 0.18);
      if (life <= 0 || life >= 1) continue;
      final p = c + Offset((rnd.nextDouble() - 0.5) * R * 2, (rnd.nextDouble() - 0.5) * R * 1.6);
      final ang = rnd.nextDouble() * math.pi;
      final dir = Offset(math.cos(ang), math.sin(ang));
      _slash(g, p - dir * 40, p + dir * 40, 4, Tk.red, 1 - life);
    }
  }

  @override
  bool shouldRepaint(TechniquePainter o) => o.t != t || o.tech != tech;
}

/// A loop that cycles through the techniques; tap to jump to the next one.
class TechniqueStage extends StatefulWidget {
  final double height;
  final bool showLabel;
  const TechniqueStage({super.key, this.height = 240, this.showLabel = true});
  @override
  State<TechniqueStage> createState() => _TechniqueStageState();
}

class _TechniqueStageState extends State<TechniqueStage> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) _next();
    })
    ..forward();
  int _i = 0;

  void _next() {
    if (!mounted) return;
    setState(() => _i = (_i + 1) % Technique.values.length);
    _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tech = Technique.values[_i];
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.mediumImpact();
        _next();
      },
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: Stack(alignment: Alignment.center, children: [
          RepaintBoundary(
            child: AnimatedBuilder(animation: _c, builder: (_, __) => CustomPaint(size: Size.infinite, painter: TechniquePainter(tech, _c.value))),
          ),
          if (widget.showLabel)
            Positioned(
              bottom: 0,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: Text(tech.label.toUpperCase(), key: ValueKey(tech), style: ts(12.5, w: 650, color: tech.color).copyWith(letterSpacing: 2)),
              ),
            ),
        ]),
      ),
    );
  }
}

/// Full-screen one-shot used when an APK build succeeds.
class TechniqueOverlay extends StatefulWidget {
  final ValueNotifier<int> trigger;
  const TechniqueOverlay({super.key, required this.trigger});
  @override
  State<TechniqueOverlay> createState() => _TechniqueOverlayState();
}

class _TechniqueOverlayState extends State<TechniqueOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200));
  Technique _tech = Technique.purple;

  @override
  void initState() {
    super.initState();
    widget.trigger.addListener(_go);
    _c.addStatusListener((_) => setState(() {}));
  }

  void _go() {
    _tech = const [Technique.purple, Technique.shrine, Technique.cleave][widget.trigger.value % 3];
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
        child: _c.isAnimating
            ? Stack(children: [
                Positioned.fill(child: ColoredBox(color: Colors.black.withValues(alpha: 0.35))),
                Positioned.fill(child: AnimatedBuilder(animation: _c, builder: (_, __) => CustomPaint(painter: TechniquePainter(_tech, _c.value)))),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 120,
                  child: Center(child: Text(_tech.label.toUpperCase(), style: ts(18, w: 700, color: _tech.color).copyWith(letterSpacing: 3))),
                ),
              ])
            : const SizedBox.shrink(),
      );
}
