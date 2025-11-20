import 'package:flutter/material.dart';

class AppLogo extends StatelessWidget {
  const AppLogo({
    super.key,
    this.assetPath = 'assets/app_logo.png',
    this.maxHeight = 32,
  });

  final String assetPath;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final fallback = Text(
      'Vib SNS',
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color:
                Theme.of(context).appBarTheme.foregroundColor ?? Colors.black87,
            letterSpacing: 0.5,
          ),
    );

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Image.asset(
        assetPath,
        height: maxHeight,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }
}
