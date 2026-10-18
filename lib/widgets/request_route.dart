import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/widgets/list.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class RequestRouteFields extends ConsumerWidget {
  const RequestRouteFields({
    super.key,
    required this.mode,
    this.proxy,
    required this.onChanged,
  });
  final RequestMode mode;
  final String? proxy;
  final ValueChanged<(RequestMode, String?)> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = context.appLocalizations;
    final groups = ref.watch(groupsProvider);
    final fact = ref.watch(configStateProvider).fact;
    final managed = fact.isManaged;
    final selected = managed
        ? fact.maintenanceProxy
        : ref.watch(selectedMapProvider)['GLOBAL'] ??
              groups.getGroup('GLOBAL')?.now ??
              '';
    final names = <String>{
      'GLOBAL',
      if (proxy != null && proxy!.isNotEmpty) proxy!,
      for (final group in groups) ...[
        if (!managed || group.name.startsWith('fc-managed-group-')) group.name,
        for (final node in group.all)
          if (!managed || node.name.startsWith('fc-managed-proxy-')) node.name,
      ],
    }.toList();
    String label(RequestMode value) => switch (value) {
      RequestMode.auto => strings.requestModeAuto,
      RequestMode.proxy => strings.requestModeProxy,
      RequestMode.direct => strings.requestModeDirect,
    };
    return ExpansionTile(
      title: Text(strings.advancedConfig),
      children: [
        ListItem<RequestMode>.options(
          title: Text(strings.requestMode),
          subtitle: Text(label(mode)),
          dialogTitle: strings.requestMode,
          options: RequestMode.values,
          value: mode,
          textBuilder: label,
          onChanged: (value) {
            if (value != null) onChanged((value, proxy));
          },
        ),
        if (mode == RequestMode.proxy)
          ListItem<String>.options(
            title: Text(strings.requestProxyTarget),
            subtitle: Text(
              proxy == null || proxy!.isEmpty || proxy == 'GLOBAL'
                  ? strings.requestProxyDefault(selected)
                  : proxy!,
            ),
            dialogTitle: strings.requestProxyTarget,
            options: names,
            value: proxy == null || proxy!.isEmpty ? 'GLOBAL' : proxy!,
            textBuilder: (name) =>
                name == 'GLOBAL' ? strings.requestProxyDefault(selected) : name,
            onChanged: (name) {
              if (name != null) onChanged((mode, name));
            },
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(strings.requestModeHelp),
        ),
        if (managed &&
            (selected.isEmpty ||
                proxy != null &&
                    proxy != 'GLOBAL' &&
                    !proxy!.startsWith('fc-managed-')))
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(strings.policyMaintenanceRequired),
          ),
      ],
    );
  }
}
