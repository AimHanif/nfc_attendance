// lib/widgets/animated_web_background.dart
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';

/// AnimatedWebBackground:
/// A dynamically animated background featuring subtle waves and
/// floating educational icons, utilizing a blue-centric gradient
/// for a cohesive, corporate-aligned visual identity.
class AnimatedWebBackground extends StatefulWidget {
  const AnimatedWebBackground({Key? key}) : super(key: key);

  @override
  State<AnimatedWebBackground> createState() => _AnimatedWebBackgroundState();
}

class _AnimatedWebBackgroundState extends State<AnimatedWebBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  /// Icon set representing core educational themes.
  final List<IconData> _icons = const [
    Icons.school,
    Icons.menu_book,
    Icons.create,
    Icons.science,
    Icons.account_balance,
    Icons.brush,
    Icons.computer,
    Icons.calculate,
    Icons.emoji_people,
  ];

  /// Pre-defined normalized start positions for icons.
  final List<Offset> _startOffsets = const [
    Offset(0.15, 0.2),
    Offset(0.5, 0.1),
    Offset(0.3, 0.6),
    Offset(0.8, 0.4),
    Offset(0.2, 0.8),
    Offset(0.7, 0.75),
    Offset(0.15, 0.9),
    Offset(0.9, 0.2),
    Offset(0.4, 0.4),
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 30),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Computes a subtle, perpetual oscillation for each icon
  /// to deliver a floating effect on the X and Y axes.
  Offset _calculateIconOffset(Offset start, double phase) {
    final t = _controller.value * 2 * pi;
    const double amplitude = 0.04;
    final dx = start.dx + amplitude * sin(t + phase);
    final dy = start.dy + amplitude * cos(t + phase);
    return Offset(dx, dy);
  }

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        // Compute gradient alignment based on animation progress,
        // enabling a dynamic, forward-thinking visual gradient shift.
        final double angle = _controller.value * 2 * pi;
        final Alignment begin = Alignment(cos(angle), sin(angle));
        final Alignment end = Alignment(-cos(angle), -sin(angle));

        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: const [
                Color(0xFF1E88E5), // Material Blue 600
                Color(0xFF1565C0), // Material Blue 800
              ],
              begin: begin,
              end: end,
            ),
          ),
          child: CustomPaint(
            size: size,
            painter: WavePainter(_controller.value),
            child: Stack(
              children: List<Widget>.generate(_icons.length, (int i) {
                final Offset offset = _calculateIconOffset(
                  _startOffsets[i],
                  i * 0.6,
                );
                return Positioned(
                  left: offset.dx * size.width,
                  top: offset.dy * size.height,
                  child: Icon(
                    _icons[i],
                    size: 36,
                    color: Colors.white.withOpacity(0.7),
                  ),
                );
              }),
            ),
          ),
        );
      },
    );
  }
}

/// WavePainter renders a series of horizontal sine waves
/// that animate gently across the canvas, reinforcing
/// the corporate blue theme with subtle motion.
class WavePainter extends CustomPainter {
  final double progress;
  WavePainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = Colors.white.withOpacity(0.08)
      ..style = PaintingStyle.fill;

    const int waveCount = 3;
    const double amplitudeFactor = 0.02;

    for (int i = 0; i < waveCount; i++) {
      final Path path = Path();
      final double phase = progress * 2 * pi - (i * pi / waveCount);
      final double amplitude = size.height * amplitudeFactor;
      final double yOffset = size.height * (0.25 + i * 0.25);
      path.moveTo(0, yOffset);
      for (double x = 0; x <= size.width; x += 1.0) {
        final double y =
            yOffset + sin((x / size.width * 2 * pi) + phase) * amplitude;
        path.lineTo(x, y);
      }
      path.lineTo(size.width, size.height);
      path.lineTo(0, size.height);
      path.close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant WavePainter oldDelegate) => true;
}
