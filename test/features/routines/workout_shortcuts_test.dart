import 'package:flutter_test/flutter_test.dart';
import 'package:wger/features/routines/workout_shortcuts.dart';

import '../../../test_data/routines.dart';

void main() {
  test('start chooses today or the explicit training day and skips rest days', () {
    final day = getTestRoutine().dayDataGym.first;
    final yesterday = day.date.subtract(const Duration(days: 1));

    expect(shortcutDay([day], '', day.date), same(day));
    expect(shortcutDay([day], '', yesterday), isNull);
    expect(shortcutDay([day], '  ${day.day!.name.toUpperCase()} ', yesterday), same(day));
    expect(shortcutDay([day], 'missing', day.date), isNull);

    day.day!.isRest = true;
    expect(shortcutDay([day], '', day.date), isNull);
    expect(shortcutDay([day], day.day!.name, day.date), isNull);
  });
}
