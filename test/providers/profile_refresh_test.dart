import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/models/profile_refresh.dart';
import 'package:fl_clash/plugins/service.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_profiles.dart';

class _Native extends Mock implements Service {}

class _Core extends Mock implements CoreHandlerInterface {}

class _Profiles extends ProfilesAction {
  _Profiles(this.client);
  final Request client;
  DateTime now = DateTime(2026, 10, 18);
  Duration elapsed = Duration.zero;
  @override
  Request get requestClient => client;
  @override
  DateTime get refreshNow => now;
  @override
  Duration get refreshElapsed => elapsed;
  void advance(Duration value) {
    elapsed += value;
    now = now.add(value);
  }
}

Future<void> _until(FutureOr<bool> Function() condition) async {
  for (var i = 0; i < 1000; i++) {
    if (await condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  throw StateError('Fixture did not reach its checkpoint');
}

final class _DefaultIO extends IOOverrides {}

class _CleanupDirectory implements Directory {
  _CleanupDirectory(
    this.inner,
    this.entered,
    this.release, {
    this.staged = false,
  });
  final Directory inner;
  final Completer<void> entered, release;
  final bool staged;
  @override
  String get path => inner.path;
  @override
  Future<bool> exists() => inner.exists();
  @override
  Future<Directory> create({bool recursive = false}) =>
      inner.create(recursive: recursive);
  @override
  Future<Directory> createTemp([String? prefix]) async => _CleanupDirectory(
    await inner.createTemp(prefix),
    entered,
    release,
    staged: prefix == 'request-',
  );
  @override
  Future<FileSystemEntity> delete({bool recursive = false}) async {
    if (staged) {
      if (!entered.isCompleted) entered.complete();
      await release.future;
    }
    return inner.delete(recursive: recursive);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late Database store;
  late HttpServer server;
  late Request client;
  late ProviderContainer container;
  late _Profiles action;
  late _Core core;
  final received = <String>[];
  final held = <String, Completer<void>>{};
  final invalid = <String>{};
  final oversized = <String>{};

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('profile-refresh-');
    AppPath.supportDirectory = () async => root;
    AppPath.temporaryDirectory = () async => root;
    AppPath.cacheDirectory = () async => root;

    await AppLocalizations.load(const Locale('en'));
    globalState.packageInfo = PackageInfo(
      appName: 'fixture',
      packageName: 'fixture',
      version: '1',
      buildNumber: '1',
    );
  });
  tearDownAll(() => root.delete(recursive: true));
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    received.clear();
    held.clear();
    invalid.clear();
    oversized.clear();
    store = Database(NativeDatabase.memory());
    database = store;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final name = request.uri.path;
      received.add(name);
      final gate = held[name];
      if (gate != null) await gate.future;
      try {
        if (oversized.contains(name)) {
          request.response.contentLength = 17 * 1024 * 1024;
          request.response.write('x');
          await request.response.flush();
          return;
        }
        request.response.headers.set(
          'subscription-userinfo',
          'upload=bad; upload=10; download=-1; download=20; expire=999999999999999999999; broken;',
        );
        request.response.headers.set(
          'content-disposition',
          'attachment; filename="server-rename.yaml"',
        );
        request.response.write(
          invalid.contains(name)
              ? 'invalid'
              : 'mode: rule\nrules: ["MATCH,DIRECT"]\n',
        );
        await request.response.close();
      } catch (_) {}
    });
    core = _Core();
    when(() => core.validateConfig(any())).thenAnswer(
      (call) async =>
          await File(call.positionalArguments.first as String).readAsString() ==
              'invalid'
          ? 'bad body'
          : '',
    );
    client = Request.scoped(native: _Native(), isAndroid: false);
    container = ProviderContainer(
      overrides: [
        coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
        profilesActionProvider.overrideWith(() => _Profiles(client)),
        profilesProvider.overrideWith(() => TestProfiles()),
        currentProfileIdProvider.overrideWithBuild((_, _) => null),
      ],
    );
    globalState.container = container;
    container.listen(configProvider, (_, _) {});
    client.attach(container);
    await client.ready();
    action = container.read(profilesActionProvider.notifier) as _Profiles;
  });
  tearDown(() async {
    container.dispose();
    await client.detach();
    for (final gate in held.values) {
      if (!gate.isCompleted) gate.complete();
    }
    await server.close(force: true);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    await store.close();
    await for (final entry in root.list()) {
      await entry.delete(recursive: true);
    }
  });

  Profile profile(
    int id,
    String name, {
    bool automatic = false,
    Duration period = const Duration(days: 1),
  }) => Profile(
    id: id,
    label: 'local-$id',
    url: 'http://127.0.0.1:${server.port}/$name',
    requestMode: RequestMode.direct,
    autoUpdate: automatic,
    autoUpdateDuration: period,
  );

  Future<void> put(List<Profile> profiles) async {
    await store.profilesDao.putAll(profiles.map((p) => p.toCompanion()));
  }

  test(
    'existing refresh never recreates a deleted row; import conflicts fail closed',
    () async {
      final deleted = profile(1, 'gone');
      final result = await action.updateProfile(deleted);
      expect(result.materialSaved, false);
      expect(received, isEmpty);
      await put([deleted]);
      expect(
        (await action.updateProfile(deleted, importing: true)).materialSaved,
        false,
      );
      expect(received, isEmpty);
      final fresh = profile(2, 'new');
      expect(
        (await action.updateProfile(fresh, importing: true)).materialSaved,
        true,
      );
      expect(
        (await store.profilesDao.query().get()).getProfile(2)?.label,
        'local-2',
      );
    },
  );

  for (final change in ['delete', 'disable', 'period', 'url', 'file']) {
    test(
      'queued automatic task rechecks $change before HTTP registration',
      () async {
        final a = profile(1, 'hold');
        final b = profile(2, 'queued', automatic: true);
        final gate = held['/hold'] = Completer<void>();
        await put([a, b]);
        final first = action.updateProfile(a);
        await _until(() => received.contains('/hold'));
        await action.autoUpdateProfiles();
        if (change == 'delete') {
          await (store.delete(
            store.profiles,
          )..where((row) => row.id.equals(2))).go();
        } else {
          final next = switch (change) {
            'disable' => b.copyWith(autoUpdate: false),
            'period' => b.copyWith(
              autoUpdateDuration: const Duration(days: 2),
              lastUpdateDate: action.now,
            ),
            'url' => b.copyWith(url: 'http://127.0.0.1:${server.port}/new'),
            _ => b.copyWith(url: ''),
          };
          await store.profiles.put(next.toCompanion());
        }
        gate.complete();
        await first;
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(received, isNot(contains('/queued')));
        if (change == 'delete') {
          expect((await store.profilesDao.query().get()).getProfile(2), isNull);
        }
      },
    );
  }

  for (final promotion in [false, true]) {
    test(
      'manual ${promotion ? 'promotion' : 'entry'} runs ahead of queued automatic work',
      () async {
        final a = profile(1, 'hold');
        final b = profile(2, 'automatic', automatic: true);
        final c = profile(3, 'manual', automatic: promotion);
        final release = held['/hold'] = Completer<void>();
        await put([a, b, c]);
        final first = action.updateProfile(a);
        await _until(() => received.contains('/hold'));
        await action.autoUpdateProfiles();
        final manual = action.updateProfile(c);
        await pumpEventQueue();
        release.complete();
        await first;
        expect((await manual).materialSaved, true);
        await _until(() => received.length == 3);
        expect(received, ['/hold', '/manual', '/automatic']);
      },
    );
  }

  test(
    'a closed download cannot absorb a new manual refresh during file cleanup',
    () async {
      final a = profile(1, 'retry');
      await put([a]);
      oversized.add('/retry');
      final entered = Completer<void>(), release = Completer<void>();
      final originalIO = IOOverrides.current ?? _DefaultIO();
      await IOOverrides.runZoned(
        () async {
          final first = action.updateProfile(a);
          final rejected = expectLater(
            first,
            throwsA(
              isA<RequestUnavailable>().having(
                (e) => e.code,
                'code',
                'profile_download_too_large',
              ),
            ),
          );
          await entered.future.timeout(const Duration(seconds: 3));
          oversized.clear();
          final second = action.updateProfile(a);
          await pumpEventQueue();
          expect(received, ['/retry']);
          release.complete();
          await rejected;
          expect((await second).materialSaved, true);
          expect(received, ['/retry', '/retry']);
        },
        createDirectory: (path) => _CleanupDirectory(
          originalIO.createDirectory(path),
          entered,
          release,
        ),
      );
    },
  );

  test(
    'duplicate manual joins running manual and automatic wake cannot cancel it',
    () async {
      final a = profile(1, 'hold', automatic: true);
      held['/hold'] = Completer<void>();
      await put([a]);
      final first = action.updateProfile(a);
      await _until(() => received.length == 1);
      final second = action.updateProfile(a);
      await action.autoUpdateProfiles();
      held['/hold']!.complete();
      expect((await first).materialSaved, true);
      expect((await second).materialSaved, true);
      expect(received, ['/hold']);
    },
  );

  test(
    'new manual source survives auto=false and supersedes an older manual waiter',
    () async {
      final a = profile(1, 'old');
      held['/old'] = Completer<void>();
      await put([a]);
      final first = action.updateProfile(a);
      await _until(() => received.contains('/old'));
      final next = a.copyWith(url: 'http://127.0.0.1:${server.port}/new');
      await action.putProfile(next);
      final second = action.updateProfile(next);
      held['/old']!.complete();
      expect((await first).application, ProfileApplicationOutcome.superseded);
      expect((await second).materialSaved, true);
      expect(received, ['/old', '/new']);
      expect((await store.profilesDao.query().get()).single.url, next.url);
    },
  );

  test(
    'stream validation failure preserves previous material; optional statistics are tolerant',
    () async {
      final a = profile(1, 'body');
      await put([a]);
      final target = File(await appPath.getProfilePath('1'));
      await target.parent.create(recursive: true);
      await target.writeAsString('old body');
      invalid.add('/body');
      await expectLater(
        action.updateProfile(a),
        throwsA(
          isA<RequestUnavailable>().having(
            (e) => e.code,
            'code',
            'profile_invalid',
          ),
        ),
      );
      expect(await target.readAsString(), 'old body');
      expect(
        (await store.profilesDao.query().get()).single.lastUpdateDate,
        isNull,
      );
      invalid.clear();
      oversized.clear();
      expect((await action.updateProfile(a)).materialSaved, true);
      final saved = (await store.profilesDao.query().get()).single;
      expect(saved.label, 'local-1');
      expect(
        saved.subscriptionInfo,
        const SubscriptionInfo(upload: 10, download: 20),
      );
      expect(saved.lastUpdateDate, action.now);
    },
  );

  test(
    'download and validation errors do not expose synthetic URL credentials or tokens',
    () async {
      final a = profile(1, 'secret').copyWith(
        url:
            'http://synthetic-user:synthetic-password@127.0.0.1:${server.port}/secret?token=synthetic-token',
      );
      await put([a]);
      invalid.add('/secret');
      try {
        await action.updateProfile(a);
        fail('The invalid fixture must fail');
      } on RequestUnavailable catch (error) {
        expect(error.toString(), isNot(contains('synthetic-password')));
        expect(error.toString(), isNot(contains('synthetic-token')));
        expect(error.code, isNot(contains('synthetic-')));
      }
    },
  );

  test(
    'minimum attempt gap and monotonic exponential retries survive repeated wakes',
    () async {
      final a = profile(
        1,
        'retry',
        automatic: true,
        period: const Duration(seconds: 1),
      );
      invalid.add('/retry');
      await put([a]);
      await action.autoUpdateProfiles();
      await _until(() => received.length == 1);
      await _until(() => root.list().isEmpty);
      for (var i = 0; i < 5; i++) {
        await action.autoUpdateProfiles();
      }
      expect(received.length, 1);
      action.advance(const Duration(minutes: 1));
      await action.autoUpdateProfiles();
      await _until(() => received.length == 2);
      await _until(() => root.list().isEmpty);
      action.advance(const Duration(minutes: 1));
      await action.autoUpdateProfiles();
      expect(received.length, 2);
      action.advance(const Duration(minutes: 1));
      await action.autoUpdateProfiles();
      await _until(() => received.length == 3);
      await _until(() => root.list().isEmpty);
      invalid.clear();
      oversized.clear();
      expect((await action.updateProfile(a)).materialSaved, true);
    },
  );

  for (final duration in [Duration.zero, const Duration(minutes: -1)]) {
    test(
      'historical $duration uses one day without rewriting the stored value',
      () async {
        final a = profile(1, 'old-period', automatic: true, period: duration)
            .copyWith(
              lastUpdateDate: action.now.subtract(const Duration(hours: 23)),
            );
        await put([a]);
        await action.autoUpdateProfiles();
        expect(received, isEmpty);
        expect(
          (await store.profilesDao.query().get()).single.autoUpdateDuration,
          duration,
        );
        action.advance(const Duration(hours: 1));
        await action.autoUpdateProfiles();
        await _until(() => received.isNotEmpty);
      },
    );
  }

  test(
    'automatic retry reaches the twenty-minute cap and ignores wall-clock jumps',
    () async {
      final a = profile(
        1,
        'backoff',
        automatic: true,
        period: const Duration(seconds: 1),
      );
      invalid.add('/backoff');
      await put([a]);
      await action.autoUpdateProfiles();
      await _until(() => received.length == 1);
      await _until(() => root.list().isEmpty);
      var attempts = 1;
      for (final gap in [1, 2, 4, 8, 16, 20, 20]) {
        action.now = action.now.add(const Duration(days: 365));
        await action.autoUpdateProfiles();
        expect(received.length, attempts);
        action.advance(Duration(minutes: gap) - const Duration(seconds: 1));
        await action.autoUpdateProfiles();
        expect(received.length, attempts);
        action.advance(const Duration(seconds: 1));
        await action.autoUpdateProfiles();
        attempts++;
        await _until(() => received.length == attempts);
        await _until(() => root.list().isEmpty);
      }
      invalid.clear();
      oversized.clear();
      expect((await action.updateProfile(a)).materialSaved, true);
    },
  );

  test(
    'very long positive periods and future wall dates do not overflow scheduling',
    () async {
      final a = profile(
        1,
        'long',
        automatic: true,
        period: const Duration(milliseconds: 9223372036854775),
      ).copyWith(lastUpdateDate: action.now.add(const Duration(days: 1)));
      await put([a]);
      await action.autoUpdateProfiles();
      expect(received, isEmpty);
      expect(
        (await store.profilesDao.query().get()).single.autoUpdateDuration,
        a.autoUpdateDuration,
      );
      final b = profile(2, 'manual');
      await put([a, b]);
      expect((await action.updateProfile(b)).materialSaved, true);
      expect(received, ['/manual']);
    },
  );

  test(
    'internal material demand progresses while ordinary work is gated by Setup',
    () async {
      final a = profile(1, 'ordinary');
      final b = profile(2, 'urgent');
      await put([a, b]);
      action.setupExecutionChanged(true);
      final ordinary = action.updateProfile(a);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(received, isEmpty);
      expect((await action.ensureFile(b, isCurrent: () async => true))?.id, 2);
      expect(received, ['/urgent']);
      action.setupExecutionChanged(false);
      expect((await ordinary).materialSaved, true);
      expect(received, ['/urgent', '/ordinary']);
    },
  );

  test(
    'automatic watching starts after attachment when the action was created during bootstrap',
    () async {
      final lateClient = Request.scoped(native: _Native(), isAndroid: false);
      final lateContainer = ProviderContainer(
        overrides: [
          coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
          profilesActionProvider.overrideWith(() => _Profiles(lateClient)),
          profilesProvider.overrideWith(() => TestProfiles()),
          currentProfileIdProvider.overrideWithBuild((_, _) => null),
        ],
      );
      try {
        final lateAction = lateContainer.read(profilesActionProvider.notifier);
        final a = profile(91, 'late-attach', automatic: true);
        await store.profilesDao.putAll([a.toCompanion()]);
        await lateAction.autoUpdateProfiles();
        expect(received, isEmpty);
        lateClient.attach(lateContainer);
        await lateClient.ready();
        await lateAction.autoUpdateProfiles();
        await _until(
          () =>
              lateContainer
                  .read(profilesProvider)
                  .getProfile(91)
                  ?.lastUpdateDate !=
              null,
        );
        expect(received, ['/late-attach']);
      } finally {
        lateContainer.dispose();
        await lateClient.detach();
      }
    },
  );
}
