import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../theme/app_theme.dart';
import '../../widgets/kit.dart';
import 'plan_scenario.dart';

class PlanScenarioCard extends StatelessWidget {
  const PlanScenarioCard({
    super.key,
    required this.income,
    required this.planned,
    required this.spent,
    required this.recurring,
    required this.daysLeft,
    required this.currency,
  });

  final double? income;
  final double planned;
  final double spent;
  final double recurring;
  final int daysLeft;
  final String currency;

  @override
  Widget build(BuildContext context) => AppCard(
    fill: AppColors.surfaceContainerLow,
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          const Icon(Icons.auto_graph_outlined, color: AppColors.primary),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Test a change to income, caps, or recurring charges before applying it.',
            ),
          ),
          Semantics(
            button: true,
            label: income == null
                ? 'Set plan income before trying a scenario'
                : 'Open what-if plan scenario',
            child: TextButton(
              onPressed: income == null
                  ? null
                  : () => showDialog<void>(
                      context: context,
                      builder: (_) => _PlanScenarioDialog(
                        income: income!,
                        planned: planned,
                        spent: spent,
                        recurring: recurring,
                        daysLeft: daysLeft,
                        currency: currency,
                      ),
                    ),
              child: const Text('Try scenario'),
            ),
          ),
        ],
      ),
    ),
  );
}

class _PlanScenarioDialog extends StatefulWidget {
  const _PlanScenarioDialog({
    required this.income,
    required this.planned,
    required this.spent,
    required this.recurring,
    required this.daysLeft,
    required this.currency,
  });

  final double income;
  final double planned;
  final double spent;
  final double recurring;
  final int daysLeft;
  final String currency;

  @override
  State<_PlanScenarioDialog> createState() => _PlanScenarioDialogState();
}

class _PlanScenarioDialogState extends State<_PlanScenarioDialog> {
  final _income = TextEditingController(text: '0');
  final _caps = TextEditingController(text: '0');
  final _recurring = TextEditingController(text: '0');

  @override
  void dispose() {
    _income.dispose();
    _caps.dispose();
    _recurring.dispose();
    super.dispose();
  }

  double _value(TextEditingController controller) =>
      double.tryParse(controller.text.trim().replaceAll(',', '.')) ?? 0;

  @override
  Widget build(BuildContext context) {
    final result = simulatePlan(
      income: widget.income,
      planned: widget.planned,
      spent: widget.spent,
      recurring: widget.recurring,
      daysLeft: widget.daysLeft,
      incomeAdjustment: _value(_income),
      capAdjustment: _value(_caps),
      recurringAdjustment: _value(_recurring),
    );
    return AlertDialog(
      title: const Text('What-if scenario'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _AdjustmentField(
              controller: _income,
              label: 'Income change',
              currency: widget.currency,
              onChanged: () => setState(() {}),
            ),
            _AdjustmentField(
              controller: _caps,
              label: 'Total cap change',
              currency: widget.currency,
              onChanged: () => setState(() {}),
            ),
            _AdjustmentField(
              controller: _recurring,
              label: 'Recurring charge change',
              currency: widget.currency,
              onChanged: () => setState(() {}),
            ),
            const SizedBox(height: 14),
            _ScenarioMetric(
              label: 'SAFE PER DAY',
              value: fmtCurrency(
                result.safeDailyAmount,
                currency: widget.currency,
              ),
            ),
            _ScenarioMetric(
              label: 'UNASSIGNED',
              value: fmtCurrency(result.unassigned, currency: widget.currency),
            ),
            _ScenarioMetric(
              label: 'RECURRING',
              value: fmtCurrency(result.recurring, currency: widget.currency),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _AdjustmentField extends StatelessWidget {
  const _AdjustmentField({
    required this.controller,
    required this.label,
    required this.currency,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final String currency;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(
        decimal: true,
        signed: true,
      ),
      decoration: InputDecoration(labelText: label, suffixText: currency),
      onChanged: (_) => onChanged(),
    ),
  );
}

class _ScenarioMetric extends StatelessWidget {
  const _ScenarioMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      children: [
        Expanded(child: Text(label, style: AppTextStyles.labelCaps)),
        Text(value, style: AppTextStyles.monoData),
      ],
    ),
  );
}
