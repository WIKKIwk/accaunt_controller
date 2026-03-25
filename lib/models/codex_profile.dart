import 'package:clash/models/codex_probe.dart';

class CodexProfile {
  const CodexProfile({
    required this.id,
    required this.label,
    required this.codexHome,
    required this.createdAt,
    this.notes,
    this.lastProbe,
  });

  final String id;
  final String label;
  final String codexHome;
  final DateTime createdAt;
  final String? notes;
  final CodexProbe? lastProbe;

  CodexProfile copyWith({
    String? id,
    String? label,
    String? codexHome,
    DateTime? createdAt,
    String? notes,
    CodexProbe? lastProbe,
    bool clearProbe = false,
  }) {
    return CodexProfile(
      id: id ?? this.id,
      label: label ?? this.label,
      codexHome: codexHome ?? this.codexHome,
      createdAt: createdAt ?? this.createdAt,
      notes: notes ?? this.notes,
      lastProbe: clearProbe ? null : lastProbe ?? this.lastProbe,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'codexHome': codexHome,
    'createdAt': createdAt.toIso8601String(),
    'notes': notes,
    'lastProbe': lastProbe?.toJson(),
  };

  factory CodexProfile.fromJson(Map<String, dynamic> json) {
    final lastProbeJson = json['lastProbe'];

    return CodexProfile(
      id: json['id'] as String,
      label: json['label'] as String,
      codexHome: json['codexHome'] as String,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      notes: json['notes'] as String?,
      lastProbe: lastProbeJson is Map<String, dynamic>
          ? CodexProbe.fromJson(lastProbeJson)
          : null,
    );
  }
}
