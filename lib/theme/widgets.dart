import 'package:flutter/material.dart';
import 'colors.dart';
import 'av_theme.dart';

class GlowContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final BorderRadiusGeometry radius;
  final VoidCallback? onTap;

  const GlowContainer({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.radius = const BorderRadius.all(Radius.circular(20)),
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final glow = Theme.of(context).extension<GlowTheme>()!;
    final box = Container(
      padding: padding,
      margin: margin,
      decoration: BoxDecoration(
        color: AVColors.slate,
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: glow.glowColor.withOpacity(0.25),
            blurRadius: glow.glowBlur,
            spreadRadius: glow.glowSpread,
          ),
        ],
        border: Border.all(color: AVColors.outline, width: 0.8),
      ),
      child: child,
    );
    return onTap == null ? box : InkWell(onTap: onTap, borderRadius: radius as BorderRadius?, child: box);
  }
}

class AVButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  const AVButton({super.key, required this.label, this.onPressed, this.icon});

  @override
  Widget build(BuildContext context) {
    final child = Row(mainAxisSize: MainAxisSize.min, children: [
      if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 8)],
      Text(label),
    ]);
    return ElevatedButton(onPressed: onPressed, child: child);
  }
}

class AVScaffold extends StatelessWidget {
  final String title;
  final Widget body;
  final List<Widget>? actions;
  const AVScaffold({super.key, required this.title, required this.body, this.actions});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: AVColors.slate,
        elevation: 0,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [AVColors.scaffold, AVColors.slate],
          ),
        ),
        child: body,
      ),
    );
  }
} 