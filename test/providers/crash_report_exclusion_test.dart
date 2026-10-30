import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:drift/native.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/dav_client.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';

class _CapturePicker extends FilePickerPlatform {
  Uint8List? captured;
  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    String? dialogTitle,
    String? initialDirectory,
    void Function(FilePickerStatus)? onFileSaving,
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    captured = bytes;
    return Uri.file('/synthetic/export.log');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const secret = 'SYNTHETIC_REPORT_RAW_ONLY';
  late Directory root;
  late Directory home;
  late Directory reports;
  late Database db;
  late ProviderContainer container;

  setUpAll(() async {
    root = Directory.systemTemp.createTempSync('report-exclusion-');
    home = Directory('${root.path}/files')..createSync();
    reports = Directory('${root.path}/no_backup/crash_reports')
      ..createSync(recursive: true);
    File('${reports.path}/raw.bin').writeAsStringSync(secret);
    AppPath.supportDirectory = () async => home;
    AppPath.temporaryDirectory = () async =>
        Directory('${root.path}/cache')..createSync();
    AppPath.cacheDirectory = AppPath.temporaryDirectory;
    AppPath.downloadDirectory = () async => home;
    SharedPreferences.setMockInitialValues({'version': 1});
    globalState.packageInfo = PackageInfo(
      appName: 'synthetic',
      packageName: 'synthetic.report',
      version: '0.0.0',
      buildNumber: '1',
    );
    await AppLocalizations.load(const Locale('en'));
  });

  setUp(() {
    db = Database(NativeDatabase.memory());
    database = db;
    container = ProviderContainer();
    container.listen(configProvider, (_, _) {});
    request.attach(container);
  });

  tearDown(() async {
    await request.detach();
    container.dispose();
    await db.close();
  });
  tearDownAll(() => root.deleteSync(recursive: true));

  void checkArchive(List<int> bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    expect(
      archive.files.map((f) => f.name),
      containsAll(['config.json', 'database.sqlite']),
    );
    for (final file in archive.files) {
      expect(file.name, isNot(contains('crash_reports')));
      expect(
        utf8.decode(file.content, allowMalformed: true),
        isNot(contains(secret)),
      );
    }
  }

  test(
    'ordinary Logs export passes only its logs to the picker boundary',
    () async {
      final previous = FilePickerPlatform.instance;
      final files = _CapturePicker();
      FilePickerPlatform.instance = files;
      try {
        final logs = container.read(logsProvider.notifier);
        logs.add(Log.app('synthetic ordinary log'));
        expect(await logs.exportLogs(), true);
        final content = utf8.decode(files.captured!);
        expect(content, contains('synthetic ordinary log'));
        expect(content, isNot(contains(secret)));
        expect(File('${reports.path}/raw.bin').readAsStringSync(), secret);
      } finally {
        FilePickerPlatform.instance = previous;
      }
    },
  );

  test(
    'production BackupAction ZIP never includes private report material',
    () async {
      List<int>? captured;
      expect(
        await container.read(backupActionProvider.notifier).backup((
          path,
        ) async {
          captured = await File(path).readAsBytes();
          return true;
        }),
        true,
      );
      checkArchive(captured!);
      expect(File('${reports.path}/raw.bin').readAsStringSync(), secret);
    },
  );

  test(
    'production backup and DAVClient upload only the ordinary archive to localhost',
    () async {
      final previous = HttpOverrides.current;
      HttpOverrides.global = null;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final delivered = Completer<List<int>>();
      final serving = server.listen((incoming) async {
        final body = <int>[];
        await for (final chunk in incoming) {
          body.addAll(chunk);
        }
        incoming.response.statusCode = HttpStatus.created;
        await incoming.response.close();
        if (incoming.method == 'PUT') delivered.complete(body);
      });
      final props = DAVProps(
        uri: 'http://127.0.0.1:${server.port}',
        user: '',
        requestMode: RequestMode.direct,
      );
      container.read(davSettingProvider.notifier).value = props;
      final client = DAVClient(props);
      try {
        expect(
          await client.operation(
            'backup',
            (_) => container.read(backupActionProvider.notifier).backup((
              path,
            ) async {
              await client.upload(path);
              return true;
            }),
          ),
          true,
        );
        checkArchive(
          await delivered.future.timeout(const Duration(seconds: 3)),
        );
        expect(File('${reports.path}/raw.bin').readAsStringSync(), secret);
      } finally {
        client.close();
        await server.close(force: true);
        await serving.cancel();
        HttpOverrides.global = previous;
      }
    },
  );

  test(
    'ordinary log encoder consumes only supplied logs and preserves the old raw-log limitation',
    () async {
      final logs = [Log.app('synthetic ordinary log')];
      expect(await encodeLogsTask(logs), isNot(contains(secret)));
      expect(await encodeLogsTask([Log.app(secret)]), contains(secret));
      expect(File('${reports.path}/raw.bin').readAsStringSync(), secret);
    },
  );
}
