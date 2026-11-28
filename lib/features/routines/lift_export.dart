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

import 'package:intl/intl.dart';
import 'package:wger/core/consts.dart';
import 'package:wger/features/routines/models/log.dart';
import 'package:wger/features/routines/models/session.dart';

/// Pounds per kilogram, the exact avoirdupois definition.
const LB_TO_KG = 0.45359237;

/// The columns of the export, Hevy's set-per-row layout, which NOOP's Lift Log
/// import (and its older lifting import) reads.
const LIFT_EXPORT_HEADER = [
  'title',
  'start_time',
  'end_time',
  'exercise_title',
  'set_index',
  'set_type',
  'weight_kg',
  'reps',
  'rpe',
];

final _timeFormat = DateFormat('yyyy-MM-dd HH:mm:ss');

/// Every logged set of [sessions] as a set-per-row CSV for NOOP.
///
/// Times are local wall clock without an offset, as Hevy writes them; NOOP
/// reads them in the phone's time zone. Weights are kilograms (pounds are
/// converted), RiR becomes RPE as 10 - RiR. `set_index` is 0-based per exercise
/// in the order the sets were logged, warm-ups included, and `set_type` says
/// `warmup` for a set from a warm-up slot entry.
String buildLiftExportCsv(
  List<WorkoutSession> sessions, {
  required String Function(int exerciseId) exerciseName,
  required bool Function(int? slotEntryId) isWarmup,
  required String Function(WorkoutSession session) title,
}) {
  final rows = <List<String>>[LIFT_EXPORT_HEADER];
  final ordered = [...sessions]..sort((a, b) => a.datetimeStart.compareTo(b.datetimeStart));

  for (final session in ordered) {
    final logs = [...session.logs]..sort((a, b) => a.date.compareTo(b.date));
    if (logs.isEmpty) {
      continue;
    }
    final end = session.datetimeEnd ?? logs.last.date;
    final counters = <int, int>{};
    for (final log in logs) {
      final index = counters[log.exerciseId] ?? 0;
      counters[log.exerciseId] = index + 1;
      final setType = isWarmup(log.slotEntryId) ? 'warmup' : 'normal';
      rows.add([
        title(session),
        _timeFormat.format(session.datetimeStart.toLocal()),
        _timeFormat.format(end.toLocal()),
        exerciseName(log.exerciseId),
        '$index',
        setType,
        _number(liftExportWeightKg(log)),
        _number(liftExportReps(log)),
        _number(liftExportRpe(log)),
      ]);
    }
  }
  return '${rows.map((row) => row.map(_csvField).join(',')).join('\n')}\n';
}

/// The set's weight in kilograms, null without one.
num? liftExportWeightKg(Log log) {
  final weight = log.weight;
  if (weight == null) {
    return null;
  }
  return log.weightUnitId == WEIGHT_UNIT_LB ? weight * LB_TO_KG : weight;
}

/// The repetitions, only when they count repetitions: a set logged in another
/// unit (until failure, seconds, ...) has no rep count NOOP could use.
num? liftExportReps(Log log) {
  final unit = log.repetitionsUnitId;
  if (unit != null && unit != REP_UNIT_REPETITIONS_ID) {
    return null;
  }
  return log.repetitions;
}

/// RPE from RiR (reps in reserve): 10 - RiR, within NOOP's 1 to 10.
num? liftExportRpe(Log log) {
  final rir = log.rir;
  if (rir == null) {
    return null;
  }
  return (10 - rir).clamp(1, 10);
}

String _number(num? value) {
  if (value == null) {
    return '';
  }
  // At most three decimals, without trailing zeros: 102.058, 80, 82.5
  final text = value.toStringAsFixed(3);
  return text.replaceFirst(RegExp(r'\.?0+$'), '');
}

String _csvField(String value) {
  if (value.contains(RegExp(r'[",\n\r]'))) {
    return '"${value.replaceAll('"', '""')}"';
  }
  return value;
}
