import 'package:flutter/material.dart';

enum AppColorStyle { grey, black, orange, retro }

class AppColorStyleData {
  const AppColorStyleData({
    required this.label,
    required this.hexLabel,
    required this.seedColor,
  });

  final String label;
  final String hexLabel;
  final Color seedColor;
}

extension AppColorStyleX on AppColorStyle {
  AppColorStyleData get data {
    return switch (this) {
      AppColorStyle.grey => const AppColorStyleData(
        label: 'Grey',
        hexLabel: '#EEEEEE',
        seedColor: Color(0xFFEEEEEE),
      ),
      AppColorStyle.black => const AppColorStyleData(
        label: 'Black',
        hexLabel: '#373A40',
        seedColor: Color(0xFF373A40),
      ),
      AppColorStyle.orange => const AppColorStyleData(
        label: 'Orange',
        hexLabel: '#DC5F00',
        seedColor: Color(0xFFDC5F00),
      ),
      AppColorStyle.retro => const AppColorStyleData(
        label: 'Retro',
        hexLabel: '#686D76',
        seedColor: Color(0xFF686D76),
      ),
    };
  }

  String get storageName => name;

  static AppColorStyle fromStorageName(String? value) {
    return AppColorStyle.values
            .where((style) => style.name == value)
            .firstOrNull ??
        AppColorStyle.orange;
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
