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

class AppPaletteData {
  const AppPaletteData({
    required this.label,
    required this.paper,
    required this.muted,
    required this.accent,
    required this.ink,
  });

  final String label;
  final Color paper;
  final Color muted;
  final Color accent;
  final Color ink;

  List<AppPaletteSwatch> get swatches => [
    AppPaletteSwatch(label: 'Paper', hexLabel: _hex(paper), color: paper),
    AppPaletteSwatch(label: 'Muted', hexLabel: _hex(muted), color: muted),
    AppPaletteSwatch(label: 'Accent', hexLabel: _hex(accent), color: accent),
    AppPaletteSwatch(label: 'Ink', hexLabel: _hex(ink), color: ink),
  ];

  String _hex(Color color) =>
      '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
}

enum AppPalettePreset { sunset, lavender, sage, sherbet, peach }

extension AppPalettePresetX on AppPalettePreset {
  AppPaletteData get palette {
    return switch (this) {
      AppPalettePreset.sunset => const AppPaletteData(
        label: 'Sunset',
        paper: Color(0xFFEEEEEE),
        muted: Color(0xFF686D76),
        accent: Color(0xFFDC5F00),
        ink: Color(0xFF373A40),
      ),
      AppPalettePreset.lavender => const AppPaletteData(
        label: 'Lavender',
        paper: Color(0xFFF4EEFF),
        muted: Color(0xFFDCD6F7),
        accent: Color(0xFFA6B1E1),
        ink: Color(0xFF424874),
      ),
      AppPalettePreset.sage => const AppPaletteData(
        label: 'Sage',
        paper: Color(0xFFE1F0DA),
        muted: Color(0xFFD4E7C5),
        accent: Color(0xFFBFD8AF),
        ink: Color(0xFF99BC85),
      ),
      AppPalettePreset.sherbet => const AppPaletteData(
        label: 'Sherbet',
        paper: Color(0xFFECF9FF),
        muted: Color(0xFFFFFBEB),
        accent: Color(0xFFFEF7CC),
        ink: Color(0xFFF8CBA6),
      ),
      AppPalettePreset.peach => const AppPaletteData(
        label: 'Peach',
        paper: Color(0xFFECF9FF),
        muted: Color(0xFFFFFBEB),
        accent: Color(0xFFFFE7CC),
        ink: Color(0xFFF8CBA6),
      ),
    };
  }

  String get storageName => name;

  static AppPalettePreset fromStorageName(String? value) {
    return AppPalettePreset.values
            .where((preset) => preset.name == value)
            .firstOrNull ??
        AppPalettePreset.lavender;
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
