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
import 'package:wger/features/nutrition/providers/water_repository.dart';

/// Today's water against the daily goal.
class WaterState {
  const WaterState({
    required this.goalLiters,
    required this.todayLiters,
    required this.isSupported,
  });

  final double goalLiters;
  final double todayLiters;

  /// False on devices without Apple Health / Health Connect, where nothing
  /// can be logged.
  final bool isSupported;

  /// How far along the day's goal is, 0 to 1.
  double get progress => goalLiters <= 0 ? 0 : (todayLiters / goalLiters).clamp(0, 1).toDouble();

  bool get goalReached => goalLiters > 0 && todayLiters >= goalLiters;
}

final waterProvider = AsyncNotifierProvider.autoDispose<WaterNotifier, WaterState>(
  WaterNotifier.new,
);

class WaterNotifier extends AsyncNotifier<WaterState> {
  WaterNotifier({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  WaterRepository get _repo => ref.read(waterRepositoryProvider);

  @override
  Future<WaterState> build() async {
    final repo = ref.watch(waterRepositoryProvider);
    final goal = await repo.readGoalLiters();
    if (!repo.isSupported) {
      return WaterState(goalLiters: goal, todayLiters: 0, isSupported: false);
    }

    // The local calendar day: a drink at 00:30 belongs to the new day
    final now = _clock();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final today = await repo.totalLiters(startOfDay, now);
    return WaterState(goalLiters: goal, todayLiters: today, isSupported: true);
  }

  /// Logs a drink of [milliliters] now. Returns false when the user did not
  /// grant access to water, in which case nothing was stored.
  Future<bool> addWater(int milliliters) async {
    if (!await _repo.ensureAuthorized()) {
      return false;
    }
    await _repo.addWater(milliliters / 1000, _clock());
    ref.invalidateSelf();
    return true;
  }

  Future<void> setGoal(double liters) async {
    await _repo.saveGoalLiters(liters);
    ref.invalidateSelf();
  }
}
