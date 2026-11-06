"""Export and inspect a fixed Git source object without using its local config."""

import configparser
import hashlib
import os
from pathlib import Path
import re
import subprocess

from android_input_materials import (
    MAX_ENTRIES,
    MAX_EXPANDED,
    MaterialError,
    SelectedRoot,
    materialize_archive,
    read_archive,
    relative,
)


def git_environment(home):
    return {'PATH': '/usr/bin:/bin', 'HOME': str(home), 'LC_ALL': 'C',
            'GIT_CONFIG_NOSYSTEM': '1', 'GIT_CONFIG_GLOBAL': '/dev/null',
            'GIT_TERMINAL_PROMPT': '0', 'GIT_NO_REPLACE_OBJECTS': '1'}


def validate_repository(repository, commit):
    with SelectedRoot(repository, directory=True) as selected:
        inventory = selected.inventory()
        if (any(item['kind'] not in ('directory', 'file') for item in inventory.values())
                or 'objects/info/alternates' in inventory
                or 'objects/info/http-alternates' in inventory
                or any(name.startswith('refs/replace/') for name in inventory)):
            raise MaterialError('Fixed Git repository contains indirection')
        with selected.file('config') as stream:
            raw = stream.read(65537)
        if len(raw) > 65536:
            raise MaterialError('Excessive fixed Git repository configuration')
        config = configparser.ConfigParser(interpolation=None, strict=True)
        config.read_string(raw.decode('utf-8'))
        safe_core = {'repositoryformatversion': {'0'}, 'filemode': {'true', 'false'},
                     'bare': {'true', 'false'}, 'logallrefupdates': {'true', 'false'},
                     'ignorecase': {'true', 'false'}, 'precomposeunicode': {'true', 'false'}}
        if config.defaults() or set(config.sections()) - {'core', 'remote "origin"'} or 'core' not in config:
            raise MaterialError('Unaccepted fixed Git repository configuration')
        if any(key not in safe_core or value not in safe_core[key]
               for key, value in config['core'].items()):
            raise MaterialError('Unaccepted fixed Git core configuration')
        if ('remote "origin"' in config
                and set(config['remote "origin"']) - {'url', 'fetch'}):
            raise MaterialError('Unaccepted fixed Git remote configuration')
        if 'shallow' in inventory:
            with selected.file('shallow') as stream:
                if stream.read(82) != (commit + '\n').encode():
                    raise MaterialError('Unexpected fixed Git shallow boundary')


def export_objects(object_directory, commit, destination):
    if not isinstance(commit, str) or not re.fullmatch('[0-9a-f]{40}', commit):
        raise MaterialError('Expected one accepted Git commit')
    object_directory = Path(object_directory).absolute()
    with SelectedRoot(object_directory, directory=True) as selected:
        inventory = selected.inventory()
        if ('info/alternates' in inventory or 'info/http-alternates' in inventory
                or any(item['kind'] not in ('directory', 'file')
                       for item in inventory.values())):
            raise MaterialError('Cached Git objects contain indirection')
    destination = Path(destination).absolute()
    destination.mkdir(mode=0o700)
    repository = destination / 'source.git'
    home = destination / 'home'
    home.mkdir()
    env = git_environment(home)

    def run(arguments, source=False, **kwargs):
        child_env = dict(env)
        if source:
            child_env['GIT_OBJECT_DIRECTORY'] = str(object_directory)
        return subprocess.run(['/usr/bin/git', *arguments], env=child_env,
                              check=True, **kwargs)

    run(['-c', 'init.defaultBranch=accepted', 'init', '--bare', str(repository)],
        stdout=subprocess.DEVNULL)
    (repository / 'shallow').write_text(commit + '\n')
    listing = run(['--git-dir', str(repository), 'rev-list', '--objects',
                   '--no-object-names', commit], source=True, capture_output=True).stdout
    objects = listing.splitlines()
    if (not objects or len(objects) > MAX_ENTRIES
            or any(not re.fullmatch(b'[0-9a-f]{40}', item) for item in objects)):
        raise MaterialError('Unexpected fixed Git object closure')
    pack = destination / 'source.pack'
    with pack.open('xb') as output:
        run(['--git-dir', str(repository), 'pack-objects', '--stdout',
             '--no-reuse-delta', '--no-reuse-object'], source=True,
            input=listing, stdout=output)
    with pack.open('rb') as source:
        run(['--git-dir', str(repository), 'index-pack', '--stdin'],
            stdin=source, stdout=subprocess.DEVNULL)
    run(['--git-dir', str(repository), 'update-ref', 'refs/heads/accepted', commit])
    run(['--git-dir', str(repository), 'fsck', '--full', '--no-reflogs'],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    return repository


def source_index(repository, commit, home):
    if not re.fullmatch('[0-9a-f]{40}', commit):
        raise MaterialError('Expected one accepted Git commit')
    env = git_environment(home)
    command = ['/usr/bin/git', '--git-dir', str(repository)]
    validate_repository(repository, commit)
    subprocess.run([*command, 'fsck', '--full', '--no-reflogs'], env=env,
                   check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    listing = subprocess.run([*command, 'ls-tree', '-r', '-z', '--full-tree', commit],
                             env=env, check=True, capture_output=True).stdout
    entries = listing.rstrip(b'\0').split(b'\0')
    if not listing or len(entries) > MAX_ENTRIES:
        raise MaterialError('Excessive or empty Git source tree')
    index = {}
    expanded = 0
    process = subprocess.Popen([*command, 'cat-file', '--batch'], env=env,
                               stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE)
    try:
        for entry in entries:
            metadata, separator, raw_name = entry.partition(b'\t')
            parts = metadata.split(b' ')
            if (not separator or len(parts) != 3 or parts[1] != b'blob'
                    or parts[0] not in (b'100644', b'100755', b'120000')
                    or not re.fullmatch(b'[0-9a-f]{40}', parts[2])):
                raise MaterialError('Unsupported fixed Git tree entry')
            name = relative(raw_name.decode('utf-8'))
            if name in index:
                raise MaterialError('Duplicate fixed Git source entry')
            oid = parts[2]
            process.stdin.write(oid + b'\n')
            process.stdin.flush()
            header = process.stdout.readline(256).split()
            if (len(header) != 3 or header[:2] != [oid, b'blob']
                    or not header[2].isdigit()):
                raise MaterialError('Git source object is unavailable')
            size = int(header[2])
            expanded += size
            if expanded > MAX_EXPANDED or (parts[0] == b'120000' and size > 4096):
                raise MaterialError('Fixed Git source exceeds payload bounds')
            digest = hashlib.sha256()
            git_hash = hashlib.sha1(b'blob ' + str(size).encode() + b'\0')
            remaining = size
            target = bytearray()
            while remaining:
                block = process.stdout.read(min(1024 * 1024, remaining))
                if not block:
                    raise MaterialError('Truncated fixed Git source object')
                remaining -= len(block)
                digest.update(block)
                git_hash.update(block)
                if parts[0] == b'120000':
                    target.extend(block)
            if process.stdout.read(1) != b'\n' or git_hash.hexdigest().encode() != oid:
                raise MaterialError('Git source bytes disagree with accepted object')
            if parts[0] == b'120000':
                index[name] = {'kind': 'symlink', 'mode': 0o777,
                               'target': target.decode('utf-8')}
            else:
                index[name] = {'kind': 'file', 'size': size,
                               'sha256': digest.hexdigest(),
                               'mode': 0o755 if parts[0] == b'100755' else 0o644}
            parent = name.rpartition('/')[0]
            while parent:
                index.setdefault(parent, {'kind': 'directory', 'mode': None})
                parent = parent.rpartition('/')[0]
        process.stdin.close()
        if process.wait(timeout=30) != 0:
            raise MaterialError('Git source reader failed')
    finally:
        if process.poll() is None:
            process.terminate()
            process.wait(timeout=30)
        for stream in (process.stdin, process.stdout, process.stderr):
            stream.close()
    return index


def materialize_source(repository, commit, destination, home):
    destination = Path(destination).absolute()
    if destination.exists() or destination.is_symlink():
        raise FileExistsError('Git source destination already exists')
    expected = source_index(repository, commit, home)
    archive = destination.with_name(destination.name + '.tar.gz')
    env = git_environment(home)
    export_repository = destination.with_name(destination.name + '.export.git')
    subprocess.run(['/usr/bin/git', '-c', 'core.hooksPath=/dev/null', 'clone',
                    '--bare', '--no-hardlinks', str(repository), str(export_repository)],
                   env=env, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    (export_repository / 'info/attributes').write_text(
        '* -text -eol -ident -filter -working-tree-encoding -export-subst -export-ignore\n',
    )
    command = ['/usr/bin/git', '--git-dir', str(export_repository)]
    with archive.open('xb') as output:
        subprocess.run([*command, 'archive', '--format=tar.gz', '--prefix=source/', commit],
                       env=env, check=True, stdout=output)
    digest = hashlib.sha256()
    with archive.open('rb') as source:
        while block := source.read(1024 * 1024):
            digest.update(block)
    specification = {'format': 'tar.gz', 'prefix': 'source',
                     'size': archive.stat().st_size, 'sha256': digest.hexdigest()}
    observed = read_archive(archive, specification)
    if set(expected) != set(observed):
        raise MaterialError('Git archive changes fixed source membership')
    for name, item in expected.items():
        if (any(observed[name].get(key) != value for key, value in item.items()
                if value is not None and key != 'mode')
                or (item['mode'] is not None
                    and observed[name]['mode'] & 0o111 != item['mode'] & 0o111)):
            raise MaterialError(f'Git archive changes fixed source bytes or semantics: {name}')
    result = materialize_archive(archive, specification, destination)
    subprocess.run(['/usr/bin/git', '-c', 'core.hooksPath=/dev/null', 'clone',
                    '--bare', '--no-hardlinks', str(repository), str(destination / '.git')],
                   env=env, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    command = ['/usr/bin/git', '--git-dir', str(destination / '.git')]
    subprocess.run([*command, 'config', 'core.bare', 'false'], env=env, check=True)
    subprocess.run([*command, 'read-tree', commit], env=env, check=True)
    result.update(accepted_git_commit=commit, source_blob_bytes_checked=True,
                  archive_is_derived_not_publisher_reference=True)
    return result
