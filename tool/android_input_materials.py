"""Read selected, hash-pinned archives and compare their unmodified payloads."""

from contextlib import contextmanager, nullcontext
import ctypes
import errno
import hashlib
import ntpath
import os
from pathlib import Path
import posixpath
import secrets
import stat
import sys
import tarfile
import zipfile


MAX_ENTRIES = 200000
MAX_EXPANDED = 16 * 1024**3
CHUNK = 1024 * 1024

_clone_library = ctypes.CDLL(None, use_errno=True) if sys.platform == 'darwin' else None
_clone_file = getattr(_clone_library, 'fclonefileat', None)
if _clone_file is not None:
    _clone_file.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_char_p, ctypes.c_int]
    _clone_file.restype = ctypes.c_int


class MaterialError(ValueError):
    pass


def relative(value, allow_empty=False):
    if (not isinstance(value, str) or '\\' in value or '\0' in value
            or value.startswith('/') or ntpath.splitdrive(value)[0]):
        raise MaterialError('Expected a root-relative archive path')
    if not value and allow_empty:
        return ''
    parts = value.split('/')
    if not value or len(parts) > 128 or any(p in ('', '.', '..') for p in parts):
        raise MaterialError('Noncanonical path or traversal')
    return value


def hash_stream(stream, expected_size):
    digest = hashlib.sha256()
    size = 0
    while block := stream.read(min(CHUNK, expected_size - size + 1)):
        size += len(block)
        if size > expected_size:
            raise MaterialError('Material grew beyond the accepted size')
        digest.update(block)
    if size != expected_size:
        raise MaterialError('Material size differs from the accepted object')
    return digest.hexdigest()


class SelectedRoot:
    def __init__(self, path, directory):
        chosen = Path(path).expanduser()
        if chosen.is_symlink():
            raise MaterialError('Select the actual root, not a symbolic link')
        chosen = chosen.resolve(strict=True)
        if not hasattr(os, 'O_NOFOLLOW') or os.open not in os.supports_dir_fd:
            raise MaterialError('Safe selected-root reads require POSIX support')
        flags = os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK
        self.fd = os.open(chosen, flags | (os.O_DIRECTORY if directory else 0))
        self.directory = directory
        mode = os.fstat(self.fd).st_mode
        if not (stat.S_ISDIR(mode) if directory else stat.S_ISREG(mode)):
            self.close()
            raise MaterialError('Selected root has the wrong type')

    def close(self):
        os.close(self.fd)

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self.close()

    @contextmanager
    def parent(self, name):
        if not self.directory:
            raise MaterialError('A selected file grants no sibling access')
        parts = relative(name).split('/')
        opened = []
        current = self.fd
        try:
            for part in parts[:-1]:
                current = os.open(part, os.O_RDONLY | os.O_DIRECTORY
                                  | os.O_NOFOLLOW, dir_fd=current)
                opened.append(current)
            yield current, parts[-1]
        finally:
            for fd in reversed(opened):
                os.close(fd)

    @contextmanager
    def file(self, name=None):
        if self.directory:
            with self.parent(name) as (parent, leaf):
                fd = os.open(leaf, os.O_RDONLY | os.O_NOFOLLOW
                             | os.O_NONBLOCK, dir_fd=parent)
        else:
            if name is not None:
                raise MaterialError('A selected file grants no sibling access')
            fd = os.dup(self.fd)
        try:
            if not stat.S_ISREG(os.fstat(fd).st_mode):
                raise MaterialError('Expected a regular payload file')
            with os.fdopen(fd, 'rb', closefd=False) as stream:
                stream.seek(0)
                yield stream
        finally:
            os.close(fd)

    @contextmanager
    def directory_at(self, name):
        with self.parent(name) as (parent, leaf):
            fd = os.open(leaf, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent)
        child = object.__new__(SelectedRoot)
        child.fd = fd
        child.directory = True
        try:
            yield child
        finally:
            child.close()

    def inventory(self):
        if not self.directory:
            raise MaterialError('Expected a selected directory')
        found = {}

        def walk(fd, prefix):
            with os.scandir(fd) as entries:
                for entry in entries:
                    name = prefix + entry.name
                    relative(name)
                    metadata = entry.stat(follow_symlinks=False)
                    mode = metadata.st_mode
                    kind = ('directory' if stat.S_ISDIR(mode) else
                            'symlink' if stat.S_ISLNK(mode) else
                            'file' if stat.S_ISREG(mode) else 'special')
                    found[name] = {'kind': kind, 'size': metadata.st_size,
                                   'mode': stat.S_IMODE(mode),
                                   'inode': (metadata.st_dev, metadata.st_ino)}
                    if len(found) > MAX_ENTRIES:
                        raise MaterialError('Installed payload exceeds the entry limit')
                    if kind == 'directory':
                        child = os.open(entry.name, os.O_RDONLY | os.O_DIRECTORY
                                        | os.O_NOFOLLOW, dir_fd=fd)
                        try:
                            walk(child, name + '/')
                        finally:
                            os.close(child)
                    elif kind == 'symlink':
                        found[name]['target'] = os.readlink(entry.name, dir_fd=fd)

        walk(self.fd, '')
        return found


def payload_name(name, prefix):
    name = relative(name.rstrip('/'))
    if not prefix:
        return name
    if name == prefix:
        return ''
    if not name.startswith(prefix + '/'):
        raise MaterialError('Member is outside the accepted archive prefix')
    return name[len(prefix) + 1:]


def link_target(name, target, hardlink, prefix):
    if (not target or '\\' in target or '\0' in target
            or target.startswith('/') or ntpath.splitdrive(target)[0]):
        raise MaterialError('Invalid archive link')
    if hardlink:
        return payload_name(target, prefix)
    result = posixpath.normpath(posixpath.join(posixpath.dirname(name), target))
    if result == '.':
        return ''
    return relative(result, allow_empty=True)


def read_archive(path, specification):
    prefix = relative(specification['prefix'], allow_empty=True)
    index = {}
    expanded = 0
    seen = set()

    def add(raw_name, kind, mode, size=0, stream=None, target=None):
        nonlocal expanded
        canonical = relative(raw_name.rstrip('/'))
        if canonical in seen or len(seen) >= MAX_ENTRIES:
            raise MaterialError('Duplicate or excessive archive members')
        seen.add(canonical)
        if kind == 'file':
            expanded += size
            if size < 0 or expanded > MAX_EXPANDED:
                raise MaterialError('Archive exceeds the expanded-size limit')
        if prefix and canonical != prefix and not canonical.startswith(prefix + '/'):
            return
        name = payload_name(raw_name, prefix)
        if not name:
            if kind != 'directory':
                raise MaterialError('Archive prefix is not a directory')
            return
        if name in index:
            raise MaterialError('Duplicate archive payload member')
        if len(index) >= MAX_ENTRIES:
            raise MaterialError('Archive exceeds the entry limit')
        item = {'kind': kind, 'mode': mode & 0o777}
        if kind == 'file':
            item.update(size=size, sha256=hash_stream(stream, size))
        elif kind in ('symlink', 'hardlink'):
            item.update(target=target,
                        destination=link_target(name, target, kind == 'hardlink', prefix))
        index[name] = item

    with SelectedRoot(path, directory=False) as selected, selected.file() as stream:
        size = os.fstat(stream.fileno()).st_size
        if size != specification['size']:
            raise MaterialError('Archive size differs from the accepted object')
        if hash_stream(stream, size) != specification['sha256']:
            raise MaterialError('Archive digest differs from the accepted object')
        stream.seek(0)
        if specification['format'] == 'file':
            if prefix:
                raise MaterialError('A standalone payload cannot use an archive prefix')
            add(relative(specification['payload']), 'file', specification.get('mode', 0o644),
                size, stream)
        elif specification['format'] == 'zip':
            with zipfile.ZipFile(stream) as archive:
                for info in archive.infolist():
                    if info.orig_filename != info.filename or info.flag_bits & 1:
                        raise MaterialError('NUL or encrypted archive member')
                    mode = info.external_attr >> 16
                    if info.is_dir():
                        add(info.filename, 'directory', mode)
                    elif stat.S_ISLNK(mode):
                        if info.file_size > 4096:
                            raise MaterialError('Oversized archive link')
                        target = archive.read(info).decode('utf-8')
                        add(info.filename, 'symlink', mode, target=target)
                    elif stat.S_IFMT(mode) in (0, stat.S_IFREG):
                        with archive.open(info) as member:
                            add(info.filename, 'file', mode, info.file_size, member)
                    else:
                        raise MaterialError('Special archive member')
        elif specification['format'] in ('tar.gz', 'tar.xz'):
            with tarfile.open(fileobj=stream, mode='r|*') as archive:
                for info in archive:
                    if info.isdir():
                        add(info.name, 'directory', info.mode)
                    elif info.isfile():
                        with archive.extractfile(info) as member:
                            add(info.name, 'file', info.mode, info.size, member)
                    elif info.issym() or info.islnk():
                        add(info.name, 'symlink' if info.issym() else 'hardlink',
                            info.mode, target=info.linkname)
                    else:
                        raise MaterialError('Special archive member')
        else:
            raise MaterialError('Unsupported accepted archive format')

    for name in list(index):
        parent = posixpath.dirname(name)
        while parent:
            item = index.setdefault(parent, {'kind': 'directory', 'mode': None})
            if item['kind'] != 'directory':
                raise MaterialError('Archive member writes through a non-directory')
            parent = posixpath.dirname(parent)
    if len(index) > MAX_ENTRIES:
        raise MaterialError('Archive exceeds the entry limit')
    if not any(item['kind'] == 'file' for item in index.values()):
        raise MaterialError('Accepted component prefix has no payload files')
    for name, item in index.items():
        if item['kind'] in ('symlink', 'hardlink'):
            resolve_link(name, index)
    return index


def resolve_link(name, index):
    pending = name.split('/') if name else []
    resolved = []
    hops = 0
    while pending:
        resolved.append(pending.pop(0))
        current = '/'.join(resolved)
        item = index.get(current)
        if item is None:
            raise MaterialError('Archive link has no accepted destination')
        if item['kind'] in ('symlink', 'hardlink'):
            hops += 1
            if hops > 64:
                raise MaterialError('Cyclic or excessive archive links')
            target = item['destination']
            pending = (target.split('/') if target else []) + pending
            resolved = []
        elif pending and item['kind'] != 'directory':
            raise MaterialError('Archive link traverses a regular file')
    return '/'.join(resolved)


def compare_tree(path, index, complete=True):
    selected = nullcontext(path) if isinstance(path, SelectedRoot) else SelectedRoot(path, directory=True)
    with selected as root:
        actual = root.inventory()
        if not set(index) <= actual.keys():
            raise MaterialError('Installed payload has missing entries')
        if complete and set(index) != actual.keys():
            raise MaterialError('Installed tree contains unaccepted entries')
        for name, expected in index.items():
            observed = actual[name]
            kind = expected['kind']
            if kind == 'hardlink':
                destination = resolve_link(name, index)
                if observed['kind'] != 'file' or observed['inode'] != actual[destination]['inode']:
                    raise MaterialError('Installed hardlink differs from the archive')
                continue
            if observed['kind'] != kind:
                raise MaterialError('Installed payload type differs from the archive')
            if kind == 'symlink':
                if observed['target'] != expected['target']:
                    raise MaterialError('Installed symbolic link differs from the archive')
            elif kind == 'file':
                with root.file(name) as stream:
                    if os.fstat(stream.fileno()).st_size != expected['size']:
                        raise MaterialError(f'Installed file size differs from accepted payload: {name}')
                    if hash_stream(stream, expected['size']) != expected['sha256']:
                        raise MaterialError(f'Installed file differs from accepted payload: {name}')
                if (observed['mode'] & 0o7111) != (expected['mode'] & 0o111):
                    raise MaterialError('Installed executable mode differs from the archive')
        return {'entries_checked': len(index), 'complete_tree': complete,
                'publisher_authentication': 'not_assessed_here',
                'generation_causality': 'not_proven'}


def write_verified_file(root, name, stream, expected):
    with root.parent(name) as (fd, leaf):
        output = os.open(leaf, os.O_WRONLY | os.O_CREAT | os.O_EXCL
                         | os.O_NOFOLLOW, 0o600, dir_fd=fd)
    try:
        digest = hashlib.sha256()
        size = 0
        with os.fdopen(output, 'wb', closefd=False) as target:
            while block := stream.read(min(CHUNK, expected['size'] - size + 1)):
                size += len(block)
                if size > expected['size']:
                    raise MaterialError('Member grew during materialization')
                target.write(block)
                digest.update(block)
        if size != expected['size'] or digest.hexdigest() != expected['sha256']:
            raise MaterialError('Member changed during materialization')
        os.fchmod(output, expected['mode'] | 0o600)
    finally:
        os.close(output)


def clone_verified_file(root, name, stream, expected):
    if _clone_file is None:
        write_verified_file(root, name, stream, expected)
        return False
    with root.parent(name) as (parent, leaf):
        status = _clone_file(stream.fileno(), parent, os.fsencode(leaf), 0)
        if status:
            code = ctypes.get_errno()
            if code not in (errno.ENOTSUP, errno.EXDEV, errno.ENOSYS, errno.EINVAL):
                raise OSError(code, os.strerror(code))
            try:
                os.stat(leaf, dir_fd=parent, follow_symlinks=False)
            except FileNotFoundError:
                pass
            else:
                raise MaterialError('Failed clone left an owned output; retained')
    if status:
        stream.seek(0)
        write_verified_file(root, name, stream, expected)
        return False
    with root.file(name) as output:
        source_stat, output_stat = os.fstat(stream.fileno()), os.fstat(output.fileno())
        if (source_stat.st_dev, source_stat.st_ino) == (output_stat.st_dev, output_stat.st_ino):
            raise MaterialError('Tool copy unexpectedly shares the source inode')
        if hash_stream(output, expected['size']) != expected['sha256']:
            raise MaterialError('Cloned payload differs from accepted bytes')
        os.fchmod(output.fileno(), expected['mode'] | 0o600)
    return True


def materialize_tree(source_path, index, destination):
    destination = Path(destination).absolute()
    if destination.exists() or destination.is_symlink():
        raise FileExistsError('Tool destination already exists')
    cloned = 0
    with SelectedRoot(source_path, True) as source:
        compare_tree(source, index, complete=False)
        with SelectedRoot(destination.parent, True) as parent:
            os.mkdir(destination.name, 0o700, dir_fd=parent.fd)
        with SelectedRoot(destination, True) as target:
            for name, item in sorted(index.items(), key=lambda pair: pair[0].count('/')):
                if item['kind'] == 'directory':
                    with target.parent(name) as (fd, leaf):
                        os.mkdir(leaf, 0o755, dir_fd=fd)
            for name, item in index.items():
                if item['kind'] == 'file':
                    with source.file(name) as stream:
                        cloned += clone_verified_file(target, name, stream, item)
            for name, item in index.items():
                if item['kind'] == 'hardlink':
                    link = resolve_link(name, index)
                    if index[link]['kind'] != 'file':
                        raise MaterialError('Hardlink destination is not a regular file')
                    with target.parent(link) as (src_fd, src_leaf), target.parent(name) as (dst_fd, dst_leaf):
                        os.link(src_leaf, dst_leaf, src_dir_fd=src_fd,
                                dst_dir_fd=dst_fd, follow_symlinks=False)
            for name, item in index.items():
                if item['kind'] == 'symlink':
                    with target.parent(name) as (fd, leaf):
                        os.symlink(item['target'], leaf, dir_fd=fd)
    result = compare_tree(destination, index)
    result['copy_on_write_files'] = cloned
    return result


def materialize_archive(path, specification, destination):
    index = read_archive(path, specification)
    destination = Path(destination).absolute()
    with SelectedRoot(path, directory=False) as selected, selected.file() as source:
        if hash_stream(source, specification['size']) != specification['sha256']:
            raise MaterialError('Archive changed before materialization')
        source.seek(0)
        with SelectedRoot(destination.parent, directory=True) as parent:
            os.mkdir(destination.name, 0o700, dir_fd=parent.fd)
        with SelectedRoot(destination, directory=True) as root:
            for name, item in sorted(index.items(), key=lambda pair: pair[0].count('/')):
                if item['kind'] == 'directory':
                    with root.parent(name) as (fd, leaf):
                        os.mkdir(leaf, 0o755, dir_fd=fd)

            copied = set()

            def copy(raw_name, stream):
                canonical = relative(raw_name.rstrip('/'))
                prefix = specification['prefix']
                if prefix and not canonical.startswith(prefix + '/'):
                    return
                name = payload_name(raw_name, prefix)
                expected = index.get(name)
                if expected is None or expected['kind'] != 'file' or name in copied:
                    raise MaterialError('Materialization differs from accepted members')
                write_verified_file(root, name, stream, expected)
                copied.add(name)

            if specification['format'] == 'file':
                copy(specification['payload'], source)
            elif specification['format'] == 'zip':
                with zipfile.ZipFile(source) as archive:
                    for info in archive.infolist():
                        if not info.is_dir() and not stat.S_ISLNK(info.external_attr >> 16):
                            with archive.open(info) as member:
                                copy(info.filename, member)
            else:
                with tarfile.open(fileobj=source, mode='r|*') as archive:
                    for info in archive:
                        if info.isfile():
                            with archive.extractfile(info) as member:
                                copy(info.name, member)
            if copied != {name for name, item in index.items() if item['kind'] == 'file'}:
                raise MaterialError('Materialization omits accepted members')
            for name, item in index.items():
                if item['kind'] == 'hardlink':
                    target = resolve_link(name, index)
                    if index[target]['kind'] != 'file':
                        raise MaterialError('Hardlink destination is not a regular file')
                    with root.parent(target) as (src_fd, src_leaf), root.parent(name) as (dst_fd, dst_leaf):
                        os.link(src_leaf, dst_leaf, src_dir_fd=src_fd,
                                dst_dir_fd=dst_fd, follow_symlinks=False)
            for name, item in index.items():
                if item['kind'] == 'symlink':
                    with root.parent(name) as (fd, leaf):
                        os.symlink(item['target'], leaf, dir_fd=fd)
    return compare_tree(destination, index)


def merge_materialized(source, index, target_root, prefix='', replacements=None):
    prefix = relative(prefix, allow_empty=True)
    replacements = replacements or {}
    mapped = {}
    for name, item in index.items():
        destination = prefix + '/' + name if prefix else name
        mapped[destination] = dict(item)
        if item['kind'] in ('symlink', 'hardlink'):
            end = item['destination']
            mapped[destination]['destination'] = '/'.join(p for p in (prefix, end) if p)
        parent = posixpath.dirname(destination)
        while parent:
            mapped.setdefault(parent, {'kind': 'directory', 'mode': None})
            parent = posixpath.dirname(parent)
    with SelectedRoot(source, directory=True) as selected, SelectedRoot(target_root, directory=True) as target:
        compare_tree(selected, index)
        for name, item in sorted(mapped.items(), key=lambda pair: pair[0].count('/')):
            if item['kind'] == 'directory':
                with target.parent(name) as (fd, leaf):
                    try:
                        os.mkdir(leaf, 0o755, dir_fd=fd)
                    except FileExistsError:
                        with target.directory_at(name):
                            pass
        for name, item in index.items():
            destination = prefix + '/' + name if prefix else name
            if item['kind'] == 'file':
                try:
                    with target.file(destination) as existing:
                        mode = os.fstat(existing.fileno()).st_mode
                        before = replacements.get(destination, item)
                        if (before['kind'] != 'file'
                                or hash_stream(existing, before['size']) != before['sha256']
                                or mode & 0o7111 != before['mode'] & 0o111):
                            raise MaterialError('Component collides with different accepted payload')
                    if destination in replacements:
                        temporary = destination + '.' + secrets.token_hex(8) + '.tmp'
                        with selected.file(name) as stream:
                            clone_verified_file(target, temporary, stream, item)
                        with target.parent(temporary) as (src_fd, src_leaf), target.parent(destination) as (dst_fd, dst_leaf):
                            os.rename(src_leaf, dst_leaf, src_dir_fd=src_fd, dst_dir_fd=dst_fd)
                except FileNotFoundError:
                    if destination in replacements:
                        raise MaterialError('Accepted predecessor for component replacement is missing')
                    with selected.file(name) as stream:
                        clone_verified_file(target, destination, stream, item)
        for name, item in index.items():
            destination = prefix + '/' + name if prefix else name
            if item['kind'] in ('hardlink', 'symlink'):
                with target.parent(destination) as (fd, leaf):
                    try:
                        if item['kind'] == 'symlink':
                            os.symlink(item['target'], leaf, dir_fd=fd)
                        else:
                            end = resolve_link(name, index)
                            end = prefix + '/' + end if prefix else end
                            with target.parent(end) as (src_fd, src_leaf):
                                os.link(src_leaf, leaf, src_dir_fd=src_fd,
                                        dst_dir_fd=fd, follow_symlinks=False)
                    except FileExistsError:
                        if item['kind'] == 'symlink' and os.readlink(leaf, dir_fd=fd) != item['target']:
                            raise MaterialError('Component link collides with existing payload')
        compare_tree(target, mapped, complete=False)
    return mapped
