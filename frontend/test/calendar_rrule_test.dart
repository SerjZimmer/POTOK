import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/calendar/services/rrule_service.dart';

void main() {
  test('RRuleService parse/build roundtrip (stub)', () {
    final svc = RRuleService();
    final parsed = svc.parse('FREQ=DAILY;INTERVAL=1');
    final built = svc.build(parsed);
    expect(built, isNotEmpty);
  });
}

