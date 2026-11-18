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
import 'package:material_ui/material_ui.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:wger/core/widgets/dashboard/widgets/water.dart';
import 'package:wger/features/nutrition/providers/water_repository.dart';
import 'package:wger/l10n/generated/app_localizations.dart';
import 'package:wger/l10n/localizations_delegates.dart';

import 'water_test.mocks.dart';

@GenerateMocks([WaterRepository])
void main() {
  late MockWaterRepository repo;

  Widget renderWidget({Locale locale = const Locale('en')}) {
    return ProviderScope(
      overrides: [waterRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: SingleChildScrollView(child: DashboardWaterWidget())),
      ),
    );
  }

  Future<void> pump(WidgetTester tester, {Locale locale = const Locale('en')}) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(renderWidget(locale: locale));
    await tester.pumpAndSettle();
  }

  setUp(() {
    repo = MockWaterRepository();
    when(repo.isSupported).thenReturn(true);
    when(repo.readGoalLiters()).thenAnswer((_) async => 3);
    when(repo.totalLiters(any, any)).thenAnswer((_) async => 1.2);
  });

  testWidgets('shows today against the goal', (tester) async {
    await pump(tester);

    expect(find.text('1.2 of 3 L'), findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
    expect(bar.value, closeTo(1.2 / 3, 1e-9));
  });

  testWidgets('formats liters with the locale decimal separator', (tester) async {
    await pump(tester, locale: const Locale('de'));

    expect(find.text('1,2 von 3 L'), findsOneWidget);
  });

  testWidgets('says so once the goal is reached', (tester) async {
    when(repo.totalLiters(any, any)).thenAnswer((_) async => 3.2);
    await pump(tester);

    expect(find.text('3.2 of 3 L · Goal reached'), findsOneWidget);
  });

  testWidgets('a quick button logs that many milliliters', (tester) async {
    when(repo.ensureAuthorized()).thenAnswer((_) async => true);
    when(repo.addWater(any, any)).thenAnswer((_) async {});
    await pump(tester);

    await tester.tap(find.text('+500 ml'));
    await tester.pumpAndSettle();

    verify(repo.addWater(0.5, any)).called(1);
  });

  testWidgets('explains a missing permission instead of logging', (tester) async {
    when(repo.ensureAuthorized()).thenAnswer((_) async => false);
    await pump(tester);

    await tester.tap(find.text('+250 ml'));
    await tester.pumpAndSettle();

    verifyNever(repo.addWater(any, any));
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('the goal dialog saves the new goal', (tester) async {
    when(repo.saveGoalLiters(any)).thenAnswer((_) async {});
    await pump(tester);

    await tester.tap(find.byTooltip('Daily water goal'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '2.5');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    verify(repo.saveGoalLiters(2.5)).called(1);
  });

  testWidgets('offers no buttons without a health platform', (tester) async {
    when(repo.isSupported).thenReturn(false);
    await pump(tester);

    expect(find.text('Logging water needs Apple Health or Health Connect'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
  });
}
