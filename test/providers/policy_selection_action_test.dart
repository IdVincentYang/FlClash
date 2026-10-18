import 'package:drift/native.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/policy_selection.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_policy_drafts.dart';

class _AndroidSelection extends PolicySelectionAction {
  @override
  bool get supportsManaged => true;
}

class _UnsupportedSelection extends PolicySelectionAction {
  @override
  bool get supportsManaged => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database store;
  late ProviderContainer container;
  late PolicySelectionAction action;
  late String draftRaw, selectedRaw;
  setUp(() async {
    store = Database(NativeDatabase.memory());
    database = store;
    await store.profilesDao.putAll([
      draftTestProfile(
        1,
      ).copyWith(selectedMap: {'fc-managed-group-a': 'DIRECT'}).toCompanion(),
      draftTestProfile(2).toCompanion(),
    ]);
    final draft = completePolicyDraft();
    draftRaw = draft.encode();
    selectedRaw = selectPolicyDraft(draft);
    await store.profilePolicyDraftsDao.compareAndWrite(
      1,
      expectedRaw: null,
      rawContent: draftRaw,
    );
    container = ProviderContainer(
      overrides: [
        currentProfileIdProvider.overrideWithBuild((_, _) => 1),
        policySelectionActionProvider.overrideWith(_AndroidSelection.new),
      ],
    );
    container.listen(configProvider, (_, _) {});
    action = container.read(policySelectionActionProvider.notifier);
  });
  tearDown(() async {
    container.dispose();
    await store.close();
  });

  test('unsupported platform rejects selection before persistence', () async {
    final unsupported = ProviderContainer(
      overrides: [
        policySelectionActionProvider.overrideWith(_UnsupportedSelection.new),
      ],
    );
    addTearDown(unsupported.dispose);
    await expectLater(
      unsupported
          .read(policySelectionActionProvider.notifier)
          .selectConfirmed(
            1,
            expected: null,
            draftRaw: draftRaw,
            selectionRaw: selectedRaw,
          ),
      throwsA(
        isA<RequestUnavailable>().having(
          (error) => error.code,
          'code',
          'managed_policy_android_required',
        ),
      ),
    );
    expect(await store.profilePolicySelectionsDao.query().get(), isEmpty);
  });

  test(
    'explicit selection resets only this profile picks and preserves other profiles and choices',
    () async {
      const other = ProfilePolicySelection(
        profileId: 2,
        rawContent: 'opaque synthetic',
      );
      await store.profilePolicySelectionsDao.compareAndWrite(
        2,
        expected: null,
        selection: other,
      );
      expect(
        await action.selectConfirmed(
          1,
          expected: null,
          draftRaw: draftRaw,
          selectionRaw: selectedRaw,
        ),
        PolicyDraftWriteResult.saved,
      );
      final profiles = await store.profilesDao.query().get();
      expect(profiles.map((p) => p.id), [1, 2]);
      expect(profiles.first.selectedMap, isEmpty);
      expect((await action.load(2))!.sameValue(other), isTrue);
      expect(container.read(initProvider), isFalse);
      expect(container.read(currentProfileIdProvider), 1);
    },
  );

  test(
    'old absent expectation cannot replace a restored null blocker or newer draft',
    () async {
      await store.profilePolicySelectionsDao.requireSelections({1});
      expect(
        await action.selectConfirmed(
          1,
          expected: null,
          draftRaw: draftRaw,
          selectionRaw: selectedRaw,
        ),
        PolicyDraftWriteResult.conflict,
      );
      final blocked = (await action.load(1))!;
      await store.profilePolicyDraftsDao.compareAndWrite(
        1,
        expectedRaw: draftRaw,
        rawContent: 'new opaque draft',
      );
      expect(
        await action.selectConfirmed(
          1,
          expected: blocked,
          draftRaw: draftRaw,
          selectionRaw: selectedRaw,
        ),
        PolicyDraftWriteResult.conflict,
      );
      expect((await action.load(1))!.rawContent, isNull);
    },
  );

  test(
    'switching to original needs explicit confirmation and rechecks target presence',
    () async {
      await action.selectConfirmed(
        1,
        expected: null,
        draftRaw: draftRaw,
        selectionRaw: selectedRaw,
      );
      final source = await request.captureSource('profile:1');
      expect(
        await action.chooseProfile(2, confirmLeave: () async => false),
        isFalse,
      );
      expect(container.read(currentProfileIdProvider), 1);
      expect(await request.configSourceCurrent(source), isTrue);
      expect(
        await action.chooseProfile(
          2,
          confirmLeave: () async {
            await store.profilePolicySelectionsDao.requireSelections({2});
            return true;
          },
        ),
        isFalse,
      );
      expect(container.read(currentProfileIdProvider), 1);
      final blocker = (await action.load(2))!;
      await store.profilePolicySelectionsDao.compareAndWrite(
        2,
        expected: blocker,
        selection: null,
      );
      expect(
        await action.chooseProfile(2, confirmLeave: () async => true),
        isTrue,
      );
      expect(container.read(currentProfileIdProvider), 2);
      expect(await request.configSourceCurrent(source), isFalse);
      expect(await action.load(1), isNotNull);
    },
  );

  test(
    'explicit original mode deletes only the selection and preserves the draft',
    () async {
      await store.profilePolicySelectionsDao.requireSelections({1});
      expect(
        await action.selectConfirmed(
          1,
          expected: await action.load(1),
          draftRaw: null,
          selectionRaw: null,
        ),
        PolicyDraftWriteResult.saved,
      );
      expect(await action.load(1), isNull);
      expect(
        (await store.profilePolicyDraftsDao.query(1).getSingle()).rawContent,
        draftRaw,
      );
      expect(container.read(initProvider), isFalse);
    },
  );
}
