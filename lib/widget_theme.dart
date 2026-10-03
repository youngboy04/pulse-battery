import 'dart:math' as math;
import 'package:flutter/material.dart';

@immutable
class WidgetPalette {
  const WidgetPalette(
    this.id,
    this.name,
    this.background,
    this.end,
    this.mouse,
    this.keyboard,
    this.text,
    this.muted, {
    this.forest = false,
  });
  final int id;
  final String name;
  final Color background, end, mouse, keyboard, text, muted;
  final bool forest;
  static const all = [
    WidgetPalette(
      0,
      'Лесной фонарь',
      Color(0xff08191f),
      Color(0xff0b2227),
      Color(0xffe6ba72),
      Color(0xffb4a1cd),
      Color(0xffe3e8df),
      Color(0xff8babae),
      forest: true,
    ),
    WidgetPalette(
      1,
      'Лунный',
      Color(0xff101a2d),
      Color(0xff1c2943),
      Color(0xffa4d7ed),
      Color(0xffb8bef0),
      Color(0xffe9f0fa),
      Color(0xff9aaecb),
    ),
    WidgetPalette(
      2,
      'Тёплый янтарь',
      Color(0xff251b17),
      Color(0xff33241c),
      Color(0xfff2bb79),
      Color(0xffdba995),
      Color(0xfff5e9dc),
      Color(0xffb7a08d),
    ),
    WidgetPalette(
      3,
      'Графит',
      Color(0xff202428),
      Color(0xff171a1f),
      Color(0xffb7f59b),
      Color(0xffb7b0ff),
      Color(0xffe9ebee),
      Color(0xff969ca6),
    ),
  ];
  static WidgetPalette fromId(int id) =>
      all.firstWhere((p) => p.id == id, orElse: () => all.first);
}

class WidgetThemePicker extends StatelessWidget {
  const WidgetThemePicker({
    super.key,
    required this.selected,
    required this.onChanged,
    this.compact = false,
  });
  final int selected;
  final ValueChanged<int> onChanged;
  final bool compact;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 660 ? 4 : 2;
      final width = (constraints.maxWidth - 10 * (columns - 1)) / columns;
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: WidgetPalette.all
            .map(
              (p) => Semantics(
                selected: selected == p.id,
                button: true,
                label: p.name,
                child: SizedBox(
                  width: width,
                  height: compact ? 74 : 94,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      key: ValueKey('theme-${p.id}'),
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => onChanged(p.id),
                      child: Ink(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [p.background, p.end],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: selected == p.id
                                ? p.mouse
                                : p.muted.withValues(alpha: .22),
                            width: selected == p.id ? 1.4 : 1,
                          ),
                        ),
                        padding: EdgeInsets.all(compact ? 11 : 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 18,
                                  height: 5,
                                  decoration: BoxDecoration(
                                    color: p.mouse,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Container(
                                  width: 18,
                                  height: 5,
                                  decoration: BoxDecoration(
                                    color: p.keyboard,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                                const Spacer(),
                                Icon(
                                  selected == p.id
                                      ? Icons.check_circle_rounded
                                      : p.forest
                                      ? Icons.forest_outlined
                                      : Icons.circle_outlined,
                                  color: p.mouse,
                                  size: 14,
                                ),
                              ],
                            ),
                            const Spacer(),
                            Text(
                              p.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: p.text,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (!compact && p.forest)
                              Text(
                                'Под ваши обои',
                                style: TextStyle(color: p.muted, fontSize: 10),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            )
            .toList(),
      );
    },
  );
}

/// Static vector scenery: no images, animation loop, or extra background work.
class ForestBackdrop extends CustomPainter {
  const ForestBackdrop(this.palette);
  final WidgetPalette palette;
  @override
  void paint(Canvas canvas, Size size) {
    if (!palette.forest) return;
    final glow = Rect.fromCircle(
      center: Offset(size.width * .97, size.height * .80),
      radius: size.width * .46,
    );
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          colors: [
            palette.mouse.withValues(alpha: .09),
            palette.mouse.withValues(alpha: 0),
          ],
        ).createShader(glow),
    );
    // Ferns and fir silhouettes sit below the readings, near the footer.
    for (int i = 0; i < 10; i++) {
      final x = size.width * i / 8 - 12;
      final h = 32.0 + math.sin(i * 2.4).abs() * 44;
      final base = size.height + 8;
      final tree = Path()..moveTo(x, base - h);
      for (int level = 0; level < 4; level++) {
        final y = base - h + h * (level + 1) / 5;
        tree.lineTo(x + 5 + level * 4, y + 9);
        tree.lineTo(x + 3 + level * 2, y + 8);
      }
      tree.lineTo(x + 19, base);
      tree.lineTo(x - 19, base);
      for (int level = 3; level >= 0; level--) {
        final y = base - h + h * (level + 1) / 5;
        tree.lineTo(x - 3 - level * 2, y + 8);
        tree.lineTo(x - 5 - level * 4, y + 9);
      }
      tree.close();
      canvas.drawPath(
        tree,
        Paint()..color = const Color(0xff030f15).withValues(alpha: .45),
      );
    }
    for (int i = 0; i < 8; i++) {
      final point = Offset(
        size.width * (.06 + i * .13),
        size.height * (.77 + math.sin(i * 3.1) * .1),
      );
      canvas.drawCircle(
        point,
        .8,
        Paint()..color = palette.mouse.withValues(alpha: .18),
      );
    }
  }

  @override
  bool shouldRepaint(ForestBackdrop oldDelegate) =>
      oldDelegate.palette != palette;
}
