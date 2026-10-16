import 'package:flutter/material.dart';

/// Lumora brand palette: deep teal night + emerald and gold accents.
const kBg = Color(0xFF06121A);
const kBg2 = Color(0xFF0C2A31);
const kSurface = Color(0xFF10232B);
const kSurface2 = Color(0xFF173540);
const kEmerald = Color(0xFF19E3A1);
const kGold = Color(0xFFFFC857);
const kText = Color(0xFFEAF6F3);
const kMuted = Color(0xFF8DA9AE);

const kBackdrop = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [kBg2, kBg],
);

ThemeData lumoraTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: kEmerald,
    brightness: Brightness.dark,
    surface: kSurface,
  ).copyWith(primary: kEmerald, secondary: kGold);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: kBg,
    textTheme: ThemeData.dark().textTheme.apply(bodyColor: kText, displayColor: kText),
    dialogTheme: const DialogThemeData(backgroundColor: kSurface),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: kSurface2,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    ),
  );
}

/// Brand mark: rounded square with a play triangle and a signal arc.
class LumoraLogo extends StatelessWidget {
  final double size;
  const LumoraLogo({super.key, this.size = 48});

  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.square(size), painter: _LogoPainter());
}

class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final r = RRect.fromRectAndRadius(Offset.zero & s, Radius.circular(s.width * 0.28));
    canvas.drawRRect(
      r,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [kEmerald, Color(0xFF0B8F7A)],
        ).createShader(Offset.zero & s),
    );
    final tri = Path()
      ..moveTo(s.width * 0.38, s.height * 0.30)
      ..lineTo(s.width * 0.74, s.height * 0.50)
      ..lineTo(s.width * 0.38, s.height * 0.70)
      ..close();
    canvas.drawPath(tri, Paint()..color = kBg);
    final arc = Paint()
      ..color = kGold
      ..style = PaintingStyle.stroke
      ..strokeWidth = s.width * 0.07
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCenter(center: Offset(s.width * 0.30, s.height * 0.50), width: s.width * 0.34, height: s.width * 0.34),
      -0.9,
      1.8,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
