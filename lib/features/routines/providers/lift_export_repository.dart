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

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wger/database/powersync/database.dart';
import 'package:wger/features/routines/lift_export.dart';
import 'package:wger/features/routines/models/session.dart';
import 'package:wger/features/routines/models/slot_entry.dart';
import 'package:wger/features/routines/providers/routines_repository.dart';
import 'package:wger/features/routines/providers/workout_session_repository.dart';

final liftExportRepositoryProvider = Provider<LiftExportRepository>((ref) {
  return LiftExportRepository(
    ref.read(driftPowerSyncDatabase),
    ref.read(workoutSessionRepositoryProvider),
    ref.read(routinesRepositoryProvider),
  );
});

/// What an export wrote.
class LiftExportResult {
  const LiftExportResult({required this.file, required this.sessions, required this.sets});

  final File file;
  final int sessions;
  final int sets;
}

/// Writes every logged set as a CSV that NOOP's Lift Log imports.
class LiftExportRepository {
  LiftExportRepository(this._db, this._sessions, this._routines);

  static const fileName = 'wger-lifts-for-noop.csv';

  final DriftPowersyncDatabase _db;
  final WorkoutSessionRepository _sessions;
  final RoutinesRepository _routines;
  final _logger = Logger('LiftExportRepository');

  /// Exercise names in [languageCode], falling back to English, then to any
  /// translation; an exercise without one is named by its id.
  Future<Map<int, String>> exerciseNames(Set<int> exerciseIds, String languageCode) async {
    if (exerciseIds.isEmpty) {
      return {};
    }
    final query = _db.select(_db.exerciseTranslationTable).join([
      innerJoin(
        _db.languageTable,
        _db.languageTable.id.equalsExp(_db.exerciseTranslationTable.languageId),
      ),
    ])..where(_db.exerciseTranslationTable.exerciseId.isIn(exerciseIds));

    final candidates = <int, Map<String, String>>{};
    for (final row in await query.get()) {
      final translation = row.readTable(_db.exerciseTranslationTable);
      final language = row.readTable(_db.languageTable);
      candidates.putIfAbsent(translation.exerciseId, () => {})[language.shortName] =
          translation.name;
    }
    return {
      for (final id in exerciseIds)
        id: liftExportPickName(candidates[id] ?? const {}, languageCode) ?? 'Exercise $id',
    };
  }

  /// The warm-up slot entry ids and the training day names of [routineIds],
  /// read from the server. A routine that can't be loaded (offline, deleted)
  /// only costs its warm-up marks and day names; its sets are still exported.
  Future<({Set<int> warmupSlotEntryIds, Map<int, String> dayNames})> routineInfo(
    Set<int> routineIds,
  ) async {
    final ids = <int>{};
    final dayNames = <int, String>{};
    for (final routineId in routineIds) {
      try {
        final routine = await _routines.fetchAndSetRoutineFullServer(routineId);
        for (final day in routine.days) {
          if (day.id != null && day.name.trim().isNotEmpty) {
            dayNames[day.id!] = day.name.trim();
          }
          for (final slot in day.slots) {
            for (final entry in slot.entries) {
              if (entry.type == SlotEntryType.warmup && entry.id != null) {
                ids.add(entry.id!);
              }
            }
          }
        }
      } catch (e) {
        _logger.warning('Could not read routine $routineId for warm-up sets: $e');
      }
    }
    return (warmupSlotEntryIds: ids, dayNames: dayNames);
  }

  Future<LiftExportResult> export(String languageCode) async {
    final sessions = (await _sessions.watchAllDrift().first)
        .where((s) => s.logs.isNotEmpty)
        .toList();
    final exerciseIds = {for (final s in sessions) ...s.logs.map((l) => l.exerciseId)};
    final routineIds = {for (final s in sessions) ?s.routineId};
    final names = await exerciseNames(exerciseIds, languageCode);
    final info = await routineInfo(routineIds);

    final csv = buildLiftExportCsv(
      sessions,
      exerciseName: (id) => names[id] ?? 'Exercise $id',
      isWarmup: (slotEntryId) =>
          slotEntryId != null && info.warmupSlotEntryIds.contains(slotEntryId),
      title: (WorkoutSession session) => info.dayNames[session.dayId] ?? 'wger',
    );
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/$fileName');
    await file.writeAsString(csv);
    final sets = sessions.fold<int>(0, (sum, s) => sum + s.logs.length);
    _logger.info('Exported ${sessions.length} sessions with $sets sets');
    return LiftExportResult(file: file, sessions: sessions.length, sets: sets);
  }
}

/// The translation to export: the app's language, else English, else any.
String? liftExportPickName(Map<String, String> byLanguage, String languageCode) =>
    byLanguage[languageCode] ?? byLanguage['en'] ?? byLanguage.values.firstOrNull;
