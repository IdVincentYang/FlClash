#!/usr/bin/env python3
"""Restore the L1-T03 core from its public base and checked-in source carrier."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

SUBMODULE = 'core/Clash.Meta'
CARRIER = 'core/patches/l1_t03'


def git(root, *args, data=None, env=None, check=True):
    result = subprocess.run(['git', '-C', str(root), *args], input=data,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            env=env, check=False)
    if check and result.returncode:
        raise RuntimeError(f'git {args[0]} failed ({result.returncode})')
    return result


def value(root, *args, **kwargs):
    return git(root, *args, **kwargs).stdout.decode('utf-8').strip()


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def canonical_source(source):
    if source.startswith('git@github.com:'):
        return 'https://github.com/' + source.split(':', 1)[1]
    return source.rstrip('/')


def source_inputs(root):
    inputs = [root / '.gitmodules', Path(__file__).resolve(),
              root / CARRIER / 'manifest.json', root / CARRIER / 'source.patch',
              root / CARRIER / 'commit.txt']
    for repo in (root, root / SUBMODULE):
        if not (repo / '.git').exists():
            continue
        for name in ('config', 'index'):
            path = Path(value(repo, 'rev-parse', '--git-path', name))
            if not path.is_absolute():
                path = repo / path
            if path.is_file():
                inputs.append(path.resolve())
        config = git(repo, 'config', '--show-origin', '--name-only', '--get-regexp',
                     r'^(url\..*\.insteadof|submodule\..*\.url)$', check=False)
        for line in config.stdout.decode('utf-8').splitlines():
            origin = line.split('\t', 1)[0]
            if origin.startswith('file:'):
                path = Path(origin[5:])
                if not path.is_absolute():
                    path = repo / path
                if path.is_file():
                    inputs.append(path.resolve())
    return sorted(str(path.resolve()) for path in set(inputs))


def tree_from_working_copy(repo, start, env, index):
    ignored = git(repo, 'ls-files', '--others', '--ignored', '--exclude-standard', '-z').stdout.decode().split('\0')
    if any(Path(path).suffix.lower() in ('.go', '.c', '.h', '.s', '.syso') or Path(path).name in ('go.mod', 'go.sum')
           for path in ignored if path):
        raise RuntimeError('Ignored build source is outside the source carrier')
    local = dict(env, GIT_INDEX_FILE=str(index))
    git(repo, 'read-tree', start, env=local)
    git(repo, 'add', '--all', '--', '.', env=local)
    return value(repo, 'write-tree', env=local)


def restore(args):
    root = args.root.resolve()
    material = root / CARRIER
    manifest = json.loads((material / 'manifest.json').read_text(encoding='utf-8'))
    patch = material / 'source.patch'
    commit = material / 'commit.txt'
    if digest(patch) != manifest['patch_sha256'] or digest(commit) != manifest['commit_sha256']:
        raise RuntimeError('Source carrier digest mismatch')
    configured = value(root, 'config', '-f', '.gitmodules', '--get', 'submodule.core/Clash.Meta.url')
    if canonical_source(configured) != canonical_source(manifest['repository']):
        raise RuntimeError('Configured submodule source differs from the manifest')
    parent_entry = value(root, 'ls-files', '--stage', '--', SUBMODULE).split()
    if len(parent_entry) < 2 or parent_entry[0] != '160000' or parent_entry[1] != manifest['commit']:
        raise RuntimeError('Parent gitlink differs from the source carrier')
    repo = root / SUBMODULE
    initialized = (repo / '.git').exists()
    if not initialized:
        if args.check:
            raise RuntimeError('Core is not initialized; run restore without --check first')
        repo.mkdir(parents=True, exist_ok=True)
        if any(repo.iterdir()):
            raise RuntimeError('Refusing to initialize a nonempty core directory')
        git(root, 'submodule', 'init', '--', SUBMODULE)
        git(root, 'init', str(repo))
    base = manifest['base_commit']
    if git(repo, 'cat-file', '-e', base + '^{commit}', check=False).returncode:
        if args.check:
            raise RuntimeError('Public base missing; run restore without --check first')
        override = git(root, 'config', '--get', 'submodule.core/Clash.Meta.url', check=False).stdout.decode().strip()
        source = str(args.base_repository.resolve()) if args.base_repository else canonical_source(override or configured)
        git(repo, 'fetch', '--no-tags', '--depth=1', '--', source, base)
    if value(repo, 'rev-parse', base + '^{tree}') != manifest['base_tree']:
        raise RuntimeError('Public base tree mismatch')
    with tempfile.TemporaryDirectory(prefix='flclash-core-restore-') as temporary:
        temp = Path(temporary)
        env = dict(os.environ)
        if args.check:
            objects = Path(value(repo, 'rev-parse', '--git-path', 'objects'))
            if not objects.is_absolute():
                objects = repo / objects
            (temp / 'objects').mkdir()
            env.update(GIT_OBJECT_DIRECTORY=str(temp / 'objects'),
                       GIT_ALTERNATE_OBJECT_DIRECTORIES=str(objects.resolve()))
        index_env = dict(env, GIT_INDEX_FILE=str(temp / 'patch-index'))
        git(repo, 'read-tree', base, env=index_env)
        git(repo, 'apply', '--cached', '--binary', '--whitespace=error', str(patch), env=index_env)
        if value(repo, 'write-tree', env=index_env) != manifest['tree']:
            raise RuntimeError('Reconstructed tree mismatch')
        for path, expected in manifest['changed_blobs'].items():
            blob = git(repo, 'rev-parse', manifest['tree'] + ':' + path, env=env, check=False)
            actual = blob.stdout.decode().strip() if not blob.returncode else None
            if actual != expected:
                raise RuntimeError('Changed blob mismatch: ' + path)
        raw = commit.read_bytes()
        headers = raw.split(b'\n\n', 1)[0].splitlines()
        if [line[7:].decode() for line in headers if line.startswith(b'parent ')] != [base]:
            raise RuntimeError('Commit must have the public base as its sole parent')
        if b'tree ' + manifest['tree'].encode() not in headers:
            raise RuntimeError('Commit tree header mismatch')
        options = ['hash-object', '-t', 'commit']
        if not args.check:
            options.append('-w')
        if value(repo, *options, '--stdin', data=raw, env=env) != manifest['commit']:
            raise RuntimeError('Reconstructed commit mismatch')
        head = git(repo, 'rev-parse', '--verify', 'HEAD', check=False).stdout.decode().strip()
        if head:
            actual = tree_from_working_copy(repo, 'HEAD', env, temp / 'working-index')
            if actual != manifest['tree']:
                if args.check:
                    raise RuntimeError('Working core differs from the source carrier')
                status = value(repo, 'status', '--porcelain', '--untracked-files=all')
                if status or actual != manifest['base_tree']:
                    raise RuntimeError('Refusing to overwrite existing core changes')
                git(repo, 'checkout', '--detach', manifest['commit'])
        elif args.check:
            raise RuntimeError('Core has no checkout')
        else:
            git(repo, 'checkout', '--detach', manifest['commit'])
    if not initialized:
        git(root, 'submodule', 'absorbgitdirs', '--', SUBMODULE)
    return {'commit': manifest['commit'], 'tree': manifest['tree'],
            'head': value(repo, 'rev-parse', 'HEAD'), 'inputs': source_inputs(root)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--base-repository', type=Path)
    args = parser.parse_args()
    try:
        print(json.dumps(restore(args), sort_keys=True))
    except (OSError, ValueError, RuntimeError, KeyError) as error:
        print('Core source verification failed: ' + str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
