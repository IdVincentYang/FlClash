import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/application_activity.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/application_activity.dart';
import 'package:fl_clash/views/application_connections.dart';
import 'package:fl_clash/views/application_targets.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class ConnectionActivityLinks extends ConsumerWidget {
  const ConnectionActivityLinks({
    super.key,
    required this.info,
    this.onOpenApplication,
    this.onOpenHost,
  });

  final TrackerInfo info;
  final VoidCallback? onOpenApplication, onOpenHost;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.appLocalizations;
    final identity = info.observation!.application;
    final packageName = identity.packageName;
    final package = ref
        .watch(applicationCatalogueProvider)
        .asData
        ?.value
        .packages
        .where((package) => package.packageName == packageName)
        .firstOrNull;
    final label =
        package?.label ??
        packageName ??
        (identity.status == 'ambiguous'
            ? l.activitySharedUid
            : l.activityUnknownApp);
    final appKey = applicationActivityKey(identity);
    final hostKey = activityHostKey(info);
    final target = info.metadata.host.isNotEmpty
        ? info.metadata.host
        : info.metadata.destinationIP;
    return generateSectionV3(
      title: l.applicationNetwork,
      items: [
        DetailRow(
          key: const ValueKey('connection-activity-app'),
          title: l.app,
          value: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis),
          copyText:
              packageName ??
              (identity.packages.isEmpty ? null : identity.packages.join('\n')),
          onPressed:
              onOpenApplication ??
              () => BaseNavigator.push(
                context,
                ApplicationTargetsView(
                  appKey: appKey,
                  label: label,
                  packageName: packageName,
                  identity: identity,
                ),
              ),
        ),
        if (target.isNotEmpty)
          DetailRow.text(
            key: const ValueKey('connection-activity-host'),
            title: l.host,
            value: target,
            onPressed:
                onOpenHost ??
                () => BaseNavigator.push(
                  context,
                  ApplicationConnectionsView(
                    appKey: appKey,
                    hostKey: hostKey,
                    appLabel: label,
                  ),
                ),
          ),
      ],
    );
  }
}
