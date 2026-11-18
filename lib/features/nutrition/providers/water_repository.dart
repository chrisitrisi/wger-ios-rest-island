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

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:health_bridge/health.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wger/core/consts.dart';
import 'package:wger/core/shared_preferences.dart';
import 'package:wger/features/health/providers/health_repository.dart';

final waterRepositoryProvider = Provider<WaterRepository>((ref) => WaterRepository());

/// The goal a fresh install starts with.
const DEFAULT_WATER_GOAL_LITERS = 3.0;

/// Thrown when the health platform did not store a drink.
class WaterWriteException implements Exception {
  const WaterWriteException();

  @override
  String toString() => 'WaterWriteException: the health platform did not store the drink';
}

/// Water tracking on top of Apple Health / Health Connect.
///
/// The platform is the single store for the drinks: wger writes there and
/// reads the day's total back, so water logged in other apps (or by an iOS
/// Shortcut) counts too, and a Shortcut automation can compare the same total
/// against the goal. Only the goal is kept locally, in the preferences.
class WaterRepository {
  WaterRepository({Health? health, SharedPreferencesAsync? prefs, bool? isSupported})
    : _health = health ?? Health(),
      _prefs = prefs ?? PreferenceHelper.asyncPref,
      _isSupported = isSupported;

  final Health _health;
  final SharedPreferencesAsync _prefs;
  final bool? _isSupported;

  static const _types = [HealthDataType.WATER];

  /// Whether this device has a health platform at all (not web or desktop).
  bool get isSupported => _isSupported ?? (!kIsWeb && (Platform.isIOS || Platform.isAndroid));

  Future<double> readGoalLiters() async =>
      await _prefs.getDouble(PREFS_WATER_GOAL_LITERS) ?? DEFAULT_WATER_GOAL_LITERS;

  Future<void> saveGoalLiters(double liters) => _prefs.setDouble(PREFS_WATER_GOAL_LITERS, liters);

  /// Asks for read and write access to water. Shows the platform's permission
  /// dialog the first time, so only call this from a tap.
  Future<bool> ensureAuthorized() async {
    await _health.configure();
    return _health.requestAuthorization(
      _types,
      permissions: const [HealthDataAccess.READ_WRITE],
    );
  }

  /// Stores one drink of [liters] at [at].
  Future<void> addWater(double liters, DateTime at) async {
    await _health.configure();
    final id = await _health.writeHealthData(
      value: liters,
      unit: HealthDataUnit.LITER,
      type: HealthDataType.WATER,
      startTime: at,
      recordingMethod: RecordingMethod.manual,
    );
    if (id == null) {
      throw const WaterWriteException();
    }
  }

  /// The liters drunk between [start] and [end], from every app writing water.
  ///
  /// Zero while access was never asked for: HealthKit throws instead of
  /// returning nothing then (see [HealthRepository.isAuthorizationMissing]),
  /// and a card that has not been tapped yet should show an empty glass, not
  /// an error. Any other failure propagates.
  Future<double> totalLiters(DateTime start, DateTime end) async {
    await _health.configure();
    final List<HealthDataPoint> points;
    try {
      points = await _health.getHealthDataFromTypes(
        types: _types,
        startTime: start,
        endTime: end,
      );
    } catch (e) {
      if (HealthRepository.isAuthorizationMissing(e)) {
        return 0;
      }
      rethrow;
    }
    return points.fold<double>(0, (sum, point) {
      final value = point.value;
      return value is NumericHealthValue ? sum + value.numericValue.toDouble() : sum;
    });
  }
}
