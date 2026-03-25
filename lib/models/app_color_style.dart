import 'package:flutter/material.dart';

class AppPaletteSwatch {
  const AppPaletteSwatch({
    required this.label,
    required this.hexLabel,
    required this.color,
  });

  final String label;
  final String hexLabel;
  final Color color;
}

class AppPalette {
  static const Color paper = Color(0xFFEEEEEE);
  static const Color muted = Color(0xFF686D76);
  static const Color ink = Color(0xFF373A40);
  static const Color accent = Color(0xFFDC5F00);

  static const List<AppPaletteSwatch> swatches = [
    AppPaletteSwatch(label: 'Grey', hexLabel: '#EEEEEE', color: paper),
    AppPaletteSwatch(label: 'Retro', hexLabel: '#686D76', color: muted),
    AppPaletteSwatch(label: 'Black', hexLabel: '#373A40', color: ink),
    AppPaletteSwatch(label: 'Orange', hexLabel: '#DC5F00', color: accent),
  ];
}
