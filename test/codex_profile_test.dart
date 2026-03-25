import 'package:clash/models/codex_probe.dart';
import 'package:clash/models/codex_profile.dart';
import 'package:clash/models/codex_usage_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('CodexProfile survives a json round trip', () {
    final profile = CodexProfile(
      id: 'profile-1',
      label: 'Work',
      codexHome: '/tmp/work-profile',
      createdAt: DateTime.parse('2026-03-25T10:30:00Z'),
      notes: 'Primary account',
      lastProbe: CodexProbe(
        loginSummary: 'Logged in using ChatGPT',
        checkedAt: DateTime.parse('2026-03-25T10:35:00Z'),
        isLoggedIn: true,
        usageSnapshot: CodexUsageSnapshot(
          capturedAt: DateTime.parse('2026-03-25T10:36:00Z'),
          planType: 'free',
          windows: [
            CodexUsageWindow(
              label: 'Weekly limit',
              windowMinutes: 10080,
              usedPercent: 16,
              resetsAt: DateTime.parse('2026-03-29T16:02:00Z'),
            ),
          ],
        ),
      ),
    );

    final restored = CodexProfile.fromJson(profile.toJson());

    expect(restored.id, profile.id);
    expect(restored.label, profile.label);
    expect(restored.codexHome, profile.codexHome);
    expect(restored.notes, profile.notes);
    expect(restored.lastProbe?.loginSummary, 'Logged in using ChatGPT');
    expect(restored.lastProbe?.isLoggedIn, isTrue);
    expect(restored.lastProbe?.usageSnapshot?.planType, 'free');
    expect(
      restored.lastProbe?.usageSnapshot?.windows.first.remainingPercent,
      84,
    );
  });
}
