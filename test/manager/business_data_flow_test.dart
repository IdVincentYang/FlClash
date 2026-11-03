import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:drift/native.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/core.dart';
import 'package:fl_clash/database/database.dart' as db;
import 'package:fl_clash/manager/core_manager.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/plugins/service.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/connection/connections.dart';
import 'package:fl_clash/views/dashboard/widgets/traffic_usage.dart';
import 'package:fl_clash/views/logs.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_app.dart';

class _NativeForwarder with ServiceListener {
  @override
  void onServiceEvent(CoreEvent event) => coreEventManager.sendEvent(event);
}

class _LocalExport extends FilePickerPlatform {
  _LocalExport(this.destination);

  final File destination;
  Uint8List? received;
  bool fail = false;

  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    String? dialogTitle,
    String? initialDirectory,
    Function(FilePickerStatus)? onFileSaving,
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    received = bytes;
    if (fail) throw StateError('synthetic export failure');
    await destination.writeAsBytes(bytes);
    return destination.uri;
  }
}

void main() {
  final input = Platform.environment['FLCLASH_BUSINESS_DATA_JSON'];
  testWidgets(
    'real Core records pass Service and CoreManager to UI and explicit export',
    (tester) async {
      final data = json.decode(File(input!).readAsStringSync()) as Map;
      final cases = (data['cases'] as List).cast<Map>();
      final root = Directory.systemTemp.createTempSync('business-consumer-');
      final previousSupport = AppPath.supportDirectory;
      final previousTemporary = AppPath.temporaryDirectory;
      final previousCache = AppPath.cacheDirectory;
      final previousDownload = AppPath.downloadDirectory;
      AppPath.supportDirectory = () async => root;
      AppPath.temporaryDirectory = () async => root;
      AppPath.cacheDirectory = () async => root;
      AppPath.downloadDirectory = () async => root;
      SharedPreferences.setMockInitialValues({});
      globalState.packageInfo = PackageInfo(
        appName: 'FlClash',
        packageName: 'test.business.review',
        version: '0',
        buildNumber: '0',
      );
      final previousDatabase = db.database;
      final reviewDatabase = db.Database(
        NativeDatabase(File('${root.path}/app.sqlite')),
      );
      db.database = reviewDatabase;
      await tester.runAsync(
        () => reviewDatabase.customSelect('SELECT 1').get(),
      );
      final pickerBefore = FilePickerPlatform.instance;
      final export = _LocalExport(File('${root.path}/explicit-export.log'));
      FilePickerPlatform.instance = export;
      final native = Service();
      final core = CoreLib.scoped(native);
      final container = ProviderContainer(
        overrides: [
          coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
          sharedStateProvider.overrideWithValue(
            const SharedState(
              stopTip: '',
              startTip: '',
              localNetworkTip: '',
              currentProfileName: 'synthetic',
              stopText: 'Stop',
              onlyStatisticsProxy: false,
            ),
          ),
        ],
      );
      globalState.container = container;
      const channel = MethodChannel('$packageName/service');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      var current = cases.first;
      final methods = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method != 'invokeMethod') {
          return call.method == 'shutdown' ? true : '';
        }
        final request = json.decode(call.arguments as String) as Map;
        final method = request['method'] as String;
        methods.add(method);
        final reply = switch (method) {
          'getConnections' => Map<String, Object?>.from(
            current['connections'] as Map,
          ),
          'getTotalTraffic' => Map<String, Object?>.from(
            current['traffic'] as Map,
          ),
          _ => <String, Object?>{'result': null},
        };
        reply['id'] = request['id'];
        return Uint8List.fromList(utf8.encode(json.encode(reply)));
      });
      final forwarder = _NativeForwarder();
      native.addListener(forwarder);
      final observations = <Map<String, Object?>>[];
      try {
        await tester.runAsync(core.start);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const TestApp(
              locale: Locale('en'),
              child: CoreManager(child: SizedBox()),
            ),
          ),
        );
        for (final scenario in cases) {
          current = scenario;
          final rawConnections = (scenario['connections'] as Map)['result'];
          final records = await tester.runAsync(core.getConnections);
          expect(
            records!.length,
            (rawConnections['connections'] as List).length,
          );
          expect(records, isNotEmpty);
          final traffic = await tester.runAsync(
            () => core.getTotalTraffic(false),
          );
          final rawTraffic = (scenario['traffic'] as Map)['result'] as Map;
          expect(traffic!.up, rawTraffic['up']);
          expect(traffic.down, rawTraffic['down']);
          for (final frame in (scenario['events'] as List).cast<Map>()) {
            await messenger.handlePlatformMessage(
              '$packageName/service',
              const StandardMethodCodec().encodeMethodCall(
                MethodCall('event', json.encode(frame)),
              ),
              null,
            );
          }
          await tester.pump();
          observations.add({
            'name': scenario['name'],
            'rpcConnections': records.length,
            'retainedRequests': container.read(requestsProvider).list.length,
            'retainedLogs': container.read(logsProvider).list.length,
            'up': traffic.up,
            'down': traffic.down,
          });
        }
        final requests = container.read(requestsProvider).list;
        final logs = container.read(logsProvider).list;
        expect(requests, isNotEmpty);
        expect(logs, isNotEmpty);
        final serialized = json.encode({
          'requests': requests.map((r) => r.toJson()).toList(),
          'logs': logs.map((l) => l.toJson()).toList(),
        });
        for (final scenario in cases) {
          for (final prefix in [
            'request-body-',
            'response-body-',
            'business-auth-',
            'business-cookie=',
          ]) {
            expect(serialized, isNot(contains('$prefix${scenario['name']}')));
          }
        }
        final active = await tester.runAsync(core.getConnections);
        container.read(totalTrafficProvider.notifier).value =
            await tester.runAsync(() => core.getTotalTraffic(false)) ??
            const Traffic();
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: TestApp(
              locale: const Locale('en'),
              child: ConnectionsView(connectionsReader: () async => active!),
            ),
          ),
        );
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('Live connections'), findsOneWidget);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const TestApp(
              locale: Locale('en'),
              child: Scaffold(body: TrafficUsage()),
            ),
          ),
        );
        await tester.pump();
        expect(find.text('Traffic usage'), findsOneWidget);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const TestApp(locale: Locale('en'), child: LogsView()),
          ),
        );
        await tester.pump();
        expect(find.text('Logs'), findsOneWidget);
        final saved = await tester.runAsync(
          container.read(logsProvider.notifier).exportLogs,
        );
        expect(saved, isTrue);
        expect(export.received, isNotEmpty);
        expect(export.destination.readAsBytesSync(), export.received);
        expect(
          await tester.runAsync(
            () => preferences.saveConfig(container.read(configProvider)),
          ),
          isTrue,
        );
        final preferencesMap = await tester.runAsync(preferences.getConfigMap);
        expect(json.encode(preferencesMap), isNot(contains('request-body-')));
        expect(json.encode(preferencesMap), isNot(contains('response-body-')));
        final tables = <String, Object?>{};
        final archive = File('${root.path}/backup.zip');
        await tester.runAsync(() async {
          final schema = await reviewDatabase
              .customSelect(
                "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
              )
              .get();
          for (final table in schema) {
            final name = table.read<String>('name');
            final rows = await reviewDatabase
                .customSelect('SELECT * FROM "$name"')
                .get();
            tables[name] = rows.map((row) => row.data).toList();
          }
          final snapshot = '${root.path}/backup.sqlite';
          await reviewDatabase.customStatement('VACUUM INTO ?', [snapshot]);
          await writeBackupArchive(
            archivePath: archive.path,
            configMap: preferencesMap!,
            databaseSnapshotPath: snapshot,
            homeDirPath: root.path,
            entries: BackupEntries.of(
              profileIds: [],
              scriptIds: [],
              providers: [],
            ),
          );
        });
        expect(json.encode(tables), isNot(contains('request-body-')));
        expect(json.encode(tables), isNot(contains('business-auth-')));
        final archived = ZipDecoder().decodeBytes(archive.readAsBytesSync());
        expect(archived.files.map((entry) => entry.name), [
          configJsonName,
          backupDatabaseName,
        ]);
        export.fail = true;
        await tester.runAsync(() async {
          await expectLater(
            container.read(logsProvider.notifier).exportLogs(),
            throwsStateError,
          );
        });
        final leftover = root
            .listSync()
            .whereType<File>()
            .where((f) => f.uri.pathSegments.last.startsWith('temp'))
            .toList();
        final leftoverHasMetadata = leftover.any(
          (file) => file.readAsStringSync().contains('127.0.0.1'),
        );
        final output = File('${root.path}/consumer.json');
        output.writeAsStringSync(
          json.encode({
            'input': input,
            'observations': observations,
            'methods': methods,
            'logs': logs.length,
            'requests': requests.length,
            'exportBytes': export.received!.length,
            'exportContainsMetadata': utf8
                .decode(export.received!)
                .contains('127.0.0.1'),
            'tables': tables,
            'backupEntries': archived.files.map((entry) => entry.name).toList(),
            'failedExportTemporaryFiles': leftover.length,
            'failedExportTemporaryFileContainsMetadata': leftoverHasMetadata,
            'scope':
                'host MethodChannel replacement; native forwarding supplied by test; no JNI/OS evidence',
          }),
        );
        final evidence =
            Platform.environment['FLCLASH_BUSINESS_CONSUMER_EVIDENCE'];
        if (evidence != null) {
          output.copySync('$evidence/consumer.json');
          export.destination.copySync('$evidence/explicit-export.log');
          archive.copySync('$evidence/backup.zip');
          for (var index = 0; index < leftover.length; index++) {
            leftover[index].copySync('$evidence/failed-export-$index.log');
          }
        }
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 4));
        native.removeListener(forwarder);
        await tester.runAsync(core.close);
        messenger.setMockMethodCallHandler(channel, null);
        container.dispose();
        await tester.runAsync(reviewDatabase.close);
        db.database = previousDatabase;
        FilePickerPlatform.instance = pickerBefore;
        AppPath.supportDirectory = previousSupport;
        AppPath.temporaryDirectory = previousTemporary;
        AppPath.cacheDirectory = previousCache;
        AppPath.downloadDirectory = previousDownload;
        root.deleteSync(recursive: true);
      }
    },
    skip: input == null,
    timeout: const Timeout(Duration(seconds: 45)),
  );
}
