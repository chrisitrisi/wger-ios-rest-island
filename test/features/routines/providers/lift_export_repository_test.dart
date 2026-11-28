/*
 * This file is part of wger Workout Manager <https://github.com/wger-project>.
 * Copyright (c) 2026 - 2026 wger Team
 *
 * wger Workout Manager is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:wger/database/powersync/database.dart';
import 'package:wger/features/routines/models/day.dart';
import 'package:wger/features/routines/models/routine.dart';
import 'package:wger/features/routines/models/slot.dart';
import 'package:wger/features/routines/models/slot_entry.dart';
import 'package:wger/features/routines/providers/lift_export_repository.dart';
import 'package:wger/features/routines/providers/routines_repository.dart';
import 'package:wger/features/routines/providers/workout_session_repository.dart';

import '../../../helpers/in_memory_drift.dart';
import 'lift_export_repository_test.mocks.dart';

@GenerateMocks([WorkoutSessionRepository, RoutinesRepository])
void main() {
  late DriftPowersyncDatabase db;
  late MockRoutinesRepository routines;
  late LiftExportRepository repository;

  setUp(() async {
    db = await openTestDatabase();
    routines = MockRoutinesRepository();
    repository = LiftExportRepository(db, MockWorkoutSessionRepository(), routines);
  });

  tearDown(() => db.close());

  Future<void> seedLanguage(int id, String shortName) => db
      .into(db.languageTable)
      .insert(LanguageTableCompanion.insert(id: id, shortName: shortName, fullName: shortName));

  Future<void> seedExercise(int id) async {
    await db
        .into(db.exerciseTable)
        .insert(
          ExerciseTableCompanion.insert(
            id: id,
            uuid: 'uuid-$id',
            categoryId: 1,
            created: DateTime.utc(2024),
            lastUpdate: DateTime.utc(2024),
          ),
        );
  }

  Future<void> seedTranslation(int id, int exerciseId, int languageId, String name) => db
      .into(db.exerciseTranslationTable)
      .insert(
        ExerciseTranslationTableCompanion.insert(
          id: id,
          uuid: 'tr-$id',
          exerciseId: exerciseId,
          languageId: languageId,
          name: name,
          description: '',
          created: DateTime.utc(2024),
          lastUpdate: DateTime.utc(2024),
        ),
      );

  group('exerciseNames', () {
    setUp(() async {
      await seedLanguage(1, 'de');
      await seedLanguage(2, 'en');
      await seedLanguage(3, 'fr');
      await db
          .into(db.exerciseCategoryTable)
          .insert(ExerciseCategoryTableCompanion.insert(id: 1, name: 'Chest'));
      for (final id in [10, 11, 12]) {
        await seedExercise(id);
      }
      await seedTranslation(1, 10, 1, 'Bankdrücken');
      await seedTranslation(2, 10, 2, 'Bench press');
      await seedTranslation(3, 11, 2, 'Squat');
      await seedTranslation(4, 12, 3, 'Soulevé de terre');
    });

    test('picks the app language, then English, then any translation', () async {
      final names = await repository.exerciseNames({10, 11, 12}, 'de');

      expect(names, {10: 'Bankdrücken', 11: 'Squat', 12: 'Soulevé de terre'});
    });

    test('names an exercise without a translation by its id', () async {
      final names = await repository.exerciseNames({99}, 'de');

      expect(names, {99: 'Exercise 99'});
    });
  });

  group('routineInfo', () {
    SlotEntry entry(int id, SlotEntryType type) => SlotEntry(
      id: id,
      slotId: 1,
      type: type,
      exerciseId: 10,
      repetitionUnitId: 1,
      repetitionRounding: 1,
      weightUnitId: 1,
      weightRounding: 1.25,
    );

    test('collects the warm-up entries and the day names', () async {
      final routine = Routine(
        id: 5,
        name: 'Plan',
        days: [
          Day(
            id: 7,
            routineId: 5,
            name: ' Mo Push A ',
            slots: [
              // withData drops its entries argument, so they are set afterwards
              Slot.withData(id: 1)
                ..entries = [entry(100, SlotEntryType.warmup), entry(101, SlotEntryType.normal)],
            ],
          ),
        ],
      );
      when(routines.fetchAndSetRoutineFullServer(5)).thenAnswer((_) async => routine);

      final info = await repository.routineInfo({5});

      expect(info.warmupSlotEntryIds, {100});
      expect(info.dayNames, {7: 'Mo Push A'});
    });

    test('a routine that cannot be loaded only costs its own marks', () async {
      when(routines.fetchAndSetRoutineFullServer(any)).thenThrow(Exception('offline'));

      final info = await repository.routineInfo({5});

      expect(info.warmupSlotEntryIds, isEmpty);
      expect(info.dayNames, isEmpty);
    });
  });
}
