import 'dart:convert';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../models.dart';
import '../theme.dart';
import '../l10n/l10n.dart';

class K9Card extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Gradient? gradient;
  final Color? color;
  const K9Card(
      {super.key,
      required this.child,
      this.padding = const EdgeInsets.all(16),
      this.onTap,
      this.gradient,
      this.color});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: gradient == null ? (color ?? K9.card) : null,
          gradient: gradient,
          borderRadius: BorderRadius.circular(K9.radius),
          border: Border.all(color: K9.border),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(K9.radius),
          onTap: onTap,
          splashColor: K9.orange.withValues(alpha: 0.08),
          highlightColor: K9.orange.withValues(alpha: 0.04),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String title;
  final IconData? icon;
  final String? action;
  final VoidCallback? onAction;
  const SectionTitle(this.title, {super.key, this.icon, this.action, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        if (icon != null) ...[
          Icon(icon, color: K9.orange, size: 20),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        ),
        if (action != null)
          GestureDetector(
            onTap: onAction,
            child: Text(action!,
                style: const TextStyle(color: K9.orange, fontWeight: FontWeight.w600)),
          ),
      ]),
    );
  }
}

class IconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  const IconBadge(this.icon, this.color, {super.key, this.size = 44});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(icon, color: color, size: size * 0.52),
    );
  }
}

/// Animowany pierścień postępu (styl Whoop / Apple Health).
class RingGauge extends StatelessWidget {
  final double value; // 0..1
  final double size;
  final double stroke;
  final Color color;
  final Gradient? gradient;
  final Widget? center;
  const RingGauge(
      {super.key,
      required this.value,
      this.size = 80,
      this.stroke = 9,
      this.color = K9.orange,
      this.gradient,
      this.center});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.clamp(0, 1)),
      duration: const Duration(milliseconds: 1100),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _RingPainter(v, stroke, color, gradient),
          child: Center(child: center),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double v;
  final double stroke;
  final Color color;
  final Gradient? gradient;
  _RingPainter(this.v, this.stroke, this.color, this.gradient);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final r = rect.deflate(stroke / 2);
    final bg = Paint()
      ..color = Colors.white.withValues(alpha: 0.07)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawArc(r, 0, math.pi * 2, false, bg);
    if (v <= 0) return;
    final fg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    if (gradient != null) {
      fg.shader = SweepGradient(
        startAngle: 0,
        endAngle: math.pi * 2,
        colors: (gradient as LinearGradient).colors,
        transform: const GradientRotation(-math.pi / 2),
      ).createShader(rect);
    } else {
      fg.color = color;
    }
    canvas.drawArc(r, -math.pi / 2, math.pi * 2 * v, false, fg);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.v != v || old.color != color;
}

/// Wejście z przesunięciem i przenikaniem, z opóźnieniem dla efektu kaskady.
class FadeSlideIn extends StatefulWidget {
  final Widget child;
  final int index;
  const FadeSlideIn({super.key, required this.child, this.index = 0});

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
  late final Animation<double> _a = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: 60 * widget.index), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _a,
      builder: (context, child) => Opacity(
        opacity: _a.value,
        child: Transform.translate(offset: Offset(0, 18 * (1 - _a.value)), child: child),
      ),
      child: widget.child,
    );
  }
}

class StatValue extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;
  final IconData? icon;
  final Color color;
  const StatValue(
      {super.key,
      required this.label,
      required this.value,
      this.unit,
      this.icon,
      this.color = K9.orange});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (icon != null) ...[Icon(icon, color: color, size: 22), const SizedBox(height: 8)],
      Text.rich(TextSpan(children: [
        TextSpan(
            text: value,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, height: 1.1)),
        if (unit != null)
          TextSpan(
              text: ' $unit',
              style: const TextStyle(fontSize: 13, color: K9.muted, fontWeight: FontWeight.w600)),
      ])),
      const SizedBox(height: 2),
      Text(label, style: const TextStyle(color: K9.muted, fontSize: 12.5)),
    ]);
  }
}

class Pill extends StatelessWidget {
  final IconData? icon;
  final String text;
  const Pill({super.key, this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 16, color: K9.text), const SizedBox(width: 6)],
        Text(text, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
      ]),
    );
  }
}

/// Przełącznik segmentowy w kształcie pigułki (np. Tydzień / Miesiąc / Rok).
class Segmented extends StatelessWidget {
  final List<String> items;
  final int index;
  final ValueChanged<int> onChanged;
  const Segmented({super.key, required this.items, required this.index, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: K9.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: K9.border)),
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth / items.length;
        return Stack(children: [
          AnimatedPositioned(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            left: w * index,
            top: 0,
            bottom: 0,
            width: w,
            child: Container(
              decoration: BoxDecoration(gradient: K9.orangeGradient, borderRadius: BorderRadius.circular(12)),
            ),
          ),
          Row(children: [
            for (var i = 0; i < items.length; i++)
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(i),
                  child: SizedBox(
                    height: 38,
                    child: Center(
                      child: AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 200),
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: i == index ? Colors.black : K9.muted),
                        child: Text(items[i]),
                      ),
                    ),
                  ),
                ),
              ),
          ]),
        ]);
      }),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;
  final String? action;
  final VoidCallback? onAction;
  const EmptyState(
      {super.key, required this.icon, required this.title, required this.text, this.action, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
      child: Column(children: [
        IconBadge(icon, K9.orange, size: 64),
        const SizedBox(height: 16),
        Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700), textAlign: TextAlign.center),
        const SizedBox(height: 6),
        Text(text, style: const TextStyle(color: K9.muted), textAlign: TextAlign.center),
        if (action != null) ...[
          const SizedBox(height: 18),
          SizedBox(width: 220, child: FilledButton(onPressed: onAction, child: Text(action!))),
        ],
      ]),
    );
  }
}

/// Zdjęcie psa (zapisane jako base64) lub elegancki placeholder.
class DogPhoto extends StatelessWidget {
  final Dog? dog;
  final BoxFit fit;
  const DogPhoto({super.key, required this.dog, this.fit = BoxFit.cover});

  @override
  Widget build(BuildContext context) {
    final b64 = dog?.photoBase64;
    if (b64 != null && b64.isNotEmpty) {
      return Image.memory(base64Decode(b64), fit: fit, gaplessPlayback: true);
    }
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0.4, -0.3),
          radius: 1.1,
          colors: [Color(0xFF5A3210), Color(0xFF221509), K9.bg],
        ),
      ),
      child: Align(
        alignment: const Alignment(0.55, -0.2),
        child: Icon(Icons.pets_rounded, size: 150, color: K9.orange.withValues(alpha: 0.22)),
      ),
    );
  }
}

class ListRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  const ListRow(
      {super.key,
      required this.icon,
      required this.color,
      required this.title,
      this.subtitle,
      this.trailing,
      this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          IconBadge(icon, color, size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: K9.muted, fontSize: 13)),
                ),
            ]),
          ),
          trailing ?? const Icon(Icons.chevron_right_rounded, color: K9.faint),
        ]),
      ),
    );
  }
}

/// Pole wyboru daty/godziny w formularzach.
class DateField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final bool withTime;
  final ValueChanged<DateTime?> onChanged;
  final bool clearable;
  const DateField(
      {super.key,
      required this.label,
      required this.value,
      required this.onChanged,
      this.withTime = false,
      this.clearable = false});

  @override
  Widget build(BuildContext context) {
    final text = value == null
        ? tr('Nie ustawiono')
        : withTime
            ? '${fmtDate(value!)}, ${fmtTime(value!)}'
            : fmtDate(value!);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () async {
        final now = DateTime.now();
        final d = await showDatePicker(
          context: context,
          initialDate: value ?? now,
          firstDate: DateTime(now.year - 30),
          lastDate: DateTime(now.year + 10),
        );
        if (d == null || !context.mounted) return;
        var result = d;
        if (withTime) {
          final t = await showTimePicker(
              context: context,
              initialTime: TimeOfDay.fromDateTime(value ?? DateTime(now.year, 1, 1, 17)));
          result = DateTime(d.year, d.month, d.day, t?.hour ?? 17, t?.minute ?? 0);
        }
        onChanged(result);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: clearable && value != null
              ? IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => onChanged(null))
              : const Icon(Icons.calendar_today_rounded, size: 18, color: K9.muted),
        ),
        child: Text(text, style: TextStyle(color: value == null ? K9.muted : K9.text)),
      ),
    );
  }
}

/// Wspólny układ dolnego arkusza z formularzem.
Future<T?> showFormSheet<T>(BuildContext context, Widget child) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.viewPaddingOf(context).bottom),
        child: child,
      ),
    ),
  );
}

Future<bool> confirmDelete(BuildContext context, String what) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(tr('Usunąć?')),
      content: Text(tr('Czy na pewno usunąć: {0}?', [what])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Anuluj'))),
        TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(tr('Usuń'), style: TextStyle(color: K9.red))),
      ],
    ),
  );
  return r ?? false;
}

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

class SheetTitle extends StatelessWidget {
  final String text;
  final VoidCallback? onDelete;
  const SheetTitle(this.text, {super.key, this.onDelete});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Row(children: [
          Expanded(
              child: Text(text, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800))),
          if (onDelete != null)
            IconButton(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline_rounded, color: K9.red)),
        ]),
      );
}

const gap12 = SizedBox(height: 12);
const gap16 = SizedBox(height: 16);
