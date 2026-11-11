/*
 * This file is part of wger Workout Manager <https://github.com/wger-project>.
 * Copyright (c)  2026 wger Team
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

import 'dart:async';
import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wger/core/date.dart';
import 'package:wger/core/keys.dart';
import 'package:wger/core/network/auth_notifier.dart';
import 'package:wger/core/network/auth_state.dart';
import 'package:wger/core/shared_preferences.dart';
import 'package:wger/features/routines/models/day_data.dart';
import 'package:wger/features/routines/models/workout_progress.dart';
import 'package:wger/features/routines/notifications/workout_notification_controller.dart';
import 'package:wger/features/routines/providers/gym_state.dart';
import 'package:wger/features/routines/providers/gym_state_notifier.dart';
import 'package:wger/features/routines/providers/routines_notifier.dart';
import 'package:wger/features/routines/providers/workout_session_notifier.dart';
import 'package:wger/features/routines/screens/gym_mode.dart';
import 'package:wger/features/routines/screens/routine_list_screen.dart';

const _channel = MethodChannel('de.wger.flutter/workout-shortcuts');

Never _fail(String message) => throw PlatformException(code: 'workout', message: message);

/// Index a workout by the local calendar day or by its explicit plan label.
DayData? shortcutDay(Iterable<DayData> days, String name, DateTime today) {
  final label = name.trim().toLowerCase();
  return days.firstWhereOrNull((entry) {
    final day = entry.day;
    if (day == null || day.id == null || day.isRest || entry.slots.isEmpty) {
      return false;
    }
    return label.isEmpty ? entry.date.isSameDayAs(today) : day.name.trim().toLowerCase() == label;
  });
}

final workoutShortcutsProvider = Provider<void>((ref) {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
    return;
  }
  var busy = false;
  _channel.setMethodCallHandler((call) async {
    if (busy) {
      _fail('Eine wger-Aktion läuft bereits. Versuche es danach erneut.');
    }
    busy = true;
    try {
      return await _perform(ref, call);
    } on PlatformException {
      rethrow;
    } catch (_) {
      _fail('Die Aktion ist fehlgeschlagen. Prüfe in wger deinen Trainingsplan und die Verbindung.');
    } finally {
      busy = false;
    }
  });
  unawaited(_channel.invokeMethod<void>('ready').catchError((Object e) {
    if (e is! MissingPluginException) {
      throw e;
    }
  }));
  ref.onDispose(() => _channel.setMethodCallHandler(null));
});

Future<String> _perform(Ref ref, MethodCall call) async {
  final auth = await ref.read(authProvider.future);
  if (auth.status != AuthStatus.loggedIn) {
    _fail('Öffne wger und melde dich an.');
  }
  await WidgetsBinding.instance.endOfFrame;
  final nav = navigatorKey.currentState;
  if (nav == null) {
    _fail('Die Trainingsansicht ist noch nicht bereit.');
  }
  if (call.method == 'plans') {
    unawaited(nav.pushNamed<void>(RoutineListScreen.routeName));
    return 'Trainingspläne geöffnet';
  }

  final notifier = ref.read(gymStateProvider.notifier);
  var state = ref.read(gymStateProvider);
  final now = clock.now();
  final name = call.argument<String>('day') ?? '';
  if (!state.isInitialized || state.validUntil.isBefore(now)) {
    final raw = await PreferenceHelper.asyncPref.getString(PREFS_WORKOUT_PROGRESS);
    WorkoutProgress? saved;
    int? routineId;
    if (raw != null) {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final previous = WorkoutProgress.fromJson(data);
      if (previous.validUntil.isAfter(now) && previous.currentPageKey != 'start') {
        saved = previous;
        routineId = data['routineId'] as int?;
      }
    }
    if (saved == null && call.method != 'start') {
      if (call.method == 'status') {
        return jsonEncode({'active': false});
      }
      _fail('Es läuft kein Workout.');
    }
    final routines = await ref.read(routinesRiverpodProvider.future);
    var routine = routineId == null ? routines.currentRoutine : routines.findByIdOrNull(routineId);
    if (routine == null || routine.id == null) {
      _fail('Kein passender Trainingsplan verfügbar.');
    }
    if (!routine.isHydrated) {
      routine = await ref.read(routinesRiverpodProvider.notifier).fetchAndSetRoutineFull(routine.id!);
    }
    final previous = saved;
    final day = previous == null
        ? shortcutDay(routine.dayDataCurrentIterationGym, name, now)
        : routine.dayDataGym.firstWhereOrNull((d) => d.day?.id == previous.dayId && d.iteration == previous.iteration);
    if (day == null) {
      if (saved != null) {
        _fail('Öffne den zuletzt verwendeten Trainingstag in wger.');
      }
      _fail('Kein passender Trainingstag. Gib im Kurzbefehl den Namen aus deinem Plan an.');
    }
    if (ref.read(authProvider).value?.status != AuthStatus.loggedIn) {
      _fail('Melde dich in wger an.');
    }
    await notifier.open(routine, day.day!.id!, day.iteration);
    state = ref.read(gymStateProvider);
  }

  if (call.method == 'start') {
    if (name.trim().isNotEmpty && state.dayDataGym.day!.name.trim().toLowerCase() != name.trim().toLowerCase()) {
      _fail('Ein anderer Trainingstag ist bereits geöffnet.');
    }
    if (state.currentPage == 0) {
      notifier.startWorkout();
      notifier.setCurrentPage(1);
    }
  } else if (state.currentPage == 0) {
    if (call.method == 'status') {
      return jsonEncode({'active': false});
    }
    _fail('Starte zuerst das Workout.');
  }

  final page = state.getSlotEntryPageByIndex();
  switch (call.method) {
    case 'start':
    case 'finish':
      if (call.method == 'finish') {
        notifier.setCurrentPage(state.pages.firstWhere((p) => p.type == PageType.session).pageIndex);
      }
      if (ref.read(gymModeVisibleProvider)) {
        nav.popUntil((route) => route.settings.name == GymModeScreen.routeName || route.isFirst);
      } else {
        unawaited(nav.pushNamed<void>(GymModeScreen.routeName,
          arguments: GymModeArguments(state.routine.id!, state.dayId, state.iteration, alreadyOpened: true)));
        await WidgetsBinding.instance.endOfFrame;
      }
      return call.method == 'finish' ? 'Abschluss geöffnet. Tippe zum Abschließen auf Speichern.' : state.dayDataGym.day!.name;
    case 'saveFinish':
      final entries = state.progress.values.where((p) => p.done).map((p) => p.loggedEntry);
      final ids = entries.map((entry) => entry?.sessionId).toSet();
      if (ids.length > 1 || ids.contains(null)) {
        _fail('Prüfe die zugeordneten Sätze unter „Workoutabschluss öffnen“.');
      }
      await ref.read(workoutSessionProvider.future);
      final saved = await ref.read(workoutSessionProvider.notifier).finishGymSession(
        routineId: state.routine.id!,
        dayId: state.dayId,
        start: state.workoutStart,
        end: now,
        sessionId: ids.firstOrNull,
      );
      if (!saved) {
        _fail('Prüfe die Sitzung unter „Workoutabschluss öffnen“.');
      }
      if (ref.read(gymModeVisibleProvider)) {
        nav.popUntil((route) => route.settings.name == GymModeScreen.routeName || route.isFirst);
        if (nav.canPop()) {
          nav.pop();
        }
      }
      notifier.clear();
      return now.toUtc().toIso8601String();
    case 'log':
      if (page?.type != SlotPageType.log || !await notifier.logPlannedSet(page!.key)) {
        _fail('Öffne einen ungespeicherten Satz mit vollständigen Werten.');
      }
      return 'Satz gespeichert';
    case 'skip':
      if (page?.type != SlotPageType.timer) {
        _fail('Keine Satzpause aktiv.');
      }
      notifier.skipRest();
      return 'Satzpause übersprungen';
    case 'extend':
      final seconds = call.argument<int>('seconds') ?? 30;
      if (seconds < 1 || seconds > 1800) {
        _fail('Wähle zwischen 1 und 1800 Sekunden.');
      }
      if (state.restEndsAt == null) {
        _fail('Kein Pausen-Countdown aktiv.');
      }
      notifier.extendRest(Duration(seconds: seconds));
      return 'Satzpause verlängert';
    case 'status':
      return jsonEncode({
        'active': true,
        'routine': state.routine.name,
        'day': state.dayDataGym.day!.name,
        'startedAt': state.workoutStart.toUtc().toIso8601String(),
        'restEndsAt': state.restEndsAt?.toUtc().toIso8601String(),
        'completedSets': state.progress.values.where((p) => p.done).length,
      });
    default:
      _fail('Unbekannte Workout-Aktion.');
  }
}
