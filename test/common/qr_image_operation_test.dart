import 'dart:async';

import 'package:fl_clash/common/app_localizations.dart';
import 'package:fl_clash/common/exception.dart';
import 'package:fl_clash/common/picker.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class _GalleryPlatform extends MobileScannerPlatform {
  final pick = Completer<int?>();
  final decode = Completer<BarcodeCapture?>();
  final cancelled = <int>[];
  int decodeCalls = 0;
  Completer<void>? cancelGate;

  @override
  Future<int?> pickQrImage(int clientId) => pick.future;

  @override
  Future<BarcodeCapture?> decodeQrImage(int handle) {
    expect(handle, 41);
    decodeCalls++;
    return decode.future;
  }

  @override
  Future<void> cancelQrImage(int clientId) async {
    cancelled.add(clientId);
    await cancelGate?.future;
  }
}

BarcodeCapture _capture(String value) =>
    BarcodeCapture(barcodes: [Barcode(rawValue: value)]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _GalleryPlatform platform;

  setUp(() async {
    await AppLocalizations.load(const Locale('en'));
    platform = _GalleryPlatform();
    MobileScannerPlatform.instance = platform;
  });

  test(
    'actual URL consumer accepts an installation QR without downloading',
    () async {
      final operation = QrImageOperation();
      final result = operation.read();
      platform.pick.complete(41);
      platform.decode.complete(
        _capture(
          'flclash://install-config?url=https%3A%2F%2Fexample.invalid%2Fsub%3Ftoken%3DSYNTHETIC',
        ),
      );
      expect(await result, 'https://example.invalid/sub?token=SYNTHETIC');
      expect(platform.cancelled, hasLength(1));
      expect(operation.isDecoding, isFalse);
    },
  );

  test('cancelled selection never invokes decoder for a late handle', () async {
    final operation = QrImageOperation();
    final result = operation.read();
    await operation.cancel();
    platform.pick.complete(41);
    expect(await result, isNull);
    expect(platform.decodeCalls, 0);
    expect(platform.cancelled, hasLength(1));
  });

  test('late decoded URL is discarded after local revocation', () async {
    final operation = QrImageOperation();
    final result = operation.read();
    platform.pick.complete(41);
    await Future<void>.delayed(Duration.zero);
    expect(operation.isDecoding, isTrue);
    await operation.cancel();
    platform.decode.complete(
      _capture('https://example.invalid/SYNTHETIC_SECRET'),
    );
    expect(await result, isNull);
  });

  test(
    'read failure sanitizes underlying exception and still cancels',
    () async {
      final operation = QrImageOperation();
      final result = operation.read();
      final expectation = expectLater(
        result,
        throwsA(
          isA<MessageException>().having(
            (error) => error.message,
            'safe message',
            currentAppLocalizations.qrImageReadFailed,
          ),
        ),
      );
      platform.pick.complete(41);
      await Future<void>.delayed(Duration.zero);
      platform.decode.completeError(
        PlatformException(
          code: 'qr_invalid_image',
          message: 'content://private/SYNTHETIC_SECRET',
        ),
      );
      await expectation;
      expect(platform.cancelled, hasLength(1));
    },
  );

  test('invalid QR text does not enter the error message', () async {
    final operation = QrImageOperation();
    final result = operation.read();
    final expectation = expectLater(
      result,
      throwsA(
        isA<MessageException>().having(
          (error) => error.message,
          'safe message',
          currentAppLocalizations.pleaseUploadValidQrcode,
        ),
      ),
    );
    platform.pick.complete(41);
    platform.decode.complete(_capture('SYNTHETIC_SECRET'));
    await expectation;
  });

  test('UI timeout completes without claiming native worker exit', () async {
    platform.cancelGate = Completer<void>();
    final operation = QrImageOperation();
    final result = operation.read();
    final expectation = expectLater(
      result,
      throwsA(
        isA<MessageException>().having(
          (error) => error.message,
          'safe message',
          currentAppLocalizations.qrImageTimeout,
        ),
      ),
    );
    platform.pick.complete(41);

    await expectation;
    expect(platform.decode.isCompleted, isFalse);
    expect(platform.cancelled, hasLength(1));
    platform.cancelGate?.complete();
    platform.decode.complete(_capture('https://example.invalid/late'));
    await Future<void>.delayed(Duration.zero);
  });
}
