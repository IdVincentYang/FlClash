# Request JNI failure regression

This macOS/JDK 17 harness calls the compiled production Kotlin `Core` declarations,
production JNI C++, and production Go exports in isolated JVM processes. It uses
no subscription, network request, APK, device, VPN, or host proxy configuration.

First compile `:core:compileDebugKotlin` with the repository Android Gradle setup
and JDK 17. The runner consumes its classes in
`build/core/tmp/kotlin-classes/debug/`; it does not replace `Core` with a Java stub.
Go, CGO, clang++, and the configured module cache must already be available.

Run from the repository root with a new output directory:

```bash
python3 android/tests/jni/run.py .buildlog/r09-jni-check
python3 android/tests/jni/run.py .buildlog/r09-jni-before --baseline 57f85cf
```

The runner refuses to overwrite output. It records source/overlay/class hashes,
commands' logs, per-process results, generated C headers and native libraries.
The before comparison materializes the complete tracked Core source set from the
requested Git revision in `baseline/`, then applies only the declared host/fault
overlays. It does not select files using the working tree or index. Introduced Go
files are absent even after staging or committing the current implementation.
The matching clean Core checkout is required and linked into this source snapshot
without changing its checkout; a mismatch fails explicitly. `baseline-source.json` records
the exact old blobs and gitlink; `production-source.json` records effective inputs.
The cases expect a terminating panic at each of the four unprotected exports.
Controlled homes are below the output directory and removed after each process.

The after cases assert returned errors, veto before a queued qualification can
proceed, lock release, whole identity rollback, rejection of a foreign/stale
identity, owner-specific cleanup, and receipt completion without clearing fault
or durable recovery responsibility. GlobalRef and input/output C-string counts
delegate to real JVM allocation/deletion and native free operations; one permanent
String-class GlobalRef remains after test-owned references have been released.
The reader/replacement case calls the real socket callback while replacement waits.

Overlay differences are explicit: Android build selectors, unavailable system DNS
update/fd-pressure/UID leaves, the TUN Close leaf, fault insertion points and JDK's
thread-attach pointer signature. Export recovery, state mutation, lock handling,
JNI status/exception conversion and Kotlin declarations are not replaced.
Go runs as darwin with host platform feature constants; the Android
`with_gvisor,no_zerotier` configuration is compiled separately.
TUN Close is an idempotent controlled leaf; this does not prove that an arbitrary
third-party Close panic is retryable. `-Xcheck:jni` can warn about Go/JVM signal
handler coexistence; a successful case is not a signal-handling guarantee.

This verifies host JVM/JNI behavior, not ART, Android scheduling, real TUN/fd
ownership, native fatal errors, or a remotely triggerable fault. Android native
compilation and Kotlin consumer tests are separate checks.
