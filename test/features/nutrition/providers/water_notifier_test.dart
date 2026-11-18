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

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:wger/features/nutrition/providers/water_notifier.dart';
import 'package:wger/features/nutrition/providers/water_repository.dart';

import 'water_notifier_test.mocks.dart';

@GenerateMocks([WaterRepository])
void main() {
  late MockWaterRepository repo;

  // 00:30 local: the day boundary is the interesting part of the range
  final now = DateTime(2026, 11, 18, 0, 30);

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [
        waterRepositoryProvider.overrideWithValue(repo),
        waterProvider.overrideWith(() => WaterNotifier(clock: () => now)),
      ],
    );
    addTearDown(container.dispose);
    // Keep the auto-dispose provider alive between reads
    container.listen(waterProvider, (_, _) {});
    return container;
  }

  setUp(() {
    repo = MockWaterRepository();
    when(repo.isSupported).thenReturn(true);
    when(repo.readGoalLiters()).thenAnswer((_) async => 3);
    when(repo.totalLiters(any, any)).thenAnswer((_) async => 1.2);
  });

  group('build', () {
    test('reads today from local midnight up to now', () async {
      final container = makeContainer();

      final state = await container.read(waterProvider.future);

      final captured = verify(repo.totalLiters(captureAny, captureAny)).captured;
      expect(captured[0], DateTime(2026, 11, 18));
      expect(captured[1], now);
      expect(state.todayLiters, 1.2);
      expect(state.goalLiters, 3);
      expect(state.isSupported, isTrue);
    });

    test('does not touch the health platform where there is none', () async {
      when(repo.isSupported).thenReturn(false);
      final container = makeContainer();

      final state = await container.read(waterProvider.future);

      expect(state.isSupported, isFalse);
      expect(state.todayLiters, 0);
      verifyNever(repo.totalLiters(any, any));
    });
  });

  group('addWater', () {
    test('stores milliliters as liters at the current time, then re-reads the day', () async {
      when(repo.ensureAuthorized()).thenAnswer((_) async => true);
      when(repo.addWater(any, any)).thenAnswer((_) async {});
      final container = makeContainer();
      await container.read(waterProvider.future);
      when(repo.totalLiters(any, any)).thenAnswer((_) async => 1.45);

      final stored = await container.read(waterProvider.notifier).addWater(250);

      expect(stored, isTrue);
      verify(repo.addWater(0.25, now)).called(1);
      expect((await container.read(waterProvider.future)).todayLiters, 1.45);
    });

    test('stores nothing when access was not granted', () async {
      when(repo.ensureAuthorized()).thenAnswer((_) async => false);
      final container = makeContainer();
      await container.read(waterProvider.future);

      final stored = await container.read(waterProvider.notifier).addWater(500);

      expect(stored, isFalse);
      verifyNever(repo.addWater(any, any));
    });
  });

  test('setGoal saves the goal and shows it', () async {
    when(repo.saveGoalLiters(any)).thenAnswer((_) async {});
    final container = makeContainer();
    await container.read(waterProvider.future);
    when(repo.readGoalLiters()).thenAnswer((_) async => 2.5);

    await container.read(waterProvider.notifier).setGoal(2.5);

    verify(repo.saveGoalLiters(2.5)).called(1);
    expect((await container.read(waterProvider.future)).goalLiters, 2.5);
  });

  group('WaterState', () {
    test('progress is capped at the goal', () {
      const state = WaterState(goalLiters: 3, todayLiters: 4.5, isSupported: true);
      expect(state.progress, 1);
      expect(state.goalReached, isTrue);
    });

    test('a zero goal is never reached and shows no progress', () {
      const state = WaterState(goalLiters: 0, todayLiters: 1, isSupported: true);
      expect(state.progress, 0);
      expect(state.goalReached, isFalse);
    });
  });
}
