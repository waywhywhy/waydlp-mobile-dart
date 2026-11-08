import 'package:flutter/material.dart';

import '../services/downloads.dart';
import '../services/errors.dart';
import '../theme.dart';

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.child, this.padding = const EdgeInsets.all(16)});
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(padding: padding, child: child),
  );
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color = Palette.accentHover});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: Color.lerp(Palette.bg, color, 0.18),
      border: Border.all(color: Color.lerp(Palette.bg, color, 0.55)!),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Text(text, style: TextStyle(fontSize: 11.5, color: Color.lerp(color, Colors.white, 0.25))),
  );
}

Color stateColor(JobState s) => switch (s) {
  JobState.running => Palette.accentHover,
  JobState.queued || JobState.waitingRetry => Palette.text2,
  JobState.paused => Palette.warning,
  JobState.completed => Palette.success,
  JobState.failed => Palette.error,
  JobState.cancelled => Palette.muted,
};

/// Readable failure with expandable technical details.
class FailureView extends StatelessWidget {
  const FailureView(this.failure, {super.key});
  final Failure failure;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          failure.kind.title,
          style: const TextStyle(color: Palette.error, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 2),
        Text(failure.kind.hint, style: const TextStyle(color: Palette.text2, fontSize: 13)),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Technical details', style: TextStyle(fontSize: 13, color: Palette.muted)),
            children: [
              SelectableText(
                '${failure.summary}\n\n${failure.details.trim()}',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Palette.muted),
                maxLines: 30,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.hint});
  final IconData icon;
  final String title;
  final String hint;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
    child: Column(
      children: [
        Icon(icon, size: 48, color: Palette.accent2),
        const SizedBox(height: 12),
        Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(
          hint,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Palette.muted),
        ),
      ],
    ),
  );
}

/// Real progress bar: determinate when the fraction is known, otherwise indeterminate.
class JobProgress extends StatelessWidget {
  const JobProgress({super.key, required this.fraction, required this.text, this.animate = true});
  final double? fraction;
  final String text;
  final bool animate;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      LinearProgressIndicator(value: fraction ?? (animate ? null : 0)),
      const SizedBox(height: 4),
      Text(text, style: const TextStyle(fontSize: 12, color: Palette.text2)),
    ],
  );
}

class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 40});
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: _LogoPainter()),
  );
}

class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 512;
    canvas.scale(s);
    final outer = RRect.fromRectAndRadius(const Rect.fromLTWH(16, 16, 480, 480), const Radius.circular(120));
    canvas.drawRRect(
      outer,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFFB56BFF), Color(0xFF5A189A)],
        ).createShader(const Rect.fromLTWH(0, 0, 512, 512)),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(44, 44, 424, 424), const Radius.circular(96)),
      Paint()..color = Colors.black,
    );
    final wave = Path()
      ..moveTo(128, 176)
      ..lineTo(192, 296)
      ..lineTo(256, 206)
      ..lineTo(320, 296)
      ..lineTo(384, 176);
    canvas.drawPath(
      wave,
      Paint()
        ..color = Palette.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 44
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawLine(
      const Offset(150, 376),
      const Offset(362, 376),
      Paint()
        ..color = Palette.accentHover
        ..strokeWidth = 32
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
