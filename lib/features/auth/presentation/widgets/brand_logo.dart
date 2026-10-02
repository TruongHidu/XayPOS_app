import 'package:flutter/material.dart';

class AppLogo extends StatelessWidget {
  const AppLogo({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: const CustomPaint(painter: _XayPosMarkPainter()),
    );
  }
}

class XayPosWordmark extends StatelessWidget {
  const XayPosWordmark({super.key, this.height = 34});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox.square(
          dimension: height,
          child: const CustomPaint(painter: _XayPosMarkPainter()),
        ),
        SizedBox(width: height * 0.24),
        Text(
          'Xây POS',
          style: TextStyle(
            color: const Color(0xFF0863BE),
            fontSize: height * 0.62,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.5,
          ),
        ),
      ],
    );
  }
}

class _XayPosMarkPainter extends CustomPainter {
  const _XayPosMarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 64;
    final bounds = Offset.zero & size;
    final gradient = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF0877D9), Color(0xFF0754AB)],
    ).createShader(bounds);
    final stroke = Paint()
      ..shader = gradient
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5 * scale
      ..strokeJoin = StrokeJoin.miter
      ..strokeCap = StrokeCap.square;

    final smallBuilding = Path()
      ..moveTo(5 * scale, 55 * scale)
      ..lineTo(5 * scale, 29 * scale)
      ..lineTo(22 * scale, 18 * scale)
      ..lineTo(22 * scale, 55 * scale)
      ..close();
    canvas.drawPath(smallBuilding, stroke);

    final tallBuilding = Path()
      ..moveTo(23 * scale, 55 * scale)
      ..lineTo(23 * scale, 8 * scale)
      ..lineTo(42 * scale, 20 * scale)
      ..lineTo(42 * scale, 31 * scale);
    canvas.drawPath(tallBuilding, stroke);

    final terminal = RRect.fromRectAndRadius(
      Rect.fromLTWH(28 * scale, 31 * scale, 31 * scale, 25 * scale),
      Radius.circular(3 * scale),
    );
    canvas.drawRRect(terminal, Paint()..shader = gradient);

    final screen = RRect.fromRectAndRadius(
      Rect.fromLTWH(33 * scale, 35 * scale, 20 * scale, 8 * scale),
      Radius.circular(1.5 * scale),
    );
    canvas.drawRRect(screen, Paint()..color = Colors.white);

    final keyPaint = Paint()..color = Colors.white;
    for (var row = 0; row < 2; row++) {
      for (var column = 0; column < 3; column++) {
        canvas.drawRect(
          Rect.fromLTWH(
            (33 + column * 7) * scale,
            (46 + row * 5) * scale,
            4 * scale,
            3 * scale,
          ),
          keyPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
