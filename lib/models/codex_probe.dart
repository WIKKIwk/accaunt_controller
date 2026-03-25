import 'package:clash/models/codex_usage_snapshot.dart';

class CodexProbe {
  const CodexProbe({
    required this.loginSummary,
    required this.checkedAt,
    required this.isLoggedIn,
    this.usageSnapshot,
  });

  final String loginSummary;
  final DateTime checkedAt;
  final bool isLoggedIn;
  final CodexUsageSnapshot? usageSnapshot;

  Map<String, dynamic> toJson() => {
    'loginSummary': loginSummary,
    'checkedAt': checkedAt.toIso8601String(),
    'isLoggedIn': isLoggedIn,
    'usageSnapshot': usageSnapshot?.toJson(),
  };

  factory CodexProbe.fromJson(Map<String, dynamic> json) {
    final usageSnapshotJson = json['usageSnapshot'];
    return CodexProbe(
      loginSummary: (json['loginSummary'] as String?) ?? 'Unknown',
      checkedAt:
          DateTime.tryParse(json['checkedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      isLoggedIn: json['isLoggedIn'] as bool? ?? false,
      usageSnapshot: usageSnapshotJson is Map<String, dynamic>
          ? CodexUsageSnapshot.fromJson(usageSnapshotJson)
          : null,
    );
  }
}
