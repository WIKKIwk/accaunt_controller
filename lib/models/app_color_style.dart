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
  static const Color paper = Color(0xFFF4EEFF);
  static const Color mist = Color(0xFFDCD6F7);
  static const Color sky = Color(0xFFA6B1E1);
  static const Color ink = Color(0xFF424874);

  static const List<AppPaletteSwatch> swatches = [
    AppPaletteSwatch(label: 'Paper', hexLabel: '#F4EEFF', color: paper),
    AppPaletteSwatch(label: 'Mist', hexLabel: '#DCD6F7', color: mist),
    AppPaletteSwatch(label: 'Sky', hexLabel: '#A6B1E1', color: sky),
    AppPaletteSwatch(label: 'Ink', hexLabel: '#424874', color: ink),
  ];
}
