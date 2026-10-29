# Local mobile_scanner backend

This package implements the FlClash Android QR consumer. Host validation covers
the current consumer; device acceptance remains pending. It derives from 7.4.2;
LICENSE preserves BSD-3-Clause. The official archive SHA-256 is
`5a51ea79f0cf8293f616a5d08baae185b59b5e6bb24df01f2a63037ade0bade0`.

Android keeps CameraX and replaces ML Kit with ZXing Java core 3.5.4
(Apache-2.0). It requires explicit QR-only formats and rejects other formats,
returnImage and ML autoZoom. Results contain rawValue, QR format and text type;
there are no structured payloads, image returns, models or network decoders.
Non-Android decoder backends retain upstream behavior. Material imports use the
project material_ui package; Android controller/channel start boundaries also
check revoked intent without changing the other backends' stop semantics.

The gallery API pairs pickQrImage/decodeQrImage with cancelQrImage. Fixed errors
never include a selected URI, path, decoded text or platform exception details.
The [contract](../../docs/features/security/qr_scanning_design.md) defines native
request-code reservation, lifecycle, worker quotas and deadlines. The app owns
the exact-name Photo Picker installation metadata exclusion, using node removal
without a selector because this merger otherwise retains an empty app marker.
Recheck image_picker source attribution and final manifests on every upgrade.

## Maintenance and verification

Compare each new upstream archive with this package. Carry forward applicable
camera, permission, channel and rotation fixes, then check root path/lock
selection, resolved release dependencies and the APK. Drop the fork only when
upstream provides the same privacy/function contract and passes these checks.
Do not patch the shared pub cache. Preserve required notices in NOTICES,
Flutter's license collector input; LICENSE remains the upstream BSD license.

Run focused checks from the repository root. Hook/toolchain requirements are in
[commands](../../.agents/commands.md):

```bash
flutter pub get --enforce-lockfile
flutter analyze --no-fatal-infos
flutter test test/pages/scan_test.dart test/common/qr_image_operation_test.dart
flutter test test/plugins/mobile_scanner test/providers/qr_import_test.dart
flutter test test/common/link_test.dart test/common/picker_test.dart test/lint
cd android
./gradlew :mobile_scanner:testDebugUnitTest -Pkotlin.incremental=false
```

Fixtures in android/src/test/resources/qr are synthetic regression assets.
tool/generate_qr_fixtures.py uses development-only Python qrcode 8.2 (BSD) and a
stdlib PNG encoder, independently of the ZXing reader. Install that tool into an
ignored directory and run the generator with that directory on PYTHONPATH.
expected.json fixes the UTF-8 and 2048-character URL inputs; additional images
cover multiple codes and EXIF 2/6. Tests use Robolectric native graphics, literal
stride/crop/rotation oracles and controlled provider/AtomicFile failures. The
API24 storage failure model is separate from actual sdk34 execution. No writer
or test fixture dependency is part of the runtime.

The [gallery regressions][gallery-tests] exercise native ownership and failures;
the [import consumer tests][import-tests] cover the real Dart codec, confirmation
and Request download/save chain with a synthetic native endpoint.
Device CameraX, permissions, OS picker/process behavior, optical performance and
UID observations remain unverified; [Loop 7 acceptance][device-acceptance]
carries those checks. Package ARM64 through the existing
[build guide](../../docs/development/android_build_guide.md). Inspect
release graph, merger/blame, final manifest, R8 mapping, assets and native
libraries: ZXing must have a real consumer while ML Kit/models/transport and the
Photo Picker installation metadata must be absent. Retain the generic service,
action and lawful providers/consumers.

[gallery-tests]: android/src/test/kotlin/dev/steenbakker/mobile_scanner/QrGalleryTest.kt
[import-tests]: ../../test/providers/qr_import_test.dart
[device-acceptance]: ../../docs/features/security/loop7/loop7_plan.md
