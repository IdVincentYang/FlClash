library;

import 'package:collection/collection.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/icons/icons.dart';
import 'package:fl_clash/models/clash_config.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';

final ruleItemHeight =
    globalState.measure.bodyLargeHeight +
    globalState.measure.bodyMediumHeight +
    12;

class RuleItem extends StatelessWidget {
  static const _targetMaxWidthFactor = 0.5;

  final bool isSelected;
  final bool isEditing;
  final Rule rule;
  final bool hasMatch;
  final void Function() onSelected;
  final void Function(Rule rule) onEdit;
  final String? Function(Rule rule)? invalidMessageOf;

  const RuleItem({
    super.key,
    required this.isSelected,
    required this.rule,
    required this.onSelected,
    required this.onEdit,
    this.invalidMessageOf,
    this.isEditing = false,
    this.hasMatch = false,
  });

  ({bool invalid, Color? color, String? message}) _checkInvalid(
    BuildContext context,
  ) {
    final message = invalidMessageOf?.call(rule);
    if (message == null && rule.ruleAction != RuleAction.SUB_RULE) {
      final ruleTarget = (rule.ruleTarget ?? '').toUpperCase();
      final color = switch (ruleTarget) {
        'DIRECT' => context.colorScheme.success,
        'REJECT' || 'REJECT-DROP' => context.colorScheme.warning,
        'MATCH' when hasMatch => context.colorScheme.tertiary,
        _ => null,
      };
      if (color != null) {
        return (invalid: false, color: color, message: null);
      }
    }
    final invalid = invalidMessageOf == null || message != null;
    return (
      invalid: invalid,
      color: invalid ? context.colorScheme.error : context.colorScheme.tertiary,
      message: message,
    );
  }

  Widget _buildInfoWidget(BuildContext context, String? message) {
    return CommonMinIconButtonTheme(
      child: IconButton(
        tooltip: context.appLocalizations.tip,
        onPressed: () {
          dialogs.showMessage(
            message: TextSpan(
              text:
                  message ??
                  rule.targetErrorTip(
                    context.appLocalizations.invalidSubRule(rule.subRule ?? ''),
                    context.appLocalizations.invalidPolicy(
                      rule.ruleTarget ?? '',
                    ),
                  ),
            ),
          );
        },
        icon: GlyphIcon(
          AppGlyphs.info,
          fill: 1,
          size: 16.ap,
          color: context.colorScheme.error,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final checkResult = _checkInvalid(context);
    final invalid = checkResult.invalid;
    return SelectedDecorationListItem(
      minVerticalPadding: 0,
      isSelected: isSelected,
      isEditing: isEditing,
      horizontalTitleGap: 0,
      invalid: invalid,
      onSelected: () {
        onSelected();
      },
      title: Center(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Row(
              mainAxisSize: MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: _RuleItemLabel(rule: rule)),
                const SizedBox(width: 16),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: constraints.maxWidth * _targetMaxWidthFactor,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (invalid)
                        _buildInfoWidget(context, checkResult.message),
                      if (rule.realTarget != null)
                        Flexible(
                          child: TooltipText(
                            text: Text(
                              hasMatch &&
                                      rule.realTarget!.toUpperCase() ==
                                          RuleAction.MATCH.value
                                  ? context.appLocalizations.matchTarget
                                  : rule.realTarget!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context
                                  .textTheme
                                  .bodyMedium
                                  ?.toJetBrainsMono
                                  .copyWith(color: checkResult.color),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
      onPressed: () {
        onEdit(rule);
      },
    );
  }
}

class _RuleItemLabel extends StatelessWidget {
  const _RuleItemLabel({required this.rule});

  final Rule rule;

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style.toJetBrainsMono;
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          rule.hostBinding == null
              ? rule.ruleAction.name
              : rule.hostBinding!.packageName ??
                    context.appLocalizations.appHostAllScope,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style.copyWith(
            fontSize: context.textTheme.bodyLarge?.fontSize,
          ),
        ),
        Flexible(
          child: TooltipText(
            text: Text(
              rule.realContent ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style.copyWith(
                fontSize: context.textTheme.bodyMedium?.fontSize,
                color: style.color?.opacity60,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class RuleStatusItem extends StatelessWidget {
  final bool status;
  final Rule rule;
  final void Function(bool) onChange;

  const RuleStatusItem({
    super.key,
    required this.status,
    required this.rule,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    return DecorationListItem(
      title: TooltipText(
        text: Text(
          rule.rawValue,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: context.textTheme.bodyMedium?.toJetBrainsMono,
        ),
      ),
      trailing: Switch(value: status, onChanged: onChange),
      onPressed: () {
        onChange(!status);
      },
    );
  }
}

class AddOrEditRuleDialog extends StatefulWidget {
  final Rule? rule;

  const AddOrEditRuleDialog({super.key, this.rule});

  @override
  State<AddOrEditRuleDialog> createState() => _AddOrEditRuleDialogState();
}

class _AddOrEditRuleDialogState extends State<AddOrEditRuleDialog> {
  final _editor = GlobalKey<RuleEditorFormState>();
  void _submit() {
    final rule = _editor.currentState?.validatedValue();
    if (rule != null) {
      Navigator.of(
        context,
      ).pop(rule.copyWith(id: widget.rule?.id ?? snowflake.id));
    }
  }

  @override
  Widget build(BuildContext context) => CommonDialog(
    title: widget.rule == null
        ? context.appLocalizations.addRule
        : context.appLocalizations.editRule,
    actions: [
      TextButton(
        onPressed: _submit,
        child: Text(context.appLocalizations.confirm),
      ),
    ],
    child: RuleEditorForm(
      key: _editor,
      rule: widget.rule ?? Rule.init(),
      onSubmitted: _submit,
    ),
  );
}

class RuleEditorForm extends StatefulWidget {
  const RuleEditorForm({
    super.key,
    required this.rule,
    this.onChanged,
    this.onSubmitted,
    this.fixedCondition = false,
    this.targetBuilder,
  });
  final Rule rule;
  final ValueChanged<Rule>? onChanged;
  final VoidCallback? onSubmitted;
  final bool fixedCondition;
  final Widget Function(BuildContext, Rule, ValueChanged<Rule>)? targetBuilder;
  @override
  State<RuleEditorForm> createState() => RuleEditorFormState();
}

class RuleEditorFormState extends State<RuleEditorForm> {
  final _content = TextEditingController();
  final _target = TextEditingController();
  final _form = GlobalKey<FormState>();
  late Rule _value;
  late List<DropdownMenuEntry> _targets;
  bool _initialized = false, _resetting = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _targets = [
      ...RuleTarget.values.map(
        (e) => DropdownMenuEntry(value: e.value, label: e.value),
      ),
      DropdownMenuEntry(
        value: RuleAction.MATCH.value,
        label: context.appLocalizations.matchTarget,
      ),
    ];
    _reset(widget.rule);
    _content.addListener(_contentChanged);
  }

  void _reset(Rule rule) {
    _resetting = true;
    _value = rule;
    _content.text = rule.content ?? '';
    _target.text =
        _targets.firstWhereOrNull((e) => e.value == rule.ruleTarget)?.label ??
        rule.ruleTarget ??
        '';
    _resetting = false;
  }

  @override
  void didUpdateWidget(RuleEditorForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rule != widget.rule && widget.rule != _value) {
      _reset(widget.rule);
    }
  }

  void _contentChanged() {
    if (_resetting) return;
    _value = _value.copyWith(content: _content.text);
    widget.onChanged?.call(_value);
  }

  void _update(Rule rule) {
    setState(() {
      _value = rule;
      _target.text =
          _targets.firstWhereOrNull((e) => e.value == rule.ruleTarget)?.label ??
          rule.ruleTarget ??
          '';
    });
    widget.onChanged?.call(rule);
  }

  Rule? validatedValue() =>
      _form.currentState?.validate() == true ? _value : null;
  @override
  void dispose() {
    _content.dispose();
    _target.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.appLocalizations;
    return DropdownMenuTheme(
      data: DropdownMenuThemeData(
        inputDecorationTheme: InputDecorationTheme(
          border: AppShape.input,
          labelStyle: context.textTheme.bodyLarge?.copyWith(
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FilledButton.tonal(
              onPressed: widget.fixedCondition
                  ? null
                  : () async {
                      final action = await dialogs.showCommonDialog<RuleAction>(
                        context: context,
                        child: OptionsDialog<RuleAction>(
                          title: l.ruleName,
                          options: RuleAction.addedRuleActions,
                          textBuilder: (item) => item.value,
                          value: _value.ruleAction,
                        ),
                      );
                      if (action != null && mounted) {
                        _update(_value.copyWith(ruleAction: action));
                      }
                    },
              child: Text(_value.ruleAction.value),
            ),
            const SizedBox(height: 24),
            _RuleContentField(
              controller: _content,
              readOnly: widget.fixedCondition,
              onSubmitted: () => widget.onSubmitted?.call(),
            ),
            const SizedBox(height: 24),
            widget.targetBuilder?.call(context, _value, _update) ??
                _RuleTargetField(
                  controller: _target,
                  entries: _targets,
                  onSelected: (value) {
                    if (value != null) {
                      _update(_value.copyWith(ruleTarget: value));
                    }
                  },
                ),
            if (_value.ruleAction.hasParams && !widget.fixedCondition) ...[
              const SizedBox(height: 20),
              Wrap(
                spacing: 8,
                children: [
                  _RuleFlagChip(
                    label: l.sourceIp,
                    isSelected: _value.src,
                    onPressed: () => _update(_value.copyWith(src: !_value.src)),
                  ),
                  _RuleFlagChip(
                    label: l.noResolve,
                    isSelected: _value.noResolve,
                    onPressed: () =>
                        _update(_value.copyWith(noResolve: !_value.noResolve)),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

class _RuleContentField extends StatelessWidget {
  const _RuleContentField({
    required this.controller,
    required this.onSubmitted,
    this.readOnly = false,
  });

  final TextEditingController controller;
  final VoidCallback onSubmitted;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    return TextFormField(
      readOnly: readOnly,
      keyboardType: TextInputType.text,
      inputFormatters: TextInputLimits.limit(TextInputLimits.rule),
      onFieldSubmitted: (_) {
        onSubmitted();
      },
      controller: controller,
      decoration: InputDecoration(labelText: appLocalizations.content),
      validator: (_) {
        if (controller.text.isEmpty) {
          return appLocalizations.emptyTip(appLocalizations.content);
        }
        return null;
      },
    );
  }
}

class _RuleTargetField extends StatelessWidget {
  const _RuleTargetField({
    required this.controller,
    required this.entries,
    required this.onSelected,
  });

  final TextEditingController controller;
  final List<DropdownMenuEntry> entries;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    return FormField<String>(
      validator: (_) {
        if (controller.text.isEmpty) {
          return appLocalizations.emptyTip(appLocalizations.ruleTarget);
        }
        return null;
      },
      builder: (filed) {
        return DropdownMenu(
          controller: controller,
          label: Text(appLocalizations.ruleTarget),
          width: 200,
          menuHeight: 250,
          enableFilter: false,
          enableSearch: false,
          trailingIcon: const GlyphIcon(AppGlyphs.chevronDown, size: 20),
          selectedTrailingIcon: const GlyphIcon(AppGlyphs.chevronUp, size: 20),
          dropdownMenuEntries: entries,
          onSelected: (value) => onSelected(value as String?),
          errorText: filed.errorText,
        );
      },
    );
  }
}

class _RuleFlagChip extends StatelessWidget {
  const _RuleFlagChip({
    required this.label,
    required this.isSelected,
    required this.onPressed,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return CommonCard(
      radius: AppCorner.sm,
      isSelected: isSelected,
      onPressed: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Text(label, style: context.textTheme.bodyMedium),
      ),
    );
  }
}
