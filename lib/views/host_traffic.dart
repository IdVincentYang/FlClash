import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/host_traffic.dart';
import 'package:fl_clash/models/common.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/config_state.dart';
import 'package:fl_clash/providers/core.dart';
import 'package:fl_clash/providers/request_state.dart';
import 'package:fl_clash/views/application_connections.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../common/android_service_state.dart';

final _hostTrafficProvider = NotifierProvider<_HostTraffic, _RankingState>(
  _HostTraffic.new,
);

typedef _RankingState = ({HostTrafficSnapshot? snapshot, bool failed});

class _HostTraffic extends Notifier<_RankingState> {
  bool _busy = false;

  @override
  _RankingState build() => (snapshot: null, failed: false);

  Future<void> refresh() async {
    if (_busy) return;
    _busy = true;
    try {
      final snapshot = await ref
          .read(coreHandlerProvider)
          .getHostTraffic()
          .timeout(const Duration(seconds: 5));
      if (!ref.mounted) return;
      final epoch = ref.read(configStateProvider).fact.runtimeEpoch;
      if (epoch.isNotEmpty && epoch != snapshot.runtimeEpoch) return;
      state = (snapshot: snapshot, failed: false);
    } catch (_) {
      if (ref.mounted) state = (snapshot: state.snapshot, failed: true);
    } finally {
      _busy = false;
    }
  }
}

bool _running(AndroidServiceStatus status) =>
    status == AndroidServiceStatus.vpnActive ||
    status == AndroidServiceStatus.proxyOnly;

class HostTrafficView extends ConsumerStatefulWidget {
  const HostTrafficView({super.key});

  @override
  ConsumerState<HostTrafficView> createState() => _HostTrafficViewState();
}

class _HostTrafficViewState extends ConsumerState<HostTrafficView> {
  late final Timer _timer;
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
  }

  void _refresh() {
    if (!mounted ||
        ModalRoute.of(context)?.isCurrent == false ||
        !ref.read(appVisibleProvider) ||
        !_running(ref.read(androidServiceStatusProvider))) {
      return;
    }
    unawaited(ref.read(_hostTrafficProvider.notifier).refresh());
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.appLocalizations;
    ref.listen(appVisibleProvider, (_, visible) {
      if (visible) _refresh();
    });
    ref.listen(androidServiceStatusProvider, (_, next) {
      if (_running(next)) _refresh();
    });
    final status = ref.watch(androidServiceStatusProvider);
    final running = _running(status);
    final stopped =
        status == AndroidServiceStatus.stopped ||
        status == AndroidServiceStatus.suspended;
    final epoch = ref.watch(
      configStateProvider.select((state) => state.fact.runtimeEpoch),
    );
    final ranking = ref.watch(_hostTrafficProvider);
    final cached = ranking.snapshot;
    final snapshot = epoch.isEmpty || cached?.runtimeEpoch == epoch
        ? cached
        : null;
    final search = SearchQuery(_query);
    String label(HostTrafficRow row) => switch (row.key) {
      'other:' => l.hostTrafficOther,
      'unknown:' => l.activityUnknownTarget,
      _ => row.key.substring(row.key.indexOf(':') + 1),
    };
    final rows =
        (snapshot?.rows ?? const <HostTrafficRow>[])
            .where((row) => search.matches([label(row)]))
            .toList()
          ..sort((a, b) {
            if (a.other != b.other) return a.other ? 1 : -1;
            final total = b.total.compareTo(a.total);
            return total == 0 ? a.key.compareTo(b.key) : total;
          });
    final hasOverflow = snapshot?.rows.any((row) => row.other) ?? false;
    return CommonScaffold(
      title: l.hostTrafficTitle,
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, context.contentTopPadding, 16, 8),
            child: SearchField(
              hintText: l.activitySearchTargets,
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          ListTile(
            title: Text(l.hostTrafficPeriod),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.hostTrafficScope),
                if (stopped)
                  Text(l.hostTrafficStopped)
                else if (!running || ranking.failed)
                  Text(l.hostTrafficUnavailable),
                if (hasOverflow) Text(l.hostTrafficLimited),
              ],
            ),
            trailing: running && ranking.failed
                ? TextButton(onPressed: _refresh, child: Text(l.retry))
                : null,
          ),
          Expanded(
            child: switch ((rows.isEmpty, snapshot == null, ranking.failed)) {
              (true, true, false) when running => const Center(
                child: CircularProgressIndicator(),
              ),
              (true, _, _) => Center(child: Text(l.noData)),
              _ => ListView.builder(
                padding: EdgeInsets.only(
                  bottom: 16 + BottomInsetScope.of(context),
                ),
                itemCount: rows.length,
                itemBuilder: (context, index) {
                  final row = rows[index];
                  return ListTile(
                    key: ValueKey(row.key),
                    title: Text(label(row)),
                    subtitle: Text(
                      '${l.upload}: ${row.upload.traffic.show} • '
                      '${l.download}: ${row.download.traffic.show}',
                    ),
                    trailing: Text('${l.total}: ${row.total.traffic.show}'),
                    onTap: row.other
                        ? null
                        : () => BaseNavigator.push(
                            context,
                            ApplicationConnectionsView.forHost(
                              hostKey: row.key,
                              runtimeEpoch: snapshot!.runtimeEpoch,
                            ),
                          ),
                  );
                },
              ),
            },
          ),
        ],
      ),
    );
  }
}
