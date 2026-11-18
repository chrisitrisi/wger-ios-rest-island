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
import 'package:material_ui/material_ui.dart';
import 'package:wger/core/formatting/formatting.dart';
import 'package:wger/core/snackbar.dart';
import 'package:wger/core/widgets/async_value_widget.dart';
import 'package:wger/core/widgets/decimal_input.dart';
import 'package:wger/core/widgets/error.dart';
import 'package:wger/features/nutrition/providers/water_notifier.dart';
import 'package:wger/l10n/generated/app_localizations.dart';

/// The drink sizes offered as one-tap buttons, in milliliters.
const waterQuickAmounts = [250, 500];

/// Today's water against the daily goal, with one-tap buttons to log a drink.
class DashboardWaterWidget extends ConsumerStatefulWidget {
  const DashboardWaterWidget({super.key});

  @override
  ConsumerState<DashboardWaterWidget> createState() => _DashboardWaterWidgetState();
}

class _DashboardWaterWidgetState extends ConsumerState<DashboardWaterWidget> {
  /// While a drink is being written, so a double tap can't log it twice.
  bool _adding = false;

  Widget _shell({required String subtitle, Widget? trailing, List<Widget> children = const []}) {
    final i18n = AppLocalizations.of(context);
    return Card(
      child: Column(
        children: [
          ListTile(
            title: Text(i18n.water, style: Theme.of(context).textTheme.headlineSmall),
            subtitle: Text(subtitle),
            leading: Icon(
              Icons.water_drop_outlined,
              color: Theme.of(context).textTheme.headlineSmall!.color,
            ),
            trailing: trailing,
          ),
          ...children,
        ],
      ),
    );
  }

  Future<void> _add(int milliliters) async {
    setState(() => _adding = true);
    try {
      final stored = await ref.read(waterProvider.notifier).addWater(milliliters);
      if (!stored && mounted) {
        showSnackbar(context, AppLocalizations.of(context).waterPermissionDenied);
      }
    } finally {
      if (mounted) {
        setState(() => _adding = false);
      }
    }
  }

  Future<void> _editGoal(double current) async {
    final goal = await showDialog<double>(
      context: context,
      builder: (_) => WaterGoalDialog(goalLiters: current),
    );
    if (goal != null) {
      await ref.read(waterProvider.notifier).setGoal(goal);
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    final numberFormat = localizedNumberFormat(context)
      ..minimumFractionDigits = 0
      ..maximumFractionDigits = 1;

    return AsyncValueWidget<WaterState>(
      value: ref.watch(waterProvider),
      loggerName: 'DashboardWaterWidget',
      loading: _shell(
        subtitle: '',
        trailing: const SizedBox(
          height: 20,
          width: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      errorBuilder: (e, st) => _shell(
        subtitle: i18n.anErrorOccurred,
        trailing: const Icon(Icons.error_outline, color: Colors.red),
        children: [StreamErrorIndicator(e, stacktrace: st)],
      ),
      data: (state) {
        if (!state.isSupported) {
          return _shell(subtitle: i18n.waterNotSupported);
        }

        final progress = i18n.waterProgress(
          numberFormat.format(state.todayLiters),
          numberFormat.format(state.goalLiters),
        );
        return _shell(
          subtitle: state.goalReached ? '$progress · ${i18n.waterGoalReached}' : progress,
          trailing: IconButton(
            icon: const Icon(Icons.flag_outlined),
            tooltip: i18n.waterGoal,
            onPressed: () => _editGoal(state.goalLiters),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: LinearProgressIndicator(value: state.progress, minHeight: 8),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  for (final amount in waterQuickAmounts)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: FilledButton.tonal(
                        onPressed: _adding ? null : () => _add(amount),
                        child: Text(i18n.waterAdd(amount)),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Edits the daily water goal; pops with the new goal in liters, or null.
class WaterGoalDialog extends StatefulWidget {
  const WaterGoalDialog({required this.goalLiters, super.key});

  final double goalLiters;

  @override
  State<WaterGoalDialog> createState() => _WaterGoalDialogState();
}

class _WaterGoalDialogState extends State<WaterGoalDialog> {
  final _formKey = GlobalKey<FormState>();
  late double? _draft;

  @override
  void initState() {
    super.initState();
    _draft = widget.goalLiters;
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    final materialL10n = MaterialLocalizations.of(context);

    return AlertDialog(
      title: Text(i18n.waterGoal),
      content: Form(
        key: _formKey,
        child: DecimalInputWidget(
          value: _draft,
          labelText: i18n.waterGoal,
          suffixText: 'L',
          isRequired: true,
          min: 0.1,
          max: 20,
          onChanged: (value) => _draft = value?.toDouble(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(materialL10n.cancelButtonLabel),
        ),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState!.validate() && _draft != null) {
              Navigator.of(context).pop(_draft);
            }
          },
          child: Text(materialL10n.saveButtonLabel),
        ),
      ],
    );
  }
}
