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
import 'package:wger/core/consts.dart';
import 'package:wger/features/routines/lift_export.dart';
import 'package:wger/features/routines/models/log.dart';
import 'package:wger/features/routines/models/session.dart';

void main() {
  // Local wall-clock times: the export writes local time and NOOP reads it in
  // the phone's zone, so the expectations use local DateTimes as well
  final start = DateTime(2026, 11, 24, 18);

  Log log(
    int exercise,
    int minute, {
    num? weight,
    num? reps,
    int? slotEntry,
    num? rir,
    int weightUnit = WEIGHT_UNIT_KG,
    int repsUnit = REP_UNIT_REPETITIONS_ID,
  }) {
    return Log(
      exerciseId: exercise,
      slotEntryId: slotEntry,
      weight: weight,
      repetitions: reps,
      rir: rir,
      weightUnitId: weightUnit,
      repetitionsUnitId: repsUnit,
      date: start.add(Duration(minutes: minute)),
    );
  }

  List<List<String>> rows(List<WorkoutSession> sessions, {Set<int> warmups = const {}}) {
    final csv = buildLiftExportCsv(
      sessions,
      exerciseName: (id) => {1: 'Bench Press', 2: 'Dips, weighted'}[id] ?? 'Exercise $id',
      isWarmup: (id) => warmups.contains(id),
      title: (_) => 'Push A',
    );
    return csv.trim().split('\n').map((line) => line.split(',')).toList();
  }

  test('writes the Hevy header NOOP reads', () {
    expect(rows([]).single, LIFT_EXPORT_HEADER);
  });

  test('one row per set with local times, the session end and 0-based set numbers', () {
    final session = WorkoutSession(
      routineId: 1,
      datetimeStart: start,
      datetimeEnd: start.add(const Duration(minutes: 65)),
      logs: [log(1, 5, weight: 80, reps: 8), log(1, 8, weight: 80, reps: 7)],
    );

    final result = rows([session]);

    expect(result, hasLength(3));
    expect(result[1], [
      'Push A',
      '2026-11-24 18:00:00',
      '2026-11-24 19:05:00',
      'Bench Press',
      '0',
      'normal',
      '80',
      '8',
      '',
    ]);
    expect(result[2][4], '1');
  });

  test('a session without an end ends with its last set', () {
    final session = WorkoutSession(
      routineId: 1,
      datetimeStart: start,
      logs: [log(1, 5, weight: 80, reps: 8), log(1, 40, weight: 80, reps: 8)],
    );

    expect(rows([session])[1][2], '2026-11-24 18:40:00');
  });

  test('sets from a warm-up slot entry are marked warmup', () {
    final session = WorkoutSession(
      routineId: 1,
      datetimeStart: start,
      logs: [
        log(1, 1, weight: 40, reps: 10, slotEntry: 9),
        log(1, 5, weight: 80, reps: 8, slotEntry: 10),
      ],
    );

    final result = rows([session], warmups: {9});

    expect(result[1][5], 'warmup');
    expect(result[2][5], 'normal');
  });

  test('pounds become kilograms, RiR becomes RPE, and non-rep units drop the reps', () {
    final session = WorkoutSession(
      routineId: 1,
      datetimeStart: start,
      logs: [
        log(1, 1, weight: 225, reps: 5, weightUnit: WEIGHT_UNIT_LB, rir: 2),
        log(1, 2, weight: 60, reps: 1, repsUnit: REP_UNIT_TILL_FAILURE_ID),
      ],
    );

    final result = rows([session]);

    expect(result[1][6], '102.058');
    expect(result[1][8], '8');
    expect(result[2][7], '');
  });

  test('set numbers count per exercise, in the order the sets were logged', () {
    final session = WorkoutSession(
      routineId: 1,
      datetimeStart: start,
      logs: [
        log(1, 9, weight: 82.5, reps: 6),
        log(2, 3, weight: 10, reps: 12),
        log(1, 1, weight: 80, reps: 8),
      ],
    );

    final result = csvLines(
      buildLiftExportCsv(
        [session],
        exerciseName: (id) => {1: 'Bench Press', 2: 'Dips, weighted'}[id]!,
        isWarmup: (_) => false,
        title: (_) => 'Push A',
      ),
    );

    // Bench 80 (0), dips (0, quoted for its comma), bench 82.5 (1)
    expect(result[1], contains('Bench Press,0,normal,80,8'));
    expect(result[2], contains('"Dips, weighted",0,normal,10,12'));
    expect(result[3], contains('Bench Press,1,normal,82.5,6'));
  });

  test('sessions without sets are left out, the others oldest first', () {
    final older = WorkoutSession(
      routineId: 1,
      datetimeStart: start,
      logs: [log(1, 1, weight: 80, reps: 8)],
    );
    final empty = WorkoutSession(routineId: 1, datetimeStart: start.add(const Duration(days: 1)));
    final newer = WorkoutSession(
      routineId: 1,
      datetimeStart: start.add(const Duration(days: 7)),
      logs: [log(1, 1, weight: 82.5, reps: 8)],
    );

    final result = rows([newer, empty, older]);

    expect(result, hasLength(3));
    expect(result[1][1], startsWith('2026-11-24'));
    expect(result[2][6], '82.5');
  });
}

List<String> csvLines(String csv) => csv.trim().split('\n');
