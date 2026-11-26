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

import 'package:health_bridge/health.dart';

/// A workout read from a health platform, reduced to what the workout import
/// needs. Keeps the `health` package's [HealthDataPoint] out of the importer.
class HealthWorkout {
  const HealthWorkout({
    required this.activityType,
    required this.start,
    required this.end,
    this.sourceName,
  });

  final HealthWorkoutActivityType activityType;
  final DateTime start;
  final DateTime end;

  /// App that wrote the workout ("NOOP"); `null` when not reported.
  final String? sourceName;

  /// Builds a workout from a platform data point, or `null` for anything that
  /// is not a workout.
  static HealthWorkout? fromDataPoint(HealthDataPoint point) {
    final value = point.value;
    if (value is! WorkoutHealthValue) {
      return null;
    }
    return HealthWorkout(
      activityType: value.workoutActivityType,
      start: point.dateFrom,
      end: point.dateTo,
      sourceName: point.sourceName.isEmpty ? null : point.sourceName,
    );
  }
}
