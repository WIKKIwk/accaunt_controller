import 'package:clash/models/codex_usage_snapshot.dart';

const String officialUsageLimitName = 'Official usage page';

class OfficialUsagePageParser {
  CodexUsageSnapshot? parse(
    String pageText, {
    String? planType,
    DateTime? capturedAt,
  }) {
    final normalized = pageText.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) {
      return null;
    }

    final remainingMatch =
        RegExp(
          r'Weekly usage limit\s+(\d{1,3})%\s+remaining',
          caseSensitive: false,
        ).firstMatch(normalized) ??
        RegExp(r'(\d{1,3})%\s+remaining', caseSensitive: false).firstMatch(
          normalized,
        );
    final resetMatch = RegExp(
      r'Resets\s+([A-Za-z]{3,9}\s+\d{1,2},\s+\d{4}\s+\d{1,2}:\d{2}\s+[AP]M)',
      caseSensitive: false,
    ).firstMatch(normalized);

    if (remainingMatch == null || resetMatch == null) {
      return null;
    }

    final remainingPercent = int.tryParse(remainingMatch.group(1) ?? '');
    final resetsAt = _parseResetDate(resetMatch.group(1) ?? '');
    if (remainingPercent == null || resetsAt == null) {
      return null;
    }

    final clampedRemaining = remainingPercent.clamp(0, 100);
    return CodexUsageSnapshot(
      capturedAt: capturedAt ?? DateTime.now(),
      windows: [
        CodexUsageWindow(
          label: 'Weekly limit',
          windowMinutes: 10080,
          usedPercent: (100 - clampedRemaining).toDouble(),
          resetsAt: resetsAt,
        ),
      ],
      planType: planType,
      limitName: officialUsageLimitName,
    );
  }

  DateTime? _parseResetDate(String raw) {
    final match = RegExp(
      r'^([A-Za-z]{3,9})\s+(\d{1,2}),\s+(\d{4})\s+(\d{1,2}):(\d{2})\s+([AP]M)$',
      caseSensitive: false,
    ).firstMatch(raw.trim());
    if (match == null) {
      return null;
    }

    final month = _monthIndex(match.group(1)!);
    final day = int.tryParse(match.group(2)!);
    final year = int.tryParse(match.group(3)!);
    final hour = int.tryParse(match.group(4)!);
    final minute = int.tryParse(match.group(5)!);
    final period = match.group(6)!.toUpperCase();
    if (month == null ||
        day == null ||
        year == null ||
        hour == null ||
        minute == null) {
      return null;
    }

    var normalizedHour = hour % 12;
    if (period == 'PM') {
      normalizedHour += 12;
    }

    return DateTime(year, month, day, normalizedHour, minute);
  }

  int? _monthIndex(String label) {
    const months = {
      'jan': 1,
      'january': 1,
      'feb': 2,
      'february': 2,
      'mar': 3,
      'march': 3,
      'apr': 4,
      'april': 4,
      'may': 5,
      'jun': 6,
      'june': 6,
      'jul': 7,
      'july': 7,
      'aug': 8,
      'august': 8,
      'sep': 9,
      'sept': 9,
      'september': 9,
      'oct': 10,
      'october': 10,
      'nov': 11,
      'november': 11,
      'dec': 12,
      'december': 12,
    };
    return months[label.trim().toLowerCase()];
  }
}
