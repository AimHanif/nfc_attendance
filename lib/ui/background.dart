// lib/widgets/animated_web_background.dart
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';

class AnimatedWebBackground extends StatefulWidget {
  const AnimatedWebBackground({Key? key}) : super(key: key);

  @override
  State<AnimatedWebBackground> createState() => _AnimatedWebBackgroundState();
}

class _AnimatedWebBackgroundState extends State<AnimatedWebBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  // School-themed icons
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

  // Compute gentle float for icons
  Offset _calculateIconOffset(Offset start, double phase) {
    final t = _controller.value * 2 * pi;
    const amp = 0.04;
    final dx = start.dx + amp * sin(t + phase);
    final dy = start.dy + amp * cos(t + phase);
    return Offset(dx, dy);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final angle = _controller.value * 2 * pi;
        final begin = Alignment(cos(angle), sin(angle));
        final end = Alignment(-cos(angle), -sin(angle));

        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: const [
                Color(0xFFCC7A00), // Muted KV-orange
                Color(0xFFB71C1C), // Deep burgundy red
              ],
              begin: begin,
              end: end,
            ),
          ),
          child: CustomPaint(
            size: size,
            painter: WavePainter(_controller.value),
            child: Stack(
              children: List.generate(_icons.length, (i) {
                final off = _calculateIconOffset(_startOffsets[i], i * 0.6);
                return Positioned(
                  left: off.dx * size.width,
                  top: off.dy * size.height,
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

/// Painter that draws subtle, animated horizontal waves
class WavePainter extends CustomPainter {
  final double progress;
  WavePainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.08)
      ..style = PaintingStyle.fill;

    const waveCount = 3;
    const amplitudeFactor = 0.02;

    for (var i = 0; i < waveCount; i++) {
      final path = Path();
      final phase = progress * 2 * pi - (i * pi / waveCount);
      final amplitude = size.height * amplitudeFactor;
      final yOffset = size.height * (0.25 + i * 0.25);
      path.moveTo(0.0, yOffset);
      for (double x = 0.0; x <= size.width; x += 1.0) {
        final y = yOffset + sin((x / size.width * 2 * pi) + phase) * amplitude;
        path.lineTo(x, y);
      }
      path.lineTo(size.width, size.height);
      path.lineTo(0.0, size.height);
      path.close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant WavePainter old) => true;
}