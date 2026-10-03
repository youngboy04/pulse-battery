import 'package:flutter/material.dart';

class HardwarePainter extends CustomPainter {
  const HardwarePainter(this.mouse, this.accent);
  final bool mouse;
  final Color accent;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / (mouse ? 130 : 255), size.height / 122);
    final glow = Paint()
      ..color = accent.withValues(alpha: .11)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(mouse ? 65 : 128, 96),
        width: mouse ? 95 : 208,
        height: 18,
      ),
      glow,
    );
    final body = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xff555b61), Color(0xff282c31), Color(0xff202429)],
      ).createShader(const Rect.fromLTWH(0, 0, 255, 122));
    final line = Paint()
      ..color = const Color(0xff626870)
      ..style = PaintingStyle.stroke
      ..strokeWidth = .8;
    if (mouse) {
      canvas.translate(19, 1);
      canvas.rotate(-.15);
      final path = Path()
        ..moveTo(49, 8)
        ..cubicTo(17, 6, 14, 35, 11, 67)
        ..cubicTo(7, 104, 19, 116, 49, 116)
        ..cubicTo(80, 116, 91, 102, 86, 67)
        ..cubicTo(82, 33, 79, 9, 49, 8)
        ..close();
      canvas.drawPath(path, body);
      canvas.drawPath(path, line);
      canvas.drawLine(const Offset(49, 10), const Offset(49, 55), line);
      canvas.drawPath(
        Path()
          ..moveTo(15, 53)
          ..quadraticBezierTo(49, 65, 83, 53),
        line,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(44, 23, 10, 23),
          const Radius.circular(5),
        ),
        Paint()..color = const Color(0xff111416),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(47, 27, 4, 14),
          const Radius.circular(2),
        ),
        Paint()..color = accent.withValues(alpha: .8),
      );
      canvas.drawLine(
        const Offset(13, 61),
        const Offset(11, 78),
        Paint()
          ..color = accent.withValues(alpha: .5)
          ..strokeWidth = 2,
      );
      final mark = Path()
        ..moveTo(43, 94)
        ..lineTo(49, 88)
        ..lineTo(55, 94)
        ..moveTo(46, 98)
        ..lineTo(52, 98);
      canvas.drawPath(
        mark,
        Paint()
          ..color = const Color(0xff7b8389)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    } else {
      canvas.translate(4, 17);
      canvas.rotate(-.055);
      final r = RRect.fromRectAndRadius(
        const Rect.fromLTWH(0, 0, 243, 95),
        const Radius.circular(9),
      );
      canvas.drawRRect(
        r.shift(const Offset(0, 5)),
        Paint()..color = const Color(0xff15181b),
      );
      canvas.drawRRect(r, body);
      canvas.drawRRect(r, line);
      for (int row = 0; row < 5; row++) {
        for (int col = 0; col < 14; col++) {
          if (row == 4 && col >= 3 && col <= 8) continue;
          final x = 9.0 + col * 16;
          final y = 8.0 + row * 16;
          final key = RRect.fromRectAndRadius(
            Rect.fromLTWH(x, y, 13, 12),
            const Radius.circular(2),
          );
          final special =
              (row == 0 && col == 0) ||
              (col == 13 && row == 2) ||
              (row == 4 && col > 10);
          canvas.drawRRect(
            key.shift(const Offset(0, 2)),
            Paint()..color = const Color(0xff111416),
          );
          canvas.drawRRect(
            key,
            Paint()
              ..color = special
                  ? accent.withValues(alpha: .8)
                  : Color.lerp(
                      const Color(0xff606870),
                      const Color(0xff343b43),
                      col / 18,
                    )!,
          );
          if (row < 4) {
            canvas.drawLine(
              Offset(x + 4, y + 4),
              Offset(x + 7, y + 4),
              Paint()
                ..color = Colors.white.withValues(alpha: .27)
                ..strokeWidth = .7,
            );
          }
        }
      }
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(57, 72, 93, 12),
          const Radius.circular(2),
        ),
        Paint()..color = const Color(0xff69717b),
      );
      canvas.drawCircle(const Offset(229, 13), 7, Paint()..color = accent);
      canvas.drawCircle(
        const Offset(229, 13),
        4,
        Paint()..color = const Color(0xff74747f),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant HardwarePainter oldDelegate) =>
      oldDelegate.mouse != mouse || oldDelegate.accent != accent;
}
