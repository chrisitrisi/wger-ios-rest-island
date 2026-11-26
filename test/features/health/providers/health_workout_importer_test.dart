/*
 * This file is part of wger Workout Manager <https://github.com/wger-project>.
 * Copyright (c) 2026 wger Team
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
import 'package:health_bridge/health.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:wger/core/network/auth_credentials_storage.dart';
import 'package:wger/features/health/models/health_workout.dart';
import 'package:wger/features/health/providers/health_importer.dart';
import 'package:wger/features/health/providers/health_repository.dart';
import 'package:wger/features/health/providers/health_workout_importer.dart';
import 'package:wger/features/measurements/models/measurement_category.dart';
import 'package:wger/features/measurements/models/measurement_entry.dart';
import 'package:wger/features/measurements/providers/measurement_repository.dart';

import 'health_workout_importer_test.mocks.dart';

const _saunaId = 'cccccccc-0000-4000-8000-000000000003';

HealthWorkout _workout(HealthWorkoutActivityType type, DateTime start, Duration length) =>
    HealthWorkout(activityType: type, start: start, end: start.add(length));

@GenerateMocks([HealthRepository, MeasurementRepository, AuthCredentialsStorage])
void main() {
  late MockHealthRepository health;
  late MockMeasurementRepository measurements;
  late MockAuthCredentialsStorage credentials;
  late List<MeasurementCategory> categories;

  final now = DateTime(2026, 11, 16, 12);

  setUp(() {
    health = MockHealthRepository();
    measurements = MockMeasurementRepository();
    credentials = MockAuthCredentialsStorage();
    categories = [];

    when(credentials.dbOwnerUserId()).thenAnswer((_) async => '2');
    when(health.sourceName).thenReturn('apple');
    when(measurements.getCategoriesOnce()).thenAnswer((_) async => categories);
    when(measurements.addLocalDriftCategory(any)).thenAnswer((_) async {});
    when(measurements.addLocalDrift(any)).thenAnswer((_) async {});
    when(measurements.updateLocalDrift(any)).thenAnswer((_) async {});
    when(
      measurements.getEntriesByExternalId(any),
    ).thenAnswer((_) async => <String, MeasurementEntry>{});
  });

  HealthWorkoutImporter importer() => HealthWorkoutImporter(
    health: health,
    measurements: measurements,
    credentials: credentials,
  );

  void givenWorkouts(List<HealthWorkout> workouts) {
    when(health.readWorkouts(any, any)).thenAnswer((_) async => workouts);
  }

  List<MeasurementEntry> addedEntries() =>
      verify(measurements.addLocalDrift(captureAny)).captured.cast<MeasurementEntry>();

  test('writes the running and sauna minutes of each day into new categories', () async {
    givenWorkouts([
      _workout(
        HealthWorkoutActivityType.RUNNING,
        DateTime(2026, 11, 14, 17),
        const Duration(minutes: 25),
      ),
      // The same run recorded by a second app counts once
      _workout(
        HealthWorkoutActivityType.RUNNING,
        DateTime(2026, 11, 14, 17, 5),
        const Duration(minutes: 20),
      ),
      _workout(
        HealthWorkoutActivityType.MIND_AND_BODY,
        DateTime(2026, 11, 14, 18),
        const Duration(minutes: 8),
      ),
      _workout(
        HealthWorkoutActivityType.TRADITIONAL_STRENGTH_TRAINING,
        DateTime(2026, 11, 14, 16),
        const Duration(minutes: 60),
      ),
    ]);

    expect(await importer().run(now: now), 2);

    final created = verify(
      measurements.addLocalDriftCategory(captureAny),
    ).captured.cast<MeasurementCategory>();
    expect(created.map((c) => (c.name, c.unit, c.metricType)), [
      ('Laufen', 'min', MetricType.custom),
      ('Sauna', 'min', MetricType.custom),
    ]);

    final entries = addedEntries();
    expect(entries.map((e) => (e.categoryId, e.date, e.value)), [
      (created[0].id, DateTime(2026, 11, 14), 25),
      (created[1].id, DateTime(2026, 11, 14), 8),
    ]);
    expect(
      entries.first.externalId,
      dailyAggregateExternalId(created[0].id!, DateTime(2026, 11, 14)),
    );
  });

  test('adopts an existing custom category by its name', () async {
    categories.add(MeasurementCategory(id: _saunaId, name: 'Sauna (min)', unit: 'min'));
    givenWorkouts([
      _workout(
        HealthWorkoutActivityType.MIND_AND_BODY,
        DateTime(2026, 11, 10, 19),
        const Duration(minutes: 10),
      ),
    ]);

    await importer().run(now: now);

    verifyNever(measurements.addLocalDriftCategory(any));
    expect(addedEntries().single.categoryId, _saunaId);
  });

  test('counts a workout towards the day it started', () async {
    categories.add(MeasurementCategory(id: _saunaId, name: 'Sauna', unit: 'min'));
    givenWorkouts([
      _workout(
        HealthWorkoutActivityType.MIND_AND_BODY,
        DateTime(2026, 11, 9, 23, 50),
        const Duration(minutes: 15),
      ),
    ]);

    await importer().run(now: now);

    final entry = addedEntries().single;
    expect(entry.date, DateTime(2026, 11, 9));
    expect(entry.value, 15);
  });

  test('updates a day whose minutes changed and leaves an unchanged one alone', () async {
    categories.add(MeasurementCategory(id: _saunaId, name: 'Sauna', unit: 'min'));
    final changedDay = DateTime(2026, 11, 10);
    final sameDay = DateTime(2026, 11, 12);
    MeasurementEntry stored(DateTime day, double value) => MeasurementEntry(
      id: 'entry-${day.day}',
      categoryId: _saunaId,
      date: day,
      value: value,
      notes: '',
      externalId: dailyAggregateExternalId(_saunaId, day),
    );
    when(measurements.getEntriesByExternalId(_saunaId)).thenAnswer(
      (_) async => {
        for (final entry in [stored(changedDay, 5), stored(sameDay, 12)]) entry.externalId!: entry,
      },
    );
    givenWorkouts([
      _workout(
        HealthWorkoutActivityType.MIND_AND_BODY,
        changedDay.add(const Duration(hours: 18)),
        const Duration(minutes: 9),
      ),
      _workout(
        HealthWorkoutActivityType.MIND_AND_BODY,
        sameDay.add(const Duration(hours: 18)),
        const Duration(minutes: 12),
      ),
    ]);

    expect(await importer().run(now: now), 1);

    verifyNever(measurements.addLocalDrift(any));
    final updated =
        verify(measurements.updateLocalDrift(captureAny)).captured.single as MeasurementEntry;
    expect((updated.id, updated.value), ('entry-10', 9));
  });

  test('creates nothing when there is no running or sauna workout', () async {
    givenWorkouts([
      _workout(
        HealthWorkoutActivityType.WALKING,
        DateTime(2026, 11, 14, 8),
        const Duration(minutes: 30),
      ),
    ]);

    expect(await importer().run(now: now), 0);
    verifyNever(measurements.addLocalDriftCategory(any));
    verifyNever(measurements.addLocalDrift(any));
  });

  test('reads the last 30 days', () async {
    givenWorkouts([]);

    await importer().run(now: now);

    verify(health.readWorkouts(now.subtract(const Duration(days: 30)), now));
  });
}
