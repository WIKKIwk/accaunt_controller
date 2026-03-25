class CodexUsageSnapshot {
  const CodexUsageSnapshot({
    required this.capturedAt,
    required this.windows,
    this.planType,
    this.limitName,
  });

  final DateTime capturedAt;
  final List<CodexUsageWindow> windows;
  final String? planType;
  final String? limitName;

  Map<String, dynamic> toJson() => {
    'capturedAt': capturedAt.toIso8601String(),
    'windows': windows.map((window) => window.toJson()).toList(),
    'planType': planType,
    'limitName': limitName,
  };

  factory CodexUsageSnapshot.fromJson(Map<String, dynamic> json) {
    return CodexUsageSnapshot(
      capturedAt:
          DateTime.tryParse(json['capturedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      windows: (json['windows'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(CodexUsageWindow.fromJson)
          .toList(),
      planType: json['planType'] as String?,
      limitName: json['limitName'] as String?,
    );
  }
}

class CodexUsageWindow {
  const CodexUsageWindow({
    required this.label,
    required this.windowMinutes,
    required this.usedPercent,
    required this.resetsAt,
  });

  final String label;
  final int windowMinutes;
  final double usedPercent;
  final DateTime resetsAt;

  int get remainingPercent {
    final value = 100 - usedPercent.round();
    if (value < 0) {
      return 0;
    }
    if (value > 100) {
      return 100;
    }
    return value;
  }

  Map<String, dynamic> toJson() => {
    'label': label,
    'windowMinutes': windowMinutes,
    'usedPercent': usedPercent,
    'resetsAt': resetsAt.toIso8601String(),
  };

  factory CodexUsageWindow.fromJson(Map<String, dynamic> json) {
    return CodexUsageWindow(
      label: (json['label'] as String?) ?? 'Limit',
      windowMinutes: (json['windowMinutes'] as num?)?.toInt() ?? 0,
      usedPercent: (json['usedPercent'] as num?)?.toDouble() ?? 0,
      resetsAt:
          DateTime.tryParse(json['resetsAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
