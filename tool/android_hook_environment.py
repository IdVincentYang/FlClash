"""Bind Native Assets inputs to one prepared workspace, without granting trust."""

import hashlib
import json
import os
from pathlib import Path
import re
import tomllib

from android_input_materials import MaterialError, SelectedRoot, compare_tree, hash_stream, read_archive
from android_pub_inputs import unique_fields


PROFILE = 'macos_arm64_android_arm64_dev'
HOOK_NDK_DESTINATION = 'ndk/29.0.14206865'
HOOK_ROLES = {
    'setup': ('dart_sdk', 'go', 'ndk_hooks'),
    'rust_api': ('dart_sdk', 'rustup', 'rustc', 'cargo', 'rust_std_host',
                 'rust_std_android', 'ndk_hooks'),
}
BINDING = 'source/tool/android_hook_binding.dart'
EMPTY_BINDING = ('const String? androidHookWorkspace = null;\n'
                 'const String? androidHookContextDigest = null;\n')
ENVIRONMENT_KEYS = set('''PATH HOME LC_ALL LANG GIT_CONFIG_NOSYSTEM GIT_CONFIG_GLOBAL
GIT_TERMINAL_PROMPT GIT_NO_REPLACE_OBJECTS XDG_CONFIG_HOME TMPDIR PUB_CACHE PUB_HOSTED_URL
FLUTTER_ROOT JAVA_HOME JAVA_TOOL_OPTIONS ANDROID_USER_HOME ANDROID_HOME ANDROID_SDK_ROOT
ANDROID_NDK_HOME ANDROID_NDK_ROOT GRADLE_USER_HOME RUSTUP_HOME CARGO_HOME RUSTUP_AUTO_INSTALL
RUSTUP_NO_UPDATE_CHECK RUSTUP_DIST_SERVER RUSTUP_UPDATE_ROOT GOTOOLCHAIN GOENV GOTELEMETRY
GOFLAGS GOPATH GOCACHE GOMODCACHE CI DASH__SUPPRESS_ANALYTICS DART_SUPPRESS_ANALYTICS
FLUTTER_SUPPRESS_ANALYTICS FLUTTER_SKIP_UPDATE_CHECK FLCLASH_ANDROID_PROFILE FLCLASH_ANDROID_DART
FLCLASH_ANDROID_FLUTTER_ROOT FLCLASH_ANDROID_GO FLCLASH_ANDROID_NDK FLCLASH_ANDROID_CMAKE
FLCLASH_ANDROID_PYTHON FLCLASH_ANDROID_PACKAGER_CONFIG FLCLASH_ANDROID_PACKAGER_MAIN'''.split())


def file_identity(path):
    with SelectedRoot(path, False) as selected, selected.file() as stream:
        size = os.fstat(stream.fileno()).st_size
        return {'size': size, 'sha256': hash_stream(stream, size)}


def binding_source(workspace, digest):
    literal = "'" + json.dumps(str(workspace), ensure_ascii=True)[1:-1].replace("'", r"\'").replace('$', r'\$') + "'"
    return ('// ignore_for_file: unnecessary_nullable_for_final_variable_declarations\n'
            f'const String? androidHookWorkspace = {literal};\n'
            f"const String? androidHookContextDigest = '{digest}';\n")


def configure_hook_pubspec(workspace):
    root = Path(workspace)
    path = root / 'source/pubspec.yaml'
    text = path.read_text()
    if 'flclash_android_environment' in text:
        raise MaterialError('Hook pubspec already contains a workspace selection')
    for hook in HOOK_ROLES:
        needle = f'    {hook}:\n      build_assets: true\n'
        if text.count(needle) != 1:
            raise MaterialError('Expected original enabled project hook definition')
        value = json.dumps(str(root / 'hook-environment.json'))
        text = text.replace(needle, needle + f'      flclash_android_environment: {value}\n')
    path.write_text(text)


def context_files(workspace):
    root = Path(workspace)
    names = {
        'source/pubspec.yaml', 'source/pubspec.lock', 'source/setup.dart',
        'source/.dart_tool/package_config.json', 'source/.flutter-plugins-dependencies',
        'source/plugins/setup/hook/build.dart', 'source/plugins/rust_api/hook/build.dart',
        'source/plugins/rust_api/rust/Cargo.lock',
        'source/plugins/rust_api/rust/rust-toolchain.toml',
        'source/tool/android_hook_environment.dart', 'source/tool/android_artifacts.toml',
        'source/tool/verify_android_inputs.py', 'home/.gitconfig', 'rustup/settings.toml',
    }
    for pattern in ('source/tool/android_*.py', 'source/plugins/setup/setup_hooks/lib/**/*.dart'):
        names.update(str(p.relative_to(root)) for p in root.glob(pattern))
    return names


def write_hook_context(workspace, environment, archives, material_roots):
    root = Path(workspace)
    binding = root / BINDING
    if binding.read_text() != EMPTY_BINDING:
        raise MaterialError('Owned hook binding must start from its tracked empty template')
    roles = set().union(*HOOK_ROLES.values())
    data = {
        'schema': 1, 'profile': PROFILE, 'workspace': str(root),
        'source': str(root / 'source'), 'environment': environment,
        'archives': {role: archives[role] for role in sorted(roles)},
        'material_roots': {role: str(material_roots[role]) for role in sorted(roles)},
        'files': {name: file_identity(root / name) for name in sorted(context_files(root))},
    }
    validate_environment(root, environment)
    raw = (json.dumps(data, sort_keys=True, indent=2) + '\n').encode()
    digest = hashlib.sha256(raw).hexdigest()
    path = root / 'hook-environment.json'
    with path.open('xb') as stream:
        stream.write(raw)
    binding.write_text(binding_source(root, digest))
    return path, binding, digest


def validate_environment(root, environment):
    if (not isinstance(environment, dict) or set(environment) != ENVIRONMENT_KEYS
            or any(not isinstance(v, str) or '\0' in v for v in environment.values())):
        raise MaterialError('Unexpected hook environment fields')
    fixed = {
        'HOME': str(root / 'home'), 'XDG_CONFIG_HOME': str(root / 'home/.config'),
        'TMPDIR': str(root / 'tmp'), 'PUB_CACHE': str(root / 'pub-cache'),
        'RUSTUP_HOME': str(root / 'rustup'), 'CARGO_HOME': str(root / 'cargo'),
        'GOPATH': str(root / 'go'), 'GOCACHE': str(root / 'go/build-cache'),
        'GOMODCACHE': str(root / 'go/pkg/mod'), 'GRADLE_USER_HOME': str(root / 'gradle-home'),
        'GIT_CONFIG_GLOBAL': str(root / 'home/.gitconfig'),
        'FLCLASH_ANDROID_PROFILE': PROFILE, 'GOENV': 'off', 'GOTOOLCHAIN': 'local',
        'GOTELEMETRY': 'off', 'GOFLAGS': '-mod=readonly', 'RUSTUP_AUTO_INSTALL': '0',
        'RUSTUP_NO_UPDATE_CHECK': '1', 'CI': 'true', 'DASH__SUPPRESS_ANALYTICS': 'true',
        'DART_SUPPRESS_ANALYTICS': 'true', 'FLUTTER_SUPPRESS_ANALYTICS': 'true',
        'FLUTTER_SKIP_UPDATE_CHECK': 'true',
    }
    if any(environment.get(k) != v for k, v in fixed.items()):
        raise MaterialError('Hook environment changed the prepared workspace or tool controls')


def read_hook_context(path, digest, hook, repository):
    path = Path(path).absolute()
    if path.name != 'hook-environment.json' or hook not in HOOK_ROLES:
        raise MaterialError('Expected a fixed project hook context')
    if not isinstance(digest, str) or not re.fullmatch('[0-9a-f]{64}', digest):
        raise MaterialError('Expected the compiled current context binding')
    root = path.parent
    if Path(repository).resolve(strict=True) != root / 'source':
        raise MaterialError('Hook checker must belong to the same owned source')
    with SelectedRoot(path, False) as selected, selected.file() as stream:
        raw = stream.read(4 * 1024 * 1024 + 1)
    if len(raw) > 4 * 1024 * 1024 or hashlib.sha256(raw).hexdigest() != digest:
        raise MaterialError('Hook context changed before consumption')
    data = json.loads(raw, object_pairs_hook=unique_fields)
    if (not isinstance(data, dict)
            or set(data) != {'schema', 'profile', 'workspace', 'source', 'environment',
                             'archives', 'material_roots', 'files'}
            or type(data['schema']) is not int or data['schema'] != 1
            or data['profile'] != PROFILE or data['workspace'] != str(root)
            or data['source'] != str(root / 'source')):
        raise MaterialError('Unexpected or stale hook context')
    validate_environment(root, data['environment'])
    if (not isinstance(data['files'], dict) or set(data['files']) != context_files(root)):
        raise MaterialError('Hook source bindings are incomplete')
    for name, expected in data['files'].items():
        if file_identity(root / name) != expected:
            raise MaterialError('Hook source, configuration or generated input changed')
    with SelectedRoot(root, True) as selected, selected.file(BINDING) as stream:
        if stream.read() != binding_source(root, digest).encode():
            raise MaterialError('Current compiled hook binding differs from owned source')
    return data


def check_hook_context(path, digest, hook, repository, policy):
    data = read_hook_context(path, digest, hook, repository)
    root = Path(data['workspace'])
    roles = set().union(*HOOK_ROLES.values())
    if (not isinstance(data['archives'], dict) or set(data['archives']) != roles
            or not isinstance(data['material_roots'], dict) or set(data['material_roots']) != roles):
        raise MaterialError('Hook tool roles differ from the fixed profile')
    indices = {}
    for role in HOOK_ROLES[hook]:
        expected_root = (root / 'flutter/bin/cache/dart-sdk' if role == 'dart_sdk' else
                         root / 'android-sdk' / HOOK_NDK_DESTINATION
                         if role == 'ndk_hooks' else root / 'materials' / role)
        if data['material_roots'][role] != str(expected_root):
            raise MaterialError('Hook tool root differs from the prepared role')
        indices[role] = read_archive(data['archives'][role], policy['artifacts'][role])
        compare_tree(expected_root, indices[role])
    env = data['environment']
    expected_tools = {
        'FLCLASH_ANDROID_DART': root / 'flutter/bin/cache/dart-sdk/bin/dart',
        'FLCLASH_ANDROID_GO': root / 'materials/go/bin/go',
        'FLCLASH_ANDROID_NDK': root / 'android-sdk' / HOOK_NDK_DESTINATION,
        'FLCLASH_ANDROID_FLUTTER_ROOT': root / 'flutter',
        'FLUTTER_ROOT': root / 'flutter',
    }
    if any(env[name] != str(value) for name, value in expected_tools.items()):
        raise MaterialError('Hook executable selection differs from the prepared role')
    if hook == 'rust_api':
        version = policy['artifacts']['rustc']['version']
        triple = version + '-aarch64-apple-darwin'
        expected = {}
        for role in ('rustc', 'cargo', 'rust_std_host', 'rust_std_android'):
            expected.update({name: item for name, item in indices[role].items()
                             if name != 'manifest.in' and item['kind'] != 'directory'})
        compare_tree(root / 'rustup/toolchains' / triple, expected, complete=False)
        with SelectedRoot(root / 'rustup', True) as selected, selected.file('settings.toml') as stream:
            settings = tomllib.load(stream)
        if settings != {'version': '12', 'default_toolchain': triple, 'overrides': {}}:
            raise MaterialError('Rustup dispatch differs from the prepared toolchain')
        for name in ('cargo', 'rustc', 'rustdoc'):
            path = root / 'cargo/bin' / name
            if not path.is_symlink() or os.readlink(path) != str(root / 'materials/rustup/rustup'):
                raise MaterialError('Cargo proxy differs from the prepared rustup')
        if any((root / 'cargo' / name).exists() for name in ('config', 'config.toml')):
            raise MaterialError('Unexpected Cargo override configuration')
    return {'status': 'current_hook_inputs_checked', 'hook': hook,
            'context_sha256': digest, 'profile_ready': False}


def check_hook_outputs(workspace, digest):
    root = Path(workspace)
    result = {}
    for hook in HOOK_ROLES:
        entries = list((root / 'source/.dart_tool/hooks_runner' / hook).glob('*/input.json'))
        if len(entries) != 1:
            raise MaterialError('Expected one current Native Assets input per project hook')
        input_path = entries[0]
        with SelectedRoot(input_path, False) as selected, selected.file() as stream:
            raw_input = stream.read(4 * 1024 * 1024 + 1)
        if len(raw_input) > 4 * 1024 * 1024:
            raise MaterialError('Excessive Native Assets input')
        native_input = json.loads(raw_input, object_pairs_hook=unique_fields)
        output_path = input_path.with_name('output.json')
        with SelectedRoot(output_path, False) as selected, selected.file() as stream:
            output = json.load(stream, object_pairs_hook=unique_fields)
        defines = native_input.get('user_defines', {}).get('workspace_pubspec', {})
        metadata = [
            {'type': 'hooks/metadata', 'encoding': {
                'key': 'flclash_android_environment_sha256', 'value': digest}},
            {'type': 'hooks/metadata', 'encoding': {
                'key': 'flclash_android_hook_input_sha256',
                'value': hashlib.sha256(raw_input).hexdigest()}},
        ]
        if (native_input.get('package_name') != hook
                or native_input.get('package_root', '').rstrip('/') != str(root / 'source/plugins' / hook)
                or defines.get('base_path') != str(root / 'source/pubspec.yaml')
                or defines.get('defines') != {'build_assets': True,
                    'flclash_android_environment': str(root / 'hook-environment.json')}
                or native_input.get('config', {}).get('build_asset_types') != ['code_assets/code']
                or output.get('status') != 'success'
                or output.get('assets_for_build') != metadata
                or not {str(root / 'hook-environment.json'), str(root / BINDING)} <= set(output.get('dependencies', []))):
            raise MaterialError('Native Assets did not complete both current managed hooks')
        result[hook] = {'input': file_identity(input_path), 'output': file_identity(output_path),
                        'context_sha256': digest}
    return result
