import 'package:clash/services/official_usage_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('OfficialUsagePageParser extracts remaining percent and reset time', () {
    const bodyText =
        'Codex Analytics Usage Weekly usage limit 3% remaining Resets May 3, 2026 1:13 PM';

    final parser = OfficialUsagePageParser();
    final snapshot = parser.parse(bodyText);

    expect(snapshot, isNotNull);
    expect(snapshot?.limitName, officialUsageLimitName);
    expect(snapshot?.windows.single.remainingPercent, 3);
    expect(snapshot?.windows.single.usedPercent, 97);
    expect(
      snapshot?.windows.single.resetsAt,
      DateTime(2026, 5, 3, 13, 13),
    );
  });
}
