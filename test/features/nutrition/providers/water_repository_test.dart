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

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:health_bridge/health.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:wger/core/consts.dart';
import 'package:wger/features/nutrition/providers/water_repository.dart';

import 'water_repository_test.mocks.dart';

HealthDataPoint _drink(double liters, {String uuid = 'w-1'}) => HealthDataPoint(
  uuid: uuid,
  value: NumericHealthValue(numericValue: liters),
  type: HealthDataType.WATER,
  unit: HealthDataUnit.LITER,
  dateFrom: DateTime.utc(2026, 11, 18, 9),
  dateTo: DateTime.utc(2026, 11, 18, 9),
  sourcePlatform: HealthPlatformType.appleHealth,
  sourceDeviceId: 'device',
  sourceId: 'source',
  sourceName: 'test',
);

@GenerateMocks([Health])
void main() {
  late MockHealth health;
  late SharedPreferencesAsync prefs;
  late WaterRepository repository;

  final start = DateTime.utc(2026, 11, 18);
  final end = DateTime.utc(2026, 11, 18, 15);

  setUp(() {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    prefs = SharedPreferencesAsync();
    health = MockHealth();
    when(health.configure()).thenAnswer((_) async {});
    repository = WaterRepository(health: health, prefs: prefs, isSupported: true);
  });

  group('goal', () {
    test('starts at 3 liters when nothing was saved', () async {
      expect(await repository.readGoalLiters(), DEFAULT_WATER_GOAL_LITERS);
      expect(DEFAULT_WATER_GOAL_LITERS, 3.0);
    });

    test('is stored under its own key', () async {
      await repository.saveGoalLiters(2.5);

      expect(await prefs.getDouble(PREFS_WATER_GOAL_LITERS), 2.5);
      expect(await repository.readGoalLiters(), 2.5);
    });
  });

  group('addWater', () {
    test('writes the drink in liters as a manual entry at the given time', () async {
      when(
        health.writeHealthData(
          value: anyNamed('value'),
          unit: anyNamed('unit'),
          type: anyNamed('type'),
          startTime: anyNamed('startTime'),
          recordingMethod: anyNamed('recordingMethod'),
        ),
      ).thenAnswer((_) async => 'record-id');
      final at = DateTime.utc(2026, 11, 18, 10, 30);

      await repository.addWater(0.25, at);

      final captured = verify(
        health.writeHealthData(
          value: captureAnyNamed('value'),
          unit: captureAnyNamed('unit'),
          type: captureAnyNamed('type'),
          startTime: captureAnyNamed('startTime'),
          recordingMethod: captureAnyNamed('recordingMethod'),
        ),
      ).captured;
      expect(captured[0], 0.25);
      expect(captured[1], HealthDataUnit.LITER);
      expect(captured[2], HealthDataType.WATER);
      expect((captured[3] as DateTime).isAtSameMomentAs(at), isTrue);
      expect(captured[4], RecordingMethod.manual);
    });

    test('throws when the platform stored nothing', () async {
      when(
        health.writeHealthData(
          value: anyNamed('value'),
          unit: anyNamed('unit'),
          type: anyNamed('type'),
          startTime: anyNamed('startTime'),
          recordingMethod: anyNamed('recordingMethod'),
        ),
      ).thenAnswer((_) async => null);

      expect(
        () => repository.addWater(0.5, DateTime.utc(2026, 11, 18)),
        throwsA(isA<WaterWriteException>()),
      );
    });
  });

  group('totalLiters', () {
    test('adds up every drink in the range', () async {
      when(
        health.getHealthDataFromTypes(
          types: [HealthDataType.WATER],
          startTime: start,
          endTime: end,
        ),
      ).thenAnswer((_) async => [_drink(0.25), _drink(0.5, uuid: 'w-2'), _drink(1, uuid: 'w-3')]);

      expect(await repository.totalLiters(start, end), closeTo(1.75, 1e-9));
    });

    test('is zero while access to water was never requested', () async {
      when(
        health.getHealthDataFromTypes(
          types: anyNamed('types'),
          startTime: anyNamed('startTime'),
          endTime: anyNamed('endTime'),
        ),
      ).thenThrow(PlatformException(code: '0', message: 'Authorization not determined'));

      expect(await repository.totalLiters(start, end), 0);
    });

    test('lets any other failure through', () async {
      when(
        health.getHealthDataFromTypes(
          types: anyNamed('types'),
          startTime: anyNamed('startTime'),
          endTime: anyNamed('endTime'),
        ),
      ).thenThrow(PlatformException(code: '0', message: 'database is locked'));

      expect(() => repository.totalLiters(start, end), throwsA(isA<PlatformException>()));
    });
  });

  test('ensureAuthorized asks for read and write access to water', () async {
    when(
      health.requestAuthorization(any, permissions: anyNamed('permissions')),
    ).thenAnswer((_) async => true);

    expect(await repository.ensureAuthorized(), isTrue);

    final captured = verify(
      health.requestAuthorization(captureAny, permissions: captureAnyNamed('permissions')),
    ).captured;
    expect(captured[0], [HealthDataType.WATER]);
    expect(captured[1], [HealthDataAccess.READ_WRITE]);
  });
}
