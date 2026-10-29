import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:mobile_scanner/src/method_channel/mobile_scanner_method_channel.dart';

const _options = StartOptions(
  cameraDirection: CameraFacing.back,
  cameraLensType: CameraLensType.any,
  cameraResolution: null,
  detectionSpeed: DetectionSpeed.noDuplicates,
  detectionTimeoutMs: 250,
  formats: [BarcodeFormat.qrCode],
  returnImage: false,
  torchEnabled: false,
  invertImage: false,
  autoZoom: false,
  initialZoom: null,
);

const _configuration = {
  'textureId': 41,
  'size': {'width': 320.0, 'height': 240.0},
  'cameraDirection': 1,
  'handlesCropAndRotation': true,
  'naturalDeviceOrientation': 'PORTRAIT_UP',
  'sensorOrientation': 90,
};

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late MethodChannelMobileScanner channel;
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    channel = MethodChannelMobileScanner();
  });
  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel.methodChannel,
      null,
    );
    debugDefaultTargetPlatformOverride = null;
  });

  test('late permission grant cannot start a revoked camera', () async {
    final request = Completer<bool>();
    final requested = Completer<void>();
    var starts = 0;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel.methodChannel,
      (call) async {
        switch (call.method) {
          case 'state':
            return 2;
          case 'request':
            requested.complete();
            return request.future;
          case 'start':
            starts++;
            return _configuration;
          default:
            return null;
        }
      },
    );
    final start = channel.start(_options);
    final rejected = expectLater(start, throwsA(isA<MobileScannerException>()));
    await requested.future;
    await channel.stop();
    request.complete(true);
    await rejected;
    expect(starts, 0);
  });

  test(
    'non-Android channel keeps upstream pending-permission behavior',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final request = Completer<bool>();
      final requested = Completer<void>();
      var starts = 0;
      var stops = 0;
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel.methodChannel,
        (call) async {
          switch (call.method) {
            case 'state':
              return 2;
            case 'request':
              requested.complete();
              return request.future;
            case 'start':
              starts++;
              return _configuration;
            case 'stop':
              stops++;
              return null;
            default:
              return null;
          }
        },
      );
      final start = channel.start(_options);
      await requested.future;
      await channel.stop();
      request.complete(true);
      await start;
      expect(starts, 1);
      expect(stops, 0);
      await channel.stop();
    },
  );

  test(
    'late native start cannot retain a stale texture or block the next start',
    () async {
      final native = Completer<Map<String, Object?>>();
      final started = Completer<void>();
      var starts = 0;
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel.methodChannel,
        (call) async {
          switch (call.method) {
            case 'state':
              return 1;
            case 'start':
              starts++;
              if (starts == 1) {
                started.complete();
                return native.future;
              }
              return _configuration;
            default:
              return null;
          }
        },
      );
      final start = channel.start(_options);
      final rejected = expectLater(
        start,
        throwsA(isA<MobileScannerException>()),
      );
      await started.future;
      await channel.stop();
      native.complete(_configuration);
      await rejected;
      final current = await channel.start(_options);
      expect(current.size.width, 320);
      expect(starts, 2);
      await channel.stop();
    },
  );
}
