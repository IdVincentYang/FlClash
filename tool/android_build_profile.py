"""Prepare one fresh macOS ARM64 Android build from explicitly selected materials."""

import hashlib
import json
import os
from pathlib import Path
import shutil
import shlex
import subprocess
import sys

from android_git_inputs import git_environment, materialize_source
from android_hook_environment import (
    HOOK_NDK_DESTINATION, check_hook_outputs, configure_hook_pubspec, write_hook_context,
)
from android_input_materials import (
    MaterialError, SelectedRoot, clone_verified_file, compare_tree, hash_stream,
    materialize_archive, materialize_tree, merge_materialized, read_archive,
    relative, write_verified_file,
)
from android_managed_build import BuildWorkspace
from android_maven_inputs import maven_references, verify_maven_files, verify_native_metadata
from android_pub_inputs import read_native_lock, unique_fields, verify_pub_graph


SDK_DESTINATIONS = {
    'dart_sdk': 'dart-sdk',
    'flutter_patched_sdk': 'artifacts/engine/common',
    'flutter_patched_sdk_product': 'artifacts/engine/common',
    'sky_engine': 'pkg', 'flutter_gpu': 'pkg',
    'flutter_host': 'artifacts/engine/darwin-x64',
    'font_subset': 'artifacts/engine/darwin-x64', 'engine_stamp': '',
    'sdk_gradle_wrapper': 'artifacts/gradle_wrapper',
    'material_fonts': 'artifacts/material_fonts',
}
for _role in ('libimobiledevice', 'libusbmuxd', 'libplist', 'openssl',
              'libimobiledeviceglue', 'ios_deploy'):
    SDK_DESTINATIONS[_role] = 'artifacts/' + _role.replace('_', '-')
for _arch in ('arm', 'arm64', 'x64'):
    for _mode in ('profile', 'release'):
        SDK_DESTINATIONS[f'android_gen_snapshot_{_arch}_{_mode}'] = (
            f'artifacts/engine/android-{_arch}-{_mode}/darwin-x64'
        )
for _arch in ('arm', 'arm64', 'x64', 'x86'):
    SDK_DESTINATIONS['android_' + _arch] = 'artifacts/engine/android-' + _arch
    if _arch != 'x86':
        for _mode in ('profile', 'release'):
            SDK_DESTINATIONS[f'android_{_arch}_{_mode}'] = (
                f'artifacts/engine/android-{_arch}-{_mode}'
            )
ANDROID_DESTINATIONS = {
    'android_platform35': 'platforms/android-35',
    'android_platform36': 'platforms/android-36',
    'android_platform37': 'platforms/android-37.0',
    'android_build_tools36': 'build-tools/36.0.0',
    'android_build_tools': 'build-tools/37.0.0',
    'android_platform_tools': 'platform-tools', 'cmake': 'cmake/3.22.1',
    'ndk_jni': 'ndk/28.2.13676358', 'ndk_hooks': HOOK_NDK_DESTINATION,
}
WIP_FILES = {
    '.agents/architecture.md', '.github/workflows/build.yaml',
    '.github/workflows/pages.yaml', 'android/.gitignore',
    'android/gradle/wrapper/gradle-wrapper.properties',
    'android/gradle/wrapper/gradle-wrapper.jar', 'android/gradle/wrapper/LICENSE',
    'android/gradle/wrapper/README.md', 'android/gradlew', 'android/gradlew.bat',
    'android/gradle/verification-metadata.xml', 'android/gradle/verification-keyring.keys',
    'docs/development/android_build_guide.md',
    'docs/features/security/android_build_sources.md',
    'docs/features/security/flclash_security_plan.md',
    'docs/features/security/loop5/loop5_plan.md',
    'docs/features/security/loop5/loop5_tasks.md',
    'docs/features/security/loop5/l5_t02_plan.md',
    'docs/features/security/loop5/l5_t02_result.md',
    'docs/features/security/loop5/l5_t04_plan.md',
    'docs/features/security/loop5/l5_t04_result.md',
    '.agents/commands.md', 'android/app/build.gradle.kts',
    'tool/ci_release.py', 'tool/test_ci_release.py', 'tool/ci_android_manifest.java',
    'tool/ci_push.py', 'tool/test_ci_push.py',
    'tool/test_ci_android_signing.py', 'tool/test_ci_workflows.py',
    'release_telegram.py', 'tool/test_release_telegram.py',

    'setup.dart', 'test/setup_test.dart', 'plugins/rust_api/hook/build.dart',
    'plugins/setup/hook/build.dart',
    'plugins/setup/setup_hooks/lib/src/core_builder.dart',
    'plugins/setup/setup_hooks/lib/src/util.dart',
}


def read_selections(path, policy):
    with SelectedRoot(path, False) as selected, selected.file() as stream:
        raw = stream.read(4 * 1024 * 1024 + 1)
    if len(raw) > 4 * 1024 * 1024:
        raise MaterialError('Excessive local material selections')
    data = json.loads(raw, object_pairs_hook=unique_fields)
    required = {'archives', 'pub_archives', 'git_repositories', 'maven_root', 'maven_files'}
    if not isinstance(data, dict) or not required <= data.keys() or set(data) - required - {'trees'}:
        raise MaterialError('Selections contain paths only; unknown fields rejected')
    data.setdefault('trees', {})
    for field in ('archives', 'pub_archives', 'git_repositories', 'maven_files', 'trees'):
        if (not isinstance(data[field], dict)
                or any(not isinstance(k, str) or not isinstance(v, str) or not v
                       for k, v in data[field].items())):
            raise MaterialError('Expected explicit named material paths')
    if (set(data['archives']) != set(policy['artifacts'])
            or not isinstance(data['maven_root'], str) or not data['maven_root']):
        raise MaterialError('Every accepted tool role needs an explicit material selection')
    if set(data['trees']) - (set(policy['artifacts']) - {'framework'}):
        raise MaterialError('Cached tool trees can only provide selected archive payloads')
    for field in ('archives', 'pub_archives', 'git_repositories', 'trees'):
        data[field] = {k: str(Path(v).absolute()) for k, v in data[field].items()}
    data['maven_root'] = str(Path(data['maven_root']).absolute())
    return data


class ManagedAndroidBuild:
    def __init__(self, repository, policy, selections, destination):
        self.repository = Path(repository).resolve(strict=True)
        self.policy = policy['artifacts']
        self.selections = selections
        destination = Path(destination).absolute()
        parent = destination.parent.resolve(strict=True)
        if not parent.is_relative_to(self.repository / 'build'):
            raise MaterialError('Managed workspace must be under this project build directory')
        destination = parent / destination.name
        if (destination.name in ('', '.', '..')
                or any(not 32 <= ord(c) <= 126 or c in (os.pathsep, ',', '\\')
                       for c in str(destination))):
            raise MaterialError('Unsupported managed workspace path: PATH/config separators '
                                'or non-ASCII/control characters')
        self.workspace = BuildWorkspace(destination)
        self.root = self.workspace.root
        self.materials = self.root / 'materials'
        self.materials.mkdir()
        self.home = self.root / 'home'
        self.home.mkdir()
        self.sdk = self.root / 'flutter'
        self.project = self.root / 'source'
        self.android = self.root / 'android-sdk'
        self.android.mkdir()
        self.cache = self.root / 'pub-cache'
        self.cache.mkdir()
        self.packager = self.root / 'packager'
        self.packager.mkdir()
        self.environment = git_environment(self.home)
        self.environment.update({'LANG': 'en_US.UTF-8', 'LC_ALL': 'en_US.UTF-8'})
        self.indices = {}
        self.generated = {}
        self.results = {'status': 'preparing', 'profile_ready': False,
                        'workspace': str(self.root)}
        self.record()

    def record(self):
        (self.root / 'result.json').write_text(json.dumps(self.results, indent=2) + '\n')

    def bind_generated(self, *paths):
        for path in paths:
            with SelectedRoot(path, False) as selected, selected.file() as stream:
                size = os.fstat(stream.fileno()).st_size
                self.generated[str(path)] = {'size': size, 'sha256': hash_stream(stream, size)}
        self.results['same_run_generated_files'] = self.generated
        self.record()

    def check_generated(self):
        for path, expected in self.generated.items():
            with SelectedRoot(path, False) as selected, selected.file() as stream:
                if hash_stream(stream, expected['size']) != expected['sha256']:
                    raise MaterialError('Same-run generated input changed before consumption')

    def run(self, command, cwd, label):
        return self.workspace.run([str(v) for v in command], cwd, self.environment, label)

    def git_output(self, root, *args):
        return subprocess.run(['/usr/bin/git', '-c', 'core.hooksPath=/dev/null',
                               '-C', str(root), *args], env=git_environment(self.home),
                              check=True, capture_output=True).stdout

    def snapshot_project(self):
        records = self.git_output(self.repository, 'status', '--porcelain=v1', '-z',
                                  '--untracked-files=all').split(b'\0')
        changes = []
        for record in records:
            if not record:
                continue
            status, name = record[:2], record[3:].decode('utf-8')
            relative(name)
            tooling = (name.startswith('plugins/setup/setup_hooks/lib/')
                       or name.startswith('plugins/setup/setup_hooks/test/')
                       or name.startswith('tool/android_') or name.startswith('tool/test_android_')
                       or name == 'tool/verify_android_inputs.py'
                       or name == 'tool/test_verify_android_inputs.py')
            if status not in (b' M', b'??', b'M ', b'A ') or not (name in WIP_FILES or tooling):
                raise MaterialError('Unrelated or unsupported source WIP; original retained')
            changes.append(name)
        core = self.repository / 'core/Clash.Meta'
        if self.git_output(core, 'status', '--porcelain=v1').strip():
            raise MaterialError('Core source has local changes')
        commit = self.git_output(self.repository, 'rev-parse', 'HEAD').decode().strip()
        core_commit = self.git_output(core, 'rev-parse', 'HEAD').decode().strip()
        gitlink = self.git_output(self.repository, 'ls-tree', 'HEAD', 'core/Clash.Meta')
        if gitlink.split()[1:3] != [b'commit', core_commit.encode()]:
            raise MaterialError('Core does not match the selected parent gitlink')
        self.run(['/usr/bin/git', '-c', 'core.hooksPath=/dev/null', 'worktree', 'add',
                  '--detach', self.project, commit], self.repository, 'project-snapshot')
        nested = self.project / 'core/Clash.Meta'
        if nested.exists():
            nested.rmdir()
        self.run(['/usr/bin/git', '-c', 'core.hooksPath=/dev/null', 'worktree', 'add',
                  '--detach', nested, core_commit], core, 'core-snapshot')
        identity = {}
        with SelectedRoot(self.repository, True) as source:
            for name in changes:
                with source.file(name) as stream:
                    stat = os.fstat(stream.fileno())
                    item = {'kind': 'file', 'size': stat.st_size,
                            'sha256': hash_stream(stream, stat.st_size),
                            'mode': 0o755 if stat.st_mode & 0o111 else 0o644}
                    stream.seek(0)
                    target = self.project / name
                    target.parent.mkdir(parents=True, exist_ok=True)
                    if target.exists():
                        if target.is_symlink() or not target.is_file():
                            raise MaterialError('Unexpected own source snapshot entry')
                        target.unlink()
                    with SelectedRoot(self.project, True) as output:
                        write_verified_file(output, name, stream, item)
                    identity[name] = item
        self.results.update(source_commit=commit, core_commit=core_commit, source_wip=identity)
        self.record()

    def prepare_tools(self):
        archives = self.selections['archives']
        for role, specification in self.policy.items():
            if role == 'framework':
                continue
            self.indices[role] = read_archive(archives[role], specification)
        materialize_source(archives['framework'], self.policy['framework']['commit'],
                           self.sdk, self.home)
        cache = self.sdk / 'bin/cache'
        cache.mkdir(parents=True, exist_ok=True)
        self.material_roots = {}
        for role, specification in self.policy.items():
            if role != 'framework':
                destination = (self.android / ANDROID_DESTINATIONS[role]
                               if role in ANDROID_DESTINATIONS else
                               cache / 'dart-sdk' if role == 'dart_sdk' else self.materials / role)
                destination.parent.mkdir(parents=True, exist_ok=True)
                if role in self.selections.get('trees', {}):
                    materialize_tree(self.selections['trees'][role], self.indices[role], destination)
                else:
                    materialize_archive(archives[role], specification, destination)
                self.material_roots[role] = destination
        expected = {}
        order = ['dart_sdk', 'sky_engine', 'flutter_gpu'] + [
            role for role in SDK_DESTINATIONS if role not in ('dart_sdk', 'sky_engine', 'flutter_gpu')
        ]
        for role in order:
            replacements = ({'pkg/LICENSE.zip_old_location.md': expected['pkg/LICENSE.zip_old_location.md']}
                            if role == 'flutter_gpu' else {})
            mapped = merge_materialized(self.material_roots[role], self.indices[role], cache,
                                        SDK_DESTINATIONS[role], replacements=replacements)
            for name, item in mapped.items():
                old = expected.get(name)
                if old and old['kind'] != 'directory' and old != item and name not in replacements:
                    raise MaterialError('Conflicting accepted SDK components')
                expected[name] = item
        compare_tree(cache, expected)
        for role, prefix in ANDROID_DESTINATIONS.items():
            compare_tree(self.android / prefix, self.indices[role])
        metadata = self.repository / 'tool/android_bootstrap/android_platform37.package.xml'
        destination = self.android / ANDROID_DESTINATIONS['android_platform37']
        with SelectedRoot(metadata, False) as selected, selected.file() as stream:
            size = os.fstat(stream.fileno()).st_size
            digest = hash_stream(stream, size)
            stream.seek(0)
            with SelectedRoot(destination, True) as target:
                write_verified_file(target, 'package.xml', stream, {
                    'size': size, 'sha256': digest, 'mode': 0o644,
                })
        self.results['native_sdk_metadata'] = {'path': str(metadata), 'sha256': digest,
                                               'license_acceptance_record_written': False}
        self.sdk_payload = expected
        self.dart = cache / 'dart-sdk/bin/dart'
        self.jdk = self.materials / 'jdk/Contents/Home'
        self.go = self.materials / 'go/bin/go'
        self.ndk = self.android / ANDROID_DESTINATIONS['ndk_hooks']
        self.prepare_environment()
        self.results['material_roots'] = {role: str(path) for role, path in self.material_roots.items()}
        self.record()

    def prepare_environment(self):
        config = self.home / '.config'
        config.mkdir()
        android_user = self.home / '.android'
        android_user.mkdir()
        cargo = self.root / 'cargo'
        cargo.mkdir()
        rustup = self.root / 'rustup'
        rustup.mkdir()
        temp = self.root / 'tmp'
        temp.mkdir()
        bins = self.root / 'bin'
        bins.mkdir()
        os.symlink(Path(sys.executable).resolve(), bins / 'python3')
        os.symlink(Path(sys.executable).resolve(), bins / 'python')
        self.environment.update({
            'HOME': str(self.home), 'XDG_CONFIG_HOME': str(config), 'TMPDIR': str(temp),
            'PUB_CACHE': str(self.cache), 'PUB_HOSTED_URL': 'https://pub.dev',
            'FLUTTER_ROOT': str(self.sdk), 'JAVA_HOME': str(self.jdk),
            'JAVA_TOOL_OPTIONS': shlex.quote('-Duser.home=' + str(self.home)),
            'ANDROID_USER_HOME': str(android_user),
            'ANDROID_HOME': str(self.android), 'ANDROID_SDK_ROOT': str(self.android),
            'ANDROID_NDK_HOME': str(self.ndk), 'ANDROID_NDK_ROOT': str(self.ndk),
            'GRADLE_USER_HOME': str(self.root / 'gradle-home'),
            'RUSTUP_HOME': str(rustup), 'CARGO_HOME': str(cargo),
            'RUSTUP_AUTO_INSTALL': '0', 'RUSTUP_NO_UPDATE_CHECK': '1',
            'RUSTUP_DIST_SERVER': (self.root / 'no-rust-downloads').as_uri(),
            'RUSTUP_UPDATE_ROOT': (self.root / 'no-rust-updates').as_uri(),
            'GOTOOLCHAIN': 'local', 'GOENV': 'off', 'GOTELEMETRY': 'off',
            'GOFLAGS': '-mod=readonly',
            'GOPATH': str(self.root / 'go'), 'GOCACHE': str(self.root / 'go/build-cache'),
            'GOMODCACHE': str(self.root / 'go/pkg/mod'),
            'CI': 'true', 'DASH__SUPPRESS_ANALYTICS': 'true',
            'DART_SUPPRESS_ANALYTICS': 'true', 'FLUTTER_SUPPRESS_ANALYTICS': 'true',
            'FLUTTER_SKIP_UPDATE_CHECK': 'true',
            'FLCLASH_ANDROID_PROFILE': 'macos_arm64_android_arm64_dev',
            'FLCLASH_ANDROID_DART': str(self.dart), 'FLCLASH_ANDROID_FLUTTER_ROOT': str(self.sdk),
            'FLCLASH_ANDROID_GO': str(self.go), 'FLCLASH_ANDROID_NDK': str(self.ndk),
            'FLCLASH_ANDROID_CMAKE': str(self.android / ANDROID_DESTINATIONS['cmake']),
            'FLCLASH_ANDROID_PYTHON': str(Path(sys.executable).resolve()),
        })
        paths = [bins, self.dart.parent, self.sdk / 'bin', self.go.parent,
                 self.materials / 'rustup', self.jdk / 'bin', cargo / 'bin',
                 self.android / ANDROID_DESTINATIONS['cmake'] / 'bin']
        self.environment['PATH'] = ':'.join(map(str, paths)) + ':/usr/bin:/bin:/usr/sbin:/sbin'
        (config / 'settings').write_text(json.dumps({
            'jdk-dir': str(self.jdk), 'android-sdk': str(self.android),
        }) + '\n')
        (self.project / 'android/local.properties').write_text(
            f'flutter.sdk={self.sdk}\nsdk.dir={self.android}\n'
            f'cmake.dir={self.android / ANDROID_DESTINATIONS["cmake"]}\n'
        )
        if (self.project / 'android/gradle/gradle-daemon-jvm.properties').exists():
            raise MaterialError('Daemon criteria can override the accepted Java selection')
        (self.root / 'environment.json').write_text(json.dumps(self.environment, indent=2) + '\n')

    def prepare_rust(self):
        version = self.policy['rustc']['version']
        toolchain = self.root / 'rustup/toolchains' / (version + '-aarch64-apple-darwin')
        toolchain.mkdir(parents=True)
        installers = self.root / 'rust-installers'
        installers.mkdir()
        expected = {}
        for role in ('rustc', 'cargo', 'rust_std_host', 'rust_std_android'):
            specification = dict(self.policy[role], prefix='')
            materialize_archive(self.selections['archives'][role], specification, installers / role)
            top = self.policy[role]['prefix'].split('/')[0]
            installer = installers / role / top / 'install.sh'
            self.run(['/bin/sh', installer, '--prefix=' + str(toolchain), '--disable-ldconfig'],
                     installer.parent, 'install-' + role)
            expected.update({name: item for name, item in self.indices[role].items()
                             if name != 'manifest.in' and item['kind'] != 'directory'})
        compare_tree(toolchain, expected, complete=False)
        rustup = self.materials / 'rustup/rustup'
        proxies = self.root / 'cargo/bin'
        proxies.mkdir()
        for name in ('cargo', 'rustc', 'rustdoc'):
            os.symlink(rustup, proxies / name)
        self.run([rustup, 'default', version], self.root, 'rustup-select')
        for command in ('rustc', 'cargo'):
            self.run([rustup, 'run', version, command, '--version'], self.root, command + '-version')

    def prepare_pub(self):
        locks = {
            'app': self.project / 'pubspec.lock',
            'flutter_tools': self.repository / 'tool/android_bootstrap/flutter_tools.pubspec.lock',
            'distributor': self.repository / 'tool/android_bootstrap/distributor.pubspec.lock',
        }
        packages = {}
        repositories = {}
        for path in locks.values():
            for name, package in read_native_lock(path)['packages'].items():
                if package['source'] == 'hosted':
                    key = name + '-' + package['version']
                    old = packages.get(key)
                    if old and old != package['description']['sha256']:
                        raise MaterialError('Native resolutions contradict one hosted package identity')
                    packages[key] = package['description']['sha256']
                elif package['source'] == 'git':
                    description = package['description']
                    repositories[description['url'] + '@' + description['resolved-ref']] = description
        if (set(packages) != set(self.selections['pub_archives'])
                or set(repositories) != set(self.selections['git_repositories'])):
            raise MaterialError('Selected pub materials must match the three native resolutions')
        hosted = self.cache / 'hosted/pub.dev'
        hosted.mkdir(parents=True)
        hashes = self.cache / 'hosted-hashes/pub.dev'
        hashes.mkdir(parents=True)
        for key, digest in packages.items():
            path = Path(self.selections['pub_archives'][key])
            materialize_archive(path, {'format': 'tar.gz', 'prefix': '',
                                      'size': path.stat().st_size, 'sha256': digest}, hosted / key)
            (hashes / (key + '.sha256')).write_text(digest + '\n')
        git_lines = ['[protocol]\n\tallow = never\n[protocol "file"]\n\tallow = always\n']
        from android_git_inputs import source_index
        for key, description in repositories.items():
            selected = Path(self.selections['git_repositories'][key])
            source_index(selected, description['resolved-ref'], self.home)
            url = description['url']
            if any(c in str(selected) + url for c in ('"', '\n', '\r', '\\')):
                raise MaterialError('Unsupported Git material selection text')
            git_lines.append(f'[url "{selected.as_uri()}"]\n\tinsteadOf = {url}\n')
        git_config = self.home / '.gitconfig'
        git_config.write_text(''.join(git_lines))
        self.environment['GIT_CONFIG_GLOBAL'] = str(git_config)
        shutil.copyfile(locks['flutter_tools'], self.sdk / 'packages/flutter_tools/pubspec.lock')
        shutil.copyfile(locks['distributor'], self.packager / 'pubspec.lock')
        shutil.copyfile(self.repository / 'tool/android_bootstrap/distributor.pubspec.yaml',
                        self.packager / 'pubspec.yaml')
        (self.sdk / 'bin/cache/flutter.version.json').write_text(json.dumps({
            'flutterVersion': self.policy['framework']['version'],
        }) + '\n')
        for graph, path in self.graphs().items():
            self.run([self.dart, '--suppress-analytics', 'pub', 'get', '--enforce-lockfile',
                      '--no-precompile', '--no-example'], path, 'pub-' + graph)
            self.check_graph(graph)
            self.run([self.dart, '--suppress-analytics', 'pub', 'get', '--offline',
                      '--enforce-lockfile', '--no-precompile', '--no-example'], path, 'pub-offline-' + graph)
            self.check_graph(graph)

    def graphs(self):
        return {'flutter_tools': self.sdk / 'packages/flutter_tools',
                'distributor': self.packager, 'app': self.project}

    def check_graph(self, graph, plugin_map=False):
        result, roots = verify_pub_graph(
            self.repository, graph, self.graphs()[graph], self.sdk, self.cache,
            self.selections['pub_archives'], self.selections['git_repositories'], self.home,
            require_plugin_map=plugin_map,
        )
        self.results.setdefault('pub_graphs', {})[graph] = result
        self.record()
        return roots

    def bootstrap_flutter(self):
        compare_tree(self.sdk / 'bin/cache', self.sdk_payload, complete=False)
        for graph in self.graphs():
            self.check_graph(graph)
        engine = (self.sdk / 'bin/internal/engine.version').read_text().strip()
        stamps = {name: engine for name in ('engine', 'engine-dart-sdk', 'engine_stamp',
                  'flutter_sdk', 'android-sdk', 'android-internal-build-artifacts', 'font-subset')}
        for name in ('material_fonts', 'gradle_wrapper', 'libimobiledevice', 'libusbmuxd',
                     'libplist', 'openssl', 'libimobiledeviceglue', 'ios-deploy'):
            stamps[name] = (self.sdk / f'bin/internal/{name}.version').read_text().strip()
        cache = self.sdk / 'bin/cache'
        for name, value in stamps.items():
            (cache / (name + '.stamp')).write_text(value + '\n')
        (cache / 'engine.realm').write_text('\n')
        os.utime(self.sdk / 'packages/flutter_tools/pubspec.lock', None)
        commit = self.policy['framework']['commit']
        for args in (['update-ref', 'refs/heads/stable', commit],
                     ['symbolic-ref', 'HEAD', 'refs/heads/stable'],
                     ['update-ref', 'refs/tags/3.47.4', commit],
                     ['remote', 'set-url', 'origin', 'https://github.com/flutter/flutter.git']):
            self.git_output(self.sdk, *args)
        snapshot = cache / 'flutter_tools.snapshot'
        if snapshot.exists():
            raise MaterialError('Fresh SDK unexpectedly contains an executable tool snapshot')
        self.run([self.dart, '--verbosity=error', '--snapshot=' + str(snapshot),
                  '--snapshot-kind=app-jit', '--packages=' + str(
                      self.sdk / 'packages/flutter_tools/.dart_tool/package_config.json'),
                  '--no-enable-mirrors', self.sdk / 'packages/flutter_tools/bin/flutter_tools.dart'],
                 self.sdk, 'first-flutter-snapshot')
        (cache / 'flutter_tools.stamp').write_text(commit + ':\n')
        self.flutter_stamps = {name + '.stamp': value + '\n' for name, value in stamps.items()}
        self.flutter_stamps.update({'engine.realm': '\n', 'flutter_tools.stamp': commit + ':\n'})
        self.bind_generated(snapshot, cache / 'flutter_tools.stamp')
        self.check_generated()
        self.check_flutter_bootstrap()
        self.run([self.sdk / 'bin/flutter', '--suppress-analytics', '--no-version-check',
                  '--version', '--machine'], self.sdk, 'flutter-version')
        self.check_flutter_bootstrap()
        self.run([self.sdk / 'bin/flutter', '--suppress-analytics', '--no-version-check',
                  'pub', 'get', '--offline', '--enforce-lockfile', '--no-example'],
                 self.project, 'flutter-pub')
        self.check_graph('app', plugin_map=True)
        roots = self.check_graph('distributor')
        self.environment['FLCLASH_ANDROID_PACKAGER_CONFIG'] = str(
            self.packager / '.dart_tool/package_config.json')
        self.environment['FLCLASH_ANDROID_PACKAGER_MAIN'] = str(
            roots['flutter_distributor'] / 'bin/main.dart')
        self.bind_generated(self.project / '.flutter-plugins-dependencies', *(
            path / '.dart_tool/package_config.json' for path in self.graphs().values()
        ))
        (self.root / 'environment.json').write_text(json.dumps(self.environment, indent=2) + '\n')

    def build(self):
        self.snapshot_project()
        self.request_digest = hashlib.sha256(json.dumps({
            'source': self.results['source_commit'], 'core': self.results['core_commit'],
            'wip': self.results['source_wip'], 'tools': self.policy,
            'target': 'android-arm64', 'api': 24, 'environment': 'dev',
        }, sort_keys=True).encode()).hexdigest()
        configure_hook_pubspec(self.root, self.request_digest)
        self.prepare_tools()
        self.prepare_rust()
        self.prepare_pub()
        self.bootstrap_flutter()
        context, binding, digest = write_hook_context(
            self.root, self.environment, self.selections['archives'], self.material_roots, self.request_digest)
        self.bind_generated(context, binding, self.project / 'pubspec.yaml')
        self.prepare_gradle()
        for graph in self.graphs():
            self.check_graph(graph, plugin_map=graph == 'app')
        self.check_generated()
        self.check_flutter_bootstrap()
        self.run([self.dart, '--disable-dart-dev',
                  '--packages=' + str(self.project / '.dart_tool/package_config.json'),
                  self.project / 'setup.dart', 'android', '--arch', 'arm64',
                  '--env', 'dev', '--targets', 'apk'], self.project, 'android-package')
        self.check_generated()
        self.results['managed_hooks'] = check_hook_outputs(self.root, digest, self.request_digest)
        checkpoint = json.loads((self.root / 'native-checkpoint.json').read_text(), object_pairs_hook=unique_fields)
        if (checkpoint.get('checkpoint_count') != 2 or checkpoint.get('original_task_completed') is not True
                or checkpoint.get('source') != str(self.project)
                or checkpoint.get('generated') != {k: v['generated'] for k, v in self.results['managed_hooks'].items()}):
            raise MaterialError('Managed Native checkpoints did not bind the packaged producer outputs')
        self.results['native_checkpoint'] = checkpoint
        for record in self.results['managed_hooks'].values():
            self.generated.update(record['generated'])
        self.check_generated()
        outputs = []
        dist = self.project / 'dist'
        if dist.is_dir():
            with SelectedRoot(dist, True) as selected:
                for name, item in selected.inventory().items():
                    if item['kind'] == 'file' and name.endswith('.apk'):
                        with selected.file(name) as stream:
                            outputs.append({'path': str(dist / name), 'size': item['size'],
                                            'sha256': hash_stream(stream, item['size'])})
        if not outputs:
            raise MaterialError('Original packaging command produced no APK')
        self.results.update(status='managed_android_build_completed', profile_ready=True,
                            apks=outputs, apk_source_causality='reserved_for_T03_T05')
        self.record()
        return self.results

    def check_flutter_bootstrap(self):
        compare_tree(self.sdk / 'bin/cache', self.sdk_payload, complete=False)
        with SelectedRoot(self.sdk, True) as selected:
            for name, expected in self.flutter_stamps.items():
                with selected.file('bin/cache/' + name) as stream:
                    if stream.read(len(expected.encode()) + 1) != expected.encode():
                        raise MaterialError('Flutter bootstrap stamp differs; launcher not entered')
            with selected.file('packages/flutter_tools/pubspec.yaml') as pubspec:
                with selected.file('packages/flutter_tools/pubspec.lock') as lock:
                    if os.fstat(pubspec.fileno()).st_mtime_ns > os.fstat(lock.fileno()).st_mtime_ns:
                        raise MaterialError('Flutter launcher would resolve its tool dependencies again')
        if self.environment.get('FLUTTER_TOOL_ARGS'):
            raise MaterialError('Flutter launcher VM options are outside the managed profile')

    def prepare_gradle(self):
        metadata = self.repository / 'android/gradle/verification-metadata.xml'
        references = maven_references(metadata)
        self.results['native_metadata'] = verify_native_metadata(
            self.repository / 'android/gradle', self.project / 'android/gradle',
        )
        checked = verify_maven_files(metadata, self.selections['maven_root'],
                                     self.selections['maven_files'])
        home = self.root / 'gradle-home'
        home.mkdir()
        raw = home / 'caches/modules-2/files-2.1'
        raw.mkdir(parents=True)
        with SelectedRoot(self.selections['maven_root'], True) as source:
            for coordinate, path in self.selections['maven_files'].items():
                group, name, version, filename = coordinate.rsplit('/', 3)
                with source.file(path) as stream:
                    size = os.fstat(stream.fileno()).st_size
                    weak_address = hashlib.sha1()
                    while block := stream.read(1024 * 1024):
                        weak_address.update(block)
                    stream.seek(0)
                    destination = '/'.join([group.replace('/', '.'), name, version,
                                            weak_address.hexdigest().lstrip('0') or '0', filename])
                    (raw / destination).parent.mkdir(parents=True, exist_ok=True)
                    with SelectedRoot(raw, True) as target:
                        clone_verified_file(target, destination, stream, {
                            'kind': 'file', 'size': size, 'mode': 0o644,
                            'sha256': references[coordinate],
                        })
        properties = {
            'org.gradle.java.home': str(self.jdk),
            'org.gradle.jvmargs': '-Xmx4G ' + shlex.quote('-Duser.home=' + str(self.home)),
            'org.gradle.java.installations.auto-detect': 'false',
            'org.gradle.java.installations.auto-download': 'false',
            'org.gradle.java.installations.paths': str(self.jdk),
            'org.gradle.daemon': 'false', 'org.gradle.configuration-cache': 'false', 'org.gradle.workers.max': '2',
            'org.gradle.dependency.verification': 'strict', 'org.gradle.vfs.watch': 'false',
            'kotlin.compiler.execution.strategy': 'in-process',
            'android.builder.sdkDownload': 'false',
        }
        (home / 'gradle.properties').write_text(''.join(f'{k}={v}\n' for k, v in properties.items()))
        init = home / 'init.d'
        init.mkdir()
        (init / 'native-checkpoint.gradle').write_text(
            (self.project / 'tool/android_native_checkpoint.gradle').read_text())
        for role, path in (
            ('gradle_wrapper', 'android/gradle/wrapper/gradle-wrapper.jar'),
            ('gradle_launcher_unix', 'android/gradlew'),
            ('gradle_launcher_windows', 'android/gradlew.bat'),
        ):
            item = self.policy[role]
            with SelectedRoot(self.project / path, False) as selected, selected.file() as stream:
                if hash_stream(stream, item['size']) != item['sha256']:
                    raise MaterialError('Project Gradle bootstrap differs from accepted release')
        wrapper = (self.project / 'android/gradle/wrapper/gradle-wrapper.properties').read_text()
        distribution = self.policy['gradle']
        if ('distributionSha256Sum=' + distribution['sha256']) not in wrapper.splitlines():
            raise MaterialError('Wrapper distribution SHA256 is not bound to accepted release')
        address = int.from_bytes(hashlib.md5(distribution['url'].encode()).digest(), 'big')
        alphabet, encoded = '0123456789abcdefghijklmnopqrstuvwxyz', ''
        while address:
            address, digit = divmod(address, 36)
            encoded = alphabet[digit] + encoded
        wrapper_cache = home / 'wrapper/dists/gradle-9.8.0-all' / encoded
        wrapper_cache.mkdir(parents=True)
        distribution_tree = wrapper_cache / 'gradle-9.8.0'
        (self.materials / 'gradle').rename(distribution_tree)
        compare_tree(distribution_tree, self.indices['gradle'])
        self.results['material_roots']['gradle'] = str(distribution_tree)
        (wrapper_cache / 'gradle-9.8.0-all.zip.ok').touch(exist_ok=False)
        (self.project / 'android/local.properties').write_text(
            f'flutter.sdk={self.sdk}\nsdk.dir={self.android}\n'
            f'cmake.dir={self.android / ANDROID_DESTINATIONS["cmake"]}\n'
        )
        self.results['maven_preflight'] = checked
        self.record()
