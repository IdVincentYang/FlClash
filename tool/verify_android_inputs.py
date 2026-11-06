#!/usr/bin/env python3
"""Verify selected Android build inputs against this repository's acceptance anchors."""

import argparse
import configparser
import json
from pathlib import Path
import platform
import re
import sys
import subprocess
import tarfile
import tomllib
from urllib.parse import urlsplit
import zipfile

from android_input_materials import (
    MaterialError,
    compare_tree,
    read_archive,
    relative,
)
from android_git_inputs import source_index


REPOSITORY = Path(__file__).resolve().parent.parent
PROFILE = 'macos_arm64_android_arm64_dev'


def policy_from_repository(root):
    with (root / 'tool/android_artifacts.toml').open('rb') as stream:
        policy = tomllib.load(stream)
    if set(policy) != {'profiles', 'artifacts'}:
        raise MaterialError('Unknown acceptance policy fields')
    if not isinstance(policy['profiles'], dict) or not isinstance(policy['artifacts'], dict):
        raise MaterialError('Expected profile and artifact tables')
    profile = policy['profiles'].get(PROFILE)
    if (not isinstance(profile, dict) or set(profile) != {'host', 'target', 'roles'}
            or profile['host'] != 'macos-arm64'
            or profile['target'] != 'android-arm64-dev'
            or not isinstance(profile['roles'], list) or not profile['roles']
            or any(not isinstance(role, str) or not re.fullmatch('[a-z][a-z0-9_]*', role)
                   for role in profile['roles'])
            or len(profile['roles']) != len(set(profile['roles']))):
        raise MaterialError('Invalid managed profile')
    for role, item in policy['artifacts'].items():
        if not isinstance(item, dict):
            raise MaterialError('Expected an acceptance anchor table')
        required = {'version', 'selector', 'host', 'url', 'reference', 'acceptance',
                    'format', 'prefix', 'complete_tree'}
        identity = {'commit'} if item.get('format') == 'git' else {'sha256', 'size'}
        if (not isinstance(item, dict) or not re.fullmatch(r'[a-z][a-z0-9_]*', role)
                or set(item) - required - identity - {'payload', 'mode'}
                or not (required | identity) <= item.keys()
                or type(item['complete_tree']) is not bool
                or item['host'] not in ('macos-arm64', 'any')):
            raise MaterialError('Invalid acceptance anchor')
        if item['format'] == 'git':
            if not isinstance(item['commit'], str) or not re.fullmatch('[0-9a-f]{40}', item['commit']):
                raise MaterialError('Invalid accepted Git source object')
        elif (not isinstance(item['sha256'], str)
              or not re.fullmatch('[0-9a-f]{64}', item['sha256'])
              or type(item['size']) is not int or item['size'] <= 0):
            raise MaterialError('Invalid accepted payload identity')
        if (item['format'] not in ('file', 'zip', 'tar.gz', 'tar.xz', 'git')
                or ('mode' in item and (type(item['mode']) is not int
                                       or item['mode'] not in (0o644, 0o755)))):
            raise MaterialError('Invalid accepted payload representation')
        for name in ['version', 'selector', 'url', 'reference', 'acceptance', 'format', 'prefix']:
            if not isinstance(item[name], str):
                raise MaterialError('Invalid acceptance anchor text')
        relative(item['prefix'], allow_empty=True)
        if item['format'] == 'file':
            relative(item.get('payload'))
            if item['prefix']:
                raise MaterialError('Standalone payload cannot use an archive prefix')
        elif 'payload' in item or 'mode' in item:
            raise MaterialError('Standalone payload fields do not apply to an archive or Git source')
        if role not in profile['roles']:
            raise MaterialError('Acceptance anchor is outside the managed profile')
        for name in ['url', 'reference']:
            url = urlsplit(item[name])
            if (url.scheme != 'https' or not url.hostname or url.username
                    or url.password or url.fragment
                    or any(ord(c) < 33 for c in item[name])):
                raise MaterialError('Acceptance references must be explicit HTTPS objects')
    return policy


def configured_version(root, selector):
    if selector in ('workflow.GO_VERSION', 'workflow.FLUTTER_VERSION'):
        text = (root / '.github/workflows/build.yaml').read_text()
        name = selector.partition('.')[2]
        matches = re.findall(r"^  " + name + r": ['\"]([0-9.]+)['\"]$", text, re.M)
    elif selector == 'rust.toolchain':
        with (root / 'plugins/rust_api/rust/rust-toolchain.toml').open('rb') as stream:
            matches = [tomllib.load(stream)['toolchain']['channel']]
    elif selector in ('catalog.ndkVersion', 'catalog.compileSdk'):
        with (root / 'android/gradle/libs.versions.toml').open('rb') as stream:
            matches = [tomllib.load(stream)['versions'][selector.partition('.')[2]]]
    elif selector == 'accepted_bootstrap':
        return None
    elif selector == 'gradle.distribution':
        text = (root / 'android/gradle/wrapper/gradle-wrapper.properties').read_text()
        matches = re.findall(r'^distributionUrl=https\\?://services\.gradle\.org/distributions/gradle-([0-9.]+)-all\.zip$', text, re.M)
    else:
        raise MaterialError('Unsupported canonical version selector')
    if len(matches) != 1:
        raise MaterialError('Canonical version is missing or ambiguous')
    return matches[0]


def selections(values):
    result = {}
    for value in values:
        role, separator, path = value.partition('=')
        if (not separator or not path or not re.fullmatch('[a-z][a-z0-9_]*', role)
                or role in result):
            raise MaterialError('Expected a unique role=path selection')
        result[role] = path
    return result


def inspect_material(root, policy, role, archive_path, tree_path):
    item = policy['artifacts'].get(role)
    if item is None:
        raise MaterialError('Role has no accepted reference')
    configured = configured_version(root, item['selector'])
    if configured is not None and item['version'] != configured:
        raise MaterialError('Acceptance object disagrees with canonical tool version')
    if item['format'] == 'git':
        index = source_index(archive_path, item['commit'], '/var/empty')
    else:
        index = read_archive(archive_path, item)
    result = compare_tree(tree_path, index, complete=item['complete_tree'])
    result.update(role=role, version=item['version'],
                  accepted_identity=item.get('sha256', item.get('commit')),
                  status='selected_material_reference_match', profile_ready=False,
                  acceptance_basis=item['acceptance'], reference=item['reference'])
    return result


def inspect_profile(root, policy, archives, trees):
    profile = policy['profiles'][PROFILE]
    expected = set(profile['roles'])
    if (set(archives) | set(trees)) - expected:
        raise MaterialError('Selection is not part of this profile')
    absent = sorted(role for role in expected
                    if role not in policy['artifacts'] or role not in archives or role not in trees)
    if absent:
        return {'status': 'unavailable_profile_inputs', 'profile_ready': False,
                'missing_roles': absent, 'exit_code': 1}
    results = [inspect_material(root, policy, role, archives[role], trees[role])
               for role in profile['roles']]
    return {'status': 'published_materials_checked_not_execution_binding',
            'profile_ready': False, 'materials': results, 'exit_code': 1}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive', action='append', default=[], metavar='ROLE=PATH')
    parser.add_argument('--tree', action='append', default=[], metavar='ROLE=PATH')
    parser.add_argument('--check-material', metavar='ROLE')
    parser.add_argument('--build-from', metavar='SELECTIONS_JSON')
    parser.add_argument('--workspace', metavar='NEW_PROJECT_BUILD_DIRECTORY')
    parser.add_argument('--check-hook-context', metavar='CURRENT_HOOK_CONTEXT')
    parser.add_argument('--context-sha256', metavar='COMPILED_CONTEXT_BINDING')
    parser.add_argument('--hook', choices=('setup', 'rust_api'))
    args = parser.parse_args()
    builder = None
    try:
        if sys.platform != 'darwin' or platform.machine() != 'arm64':
            raise MaterialError('Only the macOS ARM64 managed host is supported')
        policy = policy_from_repository(REPOSITORY)
        archives, trees = selections(args.archive), selections(args.tree)
        if args.check_hook_context:
            if (not args.context_sha256 or not args.hook or args.build_from
                    or args.workspace or args.check_material or archives or trees):
                raise MaterialError('Hook check requires only its current compiled binding')
            from android_hook_environment import check_hook_context
            result = check_hook_context(args.check_hook_context, args.context_sha256,
                                        args.hook, REPOSITORY, policy)
            result['exit_code'] = 0
        elif args.context_sha256 or args.hook:
            raise MaterialError('A hook binding applies only to hook context checks')
        elif args.build_from:
            if not args.workspace or args.check_material or archives or trees:
                raise MaterialError('Build mode requires only selections and a fresh workspace')
            if set(policy['profiles'][PROFILE]['roles']) - set(policy['artifacts']) != {
                    'pub_flutter_tools', 'pub_app', 'pub_distributor'}:
                raise MaterialError('Managed profile is missing required tool acceptance anchors')
            for item in policy['artifacts'].values():
                version = configured_version(REPOSITORY, item['selector'])
                if version is not None and version != item['version']:
                    raise MaterialError('Acceptance object disagrees with canonical tool version')
            from android_build_profile import ManagedAndroidBuild, read_selections
            selected = read_selections(args.build_from, policy)
            builder = ManagedAndroidBuild(REPOSITORY, policy, selected, args.workspace)
            result = builder.build()
            result['exit_code'] = 0
        elif args.workspace:
            raise MaterialError('A writable workspace requires explicit build mode')
        elif args.check_material:
            role = args.check_material
            if set(archives) != {role} or set(trees) != {role}:
                raise MaterialError('Material inspection requires exactly its archive and tree')
            result = inspect_material(REPOSITORY, policy, role, archives[role], trees[role])
            result['exit_code'] = 0
        else:
            result = inspect_profile(REPOSITORY, policy, archives, trees)
    except (ValueError, OSError, configparser.Error, subprocess.CalledProcessError,
            tarfile.TarError, zipfile.BadZipFile) as error:
        result = {'status': 'rejected_input', 'profile_ready': False,
                  'reason': str(error), 'kind': type(error).__name__, 'exit_code': 2}
        if builder is not None:
            builder.results.update(result)
            builder.record()
            result['workspace_retained'] = str(builder.root)
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return result['exit_code']


if __name__ == '__main__':
    sys.exit(main())
