import 'package:fl_clash/common/application_routing.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('host scope priority and modes preserve whole-app policy semantics', () {
    final own = hostRuleTemplate('example.test').copyWith(
      id: 2,
      ruleTarget: 'REJECT',
      hostBinding: const HostRuleBinding(packageName: 'a'),
    );
    final generic = hostRuleTemplate('example.test').copyWith(
      id: 1,
      ruleTarget: 'DIRECT',
      hostBinding: const HostRuleBinding(),
    );
    const app = ApplicationRouteRule(
      packageName: 'a',
      enabled: true,
      action: ApplicationRouteAction.reject,
    );
    for (final hasOwn in [false, true]) {
      for (final hasGeneric in [false, true]) {
        final settings = ApplicationRoutingSettings(
          rules: const {'a': app},
          hostRules: [if (hasOwn) own, if (hasGeneric) generic],
        );
        final selected = effectiveHostPolicy(
          settings,
          'example.test',
          'a',
          7,
          Mode.rule,
        );
        expect(selected.hostRule?.id, hasOwn ? 2 : null);
        expect(selected.appRule, hasOwn ? null : app);
        final noDefault = settings.copyWith(
          rules: {'a': app.copyWith(hasDefault: false)},
        );
        expect(
          effectiveHostPolicy(
            noDefault,
            'example.test',
            'a',
            7,
            Mode.rule,
          ).hostRule?.id,
          hasOwn
              ? 2
              : hasGeneric
              ? 1
              : null,
        );
        expect(
          effectiveHostPolicy(
            noDefault,
            'example.test',
            'a',
            7,
            Mode.direct,
          ).hostRule?.id,
          hasOwn ? 2 : null,
        );
        expect(
          effectiveHostPolicy(
            settings,
            'example.test',
            'a',
            7,
            Mode.global,
          ).fallback,
          'GLOBAL',
        );
        expect(
          effectiveHostPolicy(
            settings.copyWith(rules: {'a': app.copyWith(enabled: false)}),
            'example.test',
            'a',
            7,
            Mode.rule,
          ).hostRule?.id,
          hasGeneric ? 1 : null,
        );
      }
    }
  });

  test(
    'host wire is canonical, excludes disabled app rules and never persists a duplicate library',
    () {
      final own = hostRuleTemplate('EXAMPLE.TEST.').copyWith(
        id: 2,
        ruleTarget: 'REJECT',
        hostBinding: const HostRuleBinding(packageName: 'a'),
      );
      final generic = hostRuleTemplate('example.test').copyWith(
        id: 1,
        ruleTarget: 'DIRECT',
        hostBinding: const HostRuleBinding(),
      );
      final settings = ApplicationRoutingSettings(
        revision: 2,
        rules: const {
          'a': ApplicationRouteRule(
            packageName: 'a',
            enabled: true,
            action: ApplicationRouteAction.direct,
          ),
        },
        hostRules: [own, generic],
      );
      final wire = compileApplicationRouting(settings, 7);
      expect(wire['hostRules'], [
        {
          'id': '1',
          'package': '',
          'type': 'DOMAIN',
          'content': 'example.test',
          'target': 'DIRECT',
        },
        {
          'id': '2',
          'package': 'a',
          'type': 'DOMAIN',
          'content': 'example.test',
          'target': 'REJECT',
        },
      ]);
      expect(
        wire['revision'],
        '2cfcf3ac9ffec14b8ef87980aa48477a6755d01e5a9237f78a46308060ce7f7a',
      );
      expect(settings.toJson().containsKey('hostRules'), false);
      final off = compileApplicationRouting(settings.copyWith(rules: {}), 7);
      expect((off['hostRules'] as List).length, 1);
      expect(hostRuleTemplate('2001:db8::2').content, '2001:db8::2/128');
      expect(hostRuleTemplate('192.0.2.2').content, '192.0.2.2/32');
      expect(applicationHostRule(settings, 'example.test', 'a', 7), own);
      final disabled = settings.copyWith(
        hostRules: [
          own.copyWith(
            hostBinding: own.hostBinding!.copyWith(disabledProfiles: [7]),
          ),
        ],
      );
      expect(applicationHostRule(disabled, 'example.test', 'a', 7), isNull);
      expect(
        applicationHostRule(
          disabled,
          'example.test',
          'a',
          7,
          includeDisabled: true,
        )?.id,
        own.id,
      );
      expect(
        effectiveHostPolicyForPackages(
          settings,
          'example.test',
          ['a', 'b'],
          7,
          Mode.rule,
        ).hostRule,
        generic,
      );
    },
  );

  test('equivalent IPv6 forms find one exact saved rule', () {
    final host = hostRuleTemplate(
      '2001:db8::2',
    ).copyWith(id: 1, hostBinding: const HostRuleBinding());
    expect(
      applicationHostRule(
        ApplicationRoutingSettings(hostRules: [host]),
        '2001:0db8:0:0:0:0:0:2',
        null,
        7,
      ),
      host,
    );
    expect(
      applicationHostRule(
        ApplicationRoutingSettings(hostRules: [host]),
        '2001:db8::3',
        null,
        7,
      ),
      isNull,
    );
  });

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
