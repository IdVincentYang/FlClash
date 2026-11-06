# Gradle Wrapper bootstrap

The Wrapper JAR and `android/gradlew` launchers are Gradle bootstrap code under the
included [license](LICENSE). The JAR's embedded notices remain intact.

The accepted release is declared by [gradle-wrapper.properties](gradle-wrapper.properties).
The JAR is the `gradle-wrapper.jar` resource inside
`lib/plugins/gradle-wrapper-main-9.8.0.jar` in the official Gradle ALL distribution.
Its bytes match Gradle's separately published
[Wrapper checksum](https://services.gradle.org/distributions/gradle-9.8.0-wrapper.jar.sha256).
The Gradle repository's own bootstrap JAR at that tag is a different artifact.

The launchers come from the fixed [Gradle source tag](https://github.com/gradle/gradle/tree/v9.8.0).
Exact acceptance references and digests are maintained in
[`android_artifacts.toml`](../../../tool/android_artifacts.toml), rather than copied here.

When updating the declared Gradle version, obtain the release references, check the
distribution and embedded Wrapper against them, and update the launchers and license
from that same accepted release. Synchronize the native distribution checksum and
acceptance anchors. Do not replace the JAR from a Flutter SDK cache or use a local
binary's self-reported version as acceptance evidence.

For the managed build entry and its supported scope, see the
[Android build guide](../../../docs/development/android_build_guide.md#发布工件接受与受管构建).
