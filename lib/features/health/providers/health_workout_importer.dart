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

import 'package:collection/collection.dart';
import 'package:health_bridge/health.dart';
import 'package:logging/logging.dart';
import 'package:powersync/powersync.dart' as ps;
import 'package:wger/core/network/auth_credentials_storage.dart';
import 'package:wger/features/health/models/daily_windows.dart';
import 'package:wger/features/health/models/health_reading.dart';
import 'package:wger/features/health/models/health_workout.dart';
import 'package:wger/features/health/providers/health_importer.dart';
import 'package:wger/features/health/providers/health_repository.dart';
import 'package:wger/features/measurements/models/measurement_category.dart';
import 'package:wger/features/measurements/models/measurement_entry.dart';
import 'package:wger/features/measurements/providers/measurement_repository.dart';

/// A kind of workout whose minutes per day are kept in a measurement category.
///
/// The server only accepts its own metric types, so these go into the user's
/// own (custom) categories, found by name: an existing "Sauna (min)" is
/// adopted as it is, and a missing one is created under [name].
enum WorkoutMinutesKind {
  running(
    name: 'Laufen',
    namePrefixes: ['laufen', 'jogging', 'running'],
    activityTypes: {
      HealthWorkoutActivityType.RUNNING,
      HealthWorkoutActivityType.RUNNING_TREADMILL,
    },
  ),

  /// Health has no sauna type. NOOP writes a sauna session as Mind and Body,
  /// the one type no other workout of this setup uses.
  sauna(
    name: 'Sauna',
    namePrefixes: ['sauna'],
    activityTypes: {HealthWorkoutActivityType.MIND_AND_BODY},
  );

  const WorkoutMinutesKind({
    required this.name,
    required this.namePrefixes,
    required this.activityTypes,
  });

  /// Name of the category created when the user has none yet.
  final String name;

  /// A custom category whose name starts with one of these (ignoring case)
  /// receives the minutes.
  final List<String> namePrefixes;

  final Set<HealthWorkoutActivityType> activityTypes;

  bool matches(MeasurementCategory category) {
    final name = category.name.trim().toLowerCase();
    return category.metricType == MetricType.custom &&
        category.parentId == null &&
        namePrefixes.any(name.startsWith);
  }
}

/// Imports the minutes of running and sauna workouts per day from Apple
/// Health / Health Connect into measurement categories.
///
/// One entry per day and kind, keyed by [dailyAggregateExternalId] like the
/// other day aggregates, so a re-read updates the day instead of adding to it.
/// Workouts that overlap (two apps recording the same run) count once.
class HealthWorkoutImporter {
  HealthWorkoutImporter({
    required HealthRepository health,
    required MeasurementRepository measurements,
    required AuthCredentialsStorage credentials,
  }) : _health = health,
       _measurements = measurements,
       _credentials = credentials;

  final HealthRepository _health;
  final MeasurementRepository _measurements;
  final AuthCredentialsStorage _credentials;
  final _logger = Logger('HealthWorkoutImporter');

  /// How far back every run looks. Workouts are few, so re-reading this much
  /// each time is cheap and picks up workouts synced late.
  static const lookBack = Duration(days: 30);

  /// Namespace of the ids of the categories created here.
  static const _categoryNamespace = '9b1f0c2e-6a57-4d3b-9c1e-5f2a7d8e4b60';

  /// Reads the workouts of the last [lookBack] and writes the minutes per day.
  /// Returns the number of written entries.
  Future<int> run({DateTime? now}) async {
    final end = now ?? DateTime.now();
    final workouts = await _health.readWorkouts(end.subtract(lookBack), end);
    if (workouts.isEmpty) {
      return 0;
    }

    // Without the owner, a created category could not get the id another
    // device derives for it, see _findOrCreateCategory
    final userId = await _credentials.dbOwnerUserId();
    if (userId == null) {
      _logger.warning('Local database has no owner, skipping the workout import');
      return 0;
    }
    final categories = await _measurements.getCategoriesOnce();
    var written = 0;
    for (final kind in WorkoutMinutesKind.values) {
      final ofKind = workouts.where((w) => kind.activityTypes.contains(w.activityType)).toList();
      if (ofKind.isEmpty) {
        continue;
      }
      final category = await _findOrCreateCategory(kind, categories, userId);
      written += await _writeDays(category, minutesPerDay(ofKind));
    }
    _logger.fine('Imported $written workout day entries');
    return written;
  }

  Future<MeasurementCategory> _findOrCreateCategory(
    WorkoutMinutesKind kind,
    List<MeasurementCategory> categories,
    String userId,
  ) async {
    final existing = categories.firstWhereOrNull(kind.matches);
    if (existing != null) {
      return existing;
    }
    // Derived from the user, so a second device creates the same category
    // rather than a duplicate
    final category = MeasurementCategory(
      id: ps.uuid.v5(_categoryNamespace, '$userId:${kind.name}'),
      name: kind.name,
      unit: 'min',
    );
    await _measurements.addLocalDriftCategory(category);
    categories.add(category);
    return category;
  }

  Future<int> _writeDays(MeasurementCategory category, Map<DateTime, double> days) async {
    final stored = await _measurements.getEntriesByExternalId(category.id!);
    var written = 0;
    for (final MapEntry(key: day, value: minutes) in days.entries) {
      // Two decimals, like the other aggregates: the server stores Decimal(…, 2)
      final value = (minutes * 100).roundToDouble() / 100;
      final externalId = dailyAggregateExternalId(category.id!, day);
      final existing = stored[externalId];
      if (existing == null) {
        await _measurements.addLocalDrift(
          MeasurementEntry(
            categoryId: category.id!,
            date: day,
            value: value,
            notes: '',
            source: _health.sourceName,
            externalId: externalId,
            extraData: const {'record_type': 'WORKOUT'},
          ),
        );
        written++;
      } else if (existing.value != value) {
        await _measurements.updateLocalDrift(existing.copyWith(value: value));
        written++;
      }
    }
    return written;
  }
}

/// The minutes of [workouts] per calendar day of their start, overlapping
/// workouts counted once.
Map<DateTime, double> minutesPerDay(List<HealthWorkout> workouts) {
  final byDay = groupBy(workouts, (w) => DateTime(w.start.year, w.start.month, w.start.day));
  return {
    for (final MapEntry(key: day, value: ofDay) in byDay.entries)
      day: mergedDurationMinutes(
        ofDay.map(
          (w) => HealthReading(
            type: HealthDataType.WORKOUT,
            value: 0,
            date: w.start,
            dateTo: w.end,
          ),
        ),
      ),
  };
}
