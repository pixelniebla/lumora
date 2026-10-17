import 'dart:math' as math;

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

/// Window background: a teal glow in the corner fading to the night colour.
const kBackdrop = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF0E3A40), Color(0xFF08202A), kBg],
  stops: [0, 0.5, 1],
);

/// Heading font: Segoe UI Variable ships with Windows 11; older systems fall back to Segoe UI.
const kDisplayFont = 'Segoe UI Variable Display';
const kFontFallback = ['Segoe UI', 'Bahnschrift'];

ThemeData lumoraTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: kEmerald,
    brightness: Brightness.dark,
    surface: kSurface,
  ).copyWith(primary: kEmerald, onPrimary: kBg, secondary: kGold, onSecondary: kBg, surfaceContainerHighest: kSurface2);
  final radius = BorderRadius.circular(14);
  final base = ThemeData.dark().textTheme.apply(bodyColor: kText, displayColor: kText);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: kBg,
    textTheme: base.copyWith(
      headlineMedium: base.headlineMedium?.copyWith(fontFamily: kDisplayFont, fontFamilyFallback: kFontFallback, fontWeight: FontWeight.w700),
      titleLarge: base.titleLarge?.copyWith(fontFamily: kDisplayFont, fontFamilyFallback: kFontFallback, fontWeight: FontWeight.w600),
    ),
    dividerTheme: DividerThemeData(color: Colors.white.withValues(alpha: 0.07), space: 1),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
          fontFamily: kDisplayFont, fontFamilyFallback: kFontFallback, fontSize: 20, fontWeight: FontWeight.w600, color: kText),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: kSurface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
    ),
    cardTheme: CardThemeData(
      color: kSurface.withValues(alpha: 0.85),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
    ),
    listTileTheme: ListTileThemeData(shape: RoundedRectangleBorder(borderRadius: radius), iconColor: kMuted),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: kEmerald,
        foregroundColor: kBg,
        shape: RoundedRectangleBorder(borderRadius: radius),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: kText,
        side: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
        shape: RoundedRectangleBorder(borderRadius: radius),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: kEmerald, shape: RoundedRectangleBorder(borderRadius: radius)),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: kEmerald,
      foregroundColor: kBg,
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      extendedTextStyle: const TextStyle(fontWeight: FontWeight.w700),
    ),
    iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(foregroundColor: kText)),
    chipTheme: ChipThemeData(
      backgroundColor: kSurface2,
      selectedColor: kEmerald.withValues(alpha: 0.22),
      side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? kBg : kMuted),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? kEmerald : kSurface2),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: kEmerald, linearTrackColor: kSurface2),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: kSurface2,
      contentTextStyle: const TextStyle(color: kText),
      actionTextColor: kEmerald,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: kSurface2,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: kSurface2, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white.withValues(alpha: 0.1))),
      textStyle: const TextStyle(color: kText, fontSize: 12),
      waitDuration: const Duration(milliseconds: 500),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: WidgetStateProperty.all(6),
      radius: const Radius.circular(8),
      thumbColor: WidgetStateProperty.all(Colors.white.withValues(alpha: 0.18)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: kSurface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: kSurface2,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: kEmerald, width: 1.4)),
    ),
  );
}

/// Brand mark. Same drawing as brand/logo.svg (full) and brand/logo_small.svg (compact, used at icon sizes).
class LumoraLogo extends StatelessWidget {
  final double size;
  const LumoraLogo({super.key, this.size = 48});

  @override
  Widget build(BuildContext context) =>
      RepaintBoundary(child: CustomPaint(size: Size.square(size), painter: LumoraLogoPainter(compact: size <= 40)));
}

/// Logo with the name and tagline next to it.
class LumoraWordmark extends StatelessWidget {
  final double logoSize;
  final bool tagline;
  const LumoraWordmark({super.key, this.logoSize = 52, this.tagline = true});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      LumoraLogo(size: logoSize),
      SizedBox(width: logoSize * 0.28),
      Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text('Lumora',
            style: TextStyle(
                fontFamily: kDisplayFont,
                fontFamilyFallback: kFontFallback,
                fontSize: logoSize * 0.56,
                fontWeight: FontWeight.w600,
                height: 1,
                color: kText)),
        if (tagline)
          Padding(
            padding: EdgeInsets.only(top: logoSize * 0.08),
            child: Text('IPTV PLAYER',
                style: TextStyle(
                    fontSize: logoSize * 0.2, fontWeight: FontWeight.w700, letterSpacing: logoSize * 0.14, color: kEmerald)),
          ),
      ]),
    ]);
  }
}

class LumoraLogoPainter extends CustomPainter {
  final bool compact;
  const LumoraLogoPainter({this.compact = false});

  static final _triangle = Path()
    ..moveTo(208, 148)
    ..quadraticBezierTo(208, 125, 228, 137)
    ..lineTo(376, 235)
    ..quadraticBezierTo(396, 248, 376, 261)
    ..lineTo(228, 367)
    ..quadraticBezierTo(208, 379, 208, 356)
    ..close();

  static final _triangleSmall = Path()
    ..moveTo(176, 112)
    ..quadraticBezierTo(176, 78, 205, 96)
    ..lineTo(416, 232)
    ..quadraticBezierTo(444, 256, 416, 280)
    ..lineTo(205, 416)
    ..quadraticBezierTo(176, 434, 176, 400)
    ..close();

  @override
  void paint(Canvas canvas, Size s) {
    canvas.save();
    canvas.scale(s.width / 512);
    const tile = Rect.fromLTWH(0, 0, 512, 512);
    final tileR = RRect.fromRectAndRadius(tile, const Radius.circular(112));
    LinearGradient lin(List<Color> c, [List<double>? stops]) =>
        LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: c, stops: stops);

    if (compact) {
      canvas.drawRRect(tileR, Paint()..shader = lin(const [Color(0xFF14907B), Color(0xFF06272D)]).createShader(tile));
      canvas.drawPath(
        _triangleSmall,
        Paint()..shader = lin(const [Color(0xFFFFE29A), Color(0xFF46F5BC), Color(0xFF16C79A)], const [0, .5, 1]).createShader(_triangleSmall.getBounds()),
      );
      canvas.drawPath(
        Path()
          ..moveTo(96, 190)
          ..arcToPoint(const Offset(96, 322), radius: const Radius.circular(90), clockwise: false),
        Paint()
          ..color = kGold
          ..style = PaintingStyle.stroke
          ..strokeWidth = 30
          ..strokeCap = StrokeCap.round,
      );
      canvas.restore();
      return;
    }

    canvas.drawRRect(
      tileR,
      Paint()..shader = lin(const [Color(0xFF0D6B5B), Color(0xFF083A3C), Color(0xFF04141B)], const [0, .55, 1]).createShader(tile),
    );
    canvas.save();
    canvas.clipRRect(tileR);
    canvas.drawRect(
      const Rect.fromLTWH(30, -10, 540, 532),
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0x9E1FF0AC), Color(0x2919E3A1), Color(0x0019E3A1)],
          stops: [0, .55, 1],
        ).createShader(Rect.fromCircle(center: const Offset(343, 256), radius: 270)),
    );
    canvas.restore();
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(2.5, 2.5, 507, 507), const Radius.circular(109.5)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = const Color(0x5935F0B8),
    );
    // content group: translate(256 256) scale(1.09) translate(-250 -256)
    canvas.translate(256, 256);
    canvas.scale(1.09);
    canvas.translate(-250, -256);
    canvas.drawPath(
      _triangle,
      Paint()..shader = lin(const [Color(0xFFFFD97A), Color(0xFF3EF0B4), Color(0xFF0FB58B)], const [0, .4, 1]).createShader(_triangle.getBounds()),
    );
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 21
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(
      Path()
        ..moveTo(160, 200)
        ..arcToPoint(const Offset(160, 312), radius: const Radius.circular(80), clockwise: false),
      arc..color = const Color(0xFFFFC857),
    );
    canvas.drawPath(
      Path()
        ..moveTo(119, 166)
        ..arcToPoint(const Offset(119, 346), radius: const Radius.circular(132), clockwise: false),
      arc..color = const Color(0xB8F3B53F),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant LumoraLogoPainter old) => old.compact != compact;
}

/// A soft glow used behind hero elements.
class GlowBlob extends StatelessWidget {
  final double size;
  final Color color;
  const GlowBlob({super.key, required this.size, this.color = kEmerald});

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0)]),
          ),
        ),
      );
}

/// Used by the dashboard tiles: angle for the decorative watermark.
double tileTilt() => -math.pi / 14;
