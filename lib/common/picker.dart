import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:fl_clash/common/common.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class Picker {
  Future<PlatformFile?> pickerFile() async {
    return FilePicker.pickFile(initialDirectory: await appPath.downloadDirPath);
  }

  Future<Uri?> saveFile(String fileName, Uint8List bytes) async {
    final uri = await FilePicker.saveFile(
      fileName: fileName,
      initialDirectory: await appPath.downloadDirPath,
      bytes: bytes,
    );
    if (!system.isAndroid && uri != null && uri.scheme == 'file') {
      final file = File(uri.toFilePath());
      await file.safeWriteAsBytes(bytes);
    }
    return uri;
  }

  Future<Uri?> saveFileWithPath(String fileName, String localPath) async {
    final localFile = File(localPath);
    if (!await localFile.exists()) {
      await localFile.create(recursive: true);
    }
    final bytes = await localFile.readAsBytes();
    final uri = await FilePicker.saveFile(
      fileName: fileName,
      initialDirectory: await appPath.downloadDirPath,
      bytes: bytes,
    );
    await localFile.safeDelete();
    return uri;
  }

  Future<String?> pickerConfigQRCode({QrImageOperation? operation}) async {
    if (operation != null || system.isAndroid) {
      return (operation ?? QrImageOperation()).read();
    }
    final xFile = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (xFile == null) {
      return null;
    }
    // Not through a throwaway MobileScannerController: disposing one clears
    // the platform scan window of a scanner page that is still open.
    final capture = await MobileScannerPlatform.instance.analyzeImage(
      xFile.path,
      formats: const [BarcodeFormat.qrCode],
    );
    final url = profileUrlFromQrCodes(
      capture?.barcodes.map((barcode) => barcode.rawValue) ?? const [],
    );
    if (url == null) {
      throw MessageException(currentAppLocalizations.pleaseUploadValidQrcode);
    }
    return url;
  }
}

extension PlatformFileExt on PlatformFile {
  Future<Uint8List> readBytes() {
    return readAsBytes();
  }
}

final picker = Picker();

class QrImageOperation {
  QrImageOperation({this.beforeDecode});

  static int _nextClient = 0;
  final int _client = ++_nextClient;
  final Future<void> Function()? beforeDecode;
  bool _cancelled = false;
  bool isDecoding = false;

  Future<void> cancel() async {
    if (_cancelled) return;
    _cancelled = true;
    unawaited(_cancelNative(_client));
  }

  static Future<void> _cancelNative(int client) async {
    try {
      await MobileScannerPlatform.instance.cancelQrImage(client);
    } on Object {
      // The engine may already have detached; local acceptance stays revoked.
    }
  }

  Future<String?> read() async {
    try {
      if (_cancelled) return null;
      final handle = await MobileScannerPlatform.instance.pickQrImage(_client);
      if (_cancelled || handle == null) return null;
      await beforeDecode?.call().timeout(const Duration(seconds: 5));
      if (_cancelled) return null;
      isDecoding = true;
      final clock = Stopwatch()..start();
      final capture = await MobileScannerPlatform.instance
          .decodeQrImage(handle)
          .timeout(const Duration(seconds: 5));
      if (_cancelled || capture == null) return null;
      if (clock.elapsed >= const Duration(seconds: 5)) {
        throw TimeoutException('qr_timeout');
      }
      final url = profileUrlFromQrCodes(
        capture.barcodes.map((barcode) => barcode.rawValue),
      );
      if (url == null) {
        throw MessageException(currentAppLocalizations.pleaseUploadValidQrcode);
      }
      return url;
    } on MessageException {
      rethrow;
    } on Object catch (error) {
      if (_cancelled ||
          error is PlatformException && error.code == 'qr_cancelled') {
        return null;
      }
      final code = error is PlatformException ? error.code : '';
      throw MessageException(
        code == 'qr_busy'
            ? currentAppLocalizations.qrImageBusy
            : error is TimeoutException || code == 'qr_timeout'
            ? currentAppLocalizations.qrImageTimeout
            : currentAppLocalizations.qrImageReadFailed,
      );
    } finally {
      isDecoding = false;
      await cancel();
    }
  }
}
