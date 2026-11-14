import 'package:fl_clash/common/application_routing.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'VPN capture edits preserve the active allow/deny policy and other apps',
    () {
      const all = AccessControlProps(rejectList: ['old']);
      final excluded = setApplicationCapture(all, ['a'], false);
      expect(excluded.rejectList, ['a']);
      expect(applicationCaptured(excluded, 'a'), false);
      expect(applicationCaptured(excluded, 'b'), true);
      expect(setApplicationCapture(excluded, ['a'], true).rejectList, isEmpty);
      const allow = AccessControlProps(
        enable: true,
        mode: AccessControlMode.acceptSelected,
        acceptList: ['b'],
      );
      final added = setApplicationCapture(allow, ['a'], true);
      expect(added.acceptList, ['a', 'b']);
      expect(setApplicationCapture(added, ['a'], false).acceptList, ['b']);
      expect(
        applicationCaptureFingerprint(added),
        applicationCaptureFingerprint(
          added.copyWith(acceptList: ['b', 'a', 'a']),
        ),
      );
      expect(
        applicationCaptureFingerprint(all),
        applicationCaptureFingerprint(const AccessControlProps()),
      );
    },
  );

  test(
    'bindings remember subscriptions without guessing names across subscriptions',
    () {
      const a = ApplicationRouteTarget(
        name: 'Node A',
        kind: ApplicationTargetKind.node,
      );
      const b = ApplicationRouteTarget(
        name: 'Node B',
        kind: ApplicationTargetKind.node,
      );
      const rule = ApplicationRouteRule(
        packageName: 'app',
        enabled: true,
        useSharedTarget: false,
        targets: {1: a, 2: b},
      );
      const settings = ApplicationRoutingSettings(rules: {'app': rule});
      expect(applicationTargetFor(settings, rule, 1), a);
      expect(applicationTargetFor(settings, rule, 2), b);
      expect(applicationTargetFor(settings, rule, 3), isNull);
      const global = ApplicationRouteTarget(
        name: 'Mine',
        kind: ApplicationTargetKind.globalGroup,
        groupId: 8,
      );
      expect(
        applicationTargetFor(settings, rule.copyWith(targets: {1: global}), 3),
        global,
      );
      expect(
        applicationTargetFor(
          settings,
          rule.copyWith(targets: {1: global, 2: global.copyWith(groupId: 9)}),
          3,
        ),
        isNull,
      );
    },
  );

  test(
    'disabled rules are absent and explicit reject stays a valid action',
    () {
      const settings = ApplicationRoutingSettings(
        revision: 2,
        rules: {
          'b': ApplicationRouteRule(
            packageName: 'b',
            enabled: true,
            action: ApplicationRouteAction.reject,
          ),
          'a': ApplicationRouteRule(
            packageName: 'a',
            enabled: true,
            action: ApplicationRouteAction.direct,
          ),
          'off': ApplicationRouteRule(packageName: 'off'),
        },
      );
      final wire = compileApplicationRouting(settings, 7);
      expect(wire['rules'], [
        {'package': 'a', 'target': 'DIRECT'},
        {'package': 'b', 'target': 'REJECT'},
      ]);
      expect(
        wire['revision'],
        'd887c05e010a90e8d43773632359c9bc1b29e24a0cded86d265ffd66c31ed219',
      );
    },
  );

  test(
    'empty REJECT placeholder never counts as a usable custom group member',
    () {
      const definition = LocalProxyGroup(
        id: 8,
        name: 'Mine',
        global: true,
        nodes: ['removed'],
      );
      const target = ApplicationRouteTarget(
        name: 'old name',
        kind: ApplicationTargetKind.globalGroup,
        groupId: 8,
      );
      final state = resolveApplicationTarget(
        target: target,
        profile: const Profile(
          id: 7,
          autoUpdateDuration: Duration(hours: 1),
          localGroups: [definition],
        ),
        groups: [
          const Group(
            name: 'Mine',
            type: GroupType.Fallback,
            all: [Proxy(name: 'REJECT', type: 'Reject')],
          ),
        ],
        definitions: [definition],
        ready: true,
      );
      expect(state.target?.name, 'Mine');
      expect(state.issue, ApplicationTargetIssue.empty);
      expect(state.members, 0);
    },
  );
}
