"""Replace only the configured publication tree using isolated native Git and SSH."""

import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import signal
import stat
import subprocess
import sys
import tempfile

from ci_release import ReleaseError, event_context, load_json, regular_file, require

GITHUB_KEY = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl'
GITHUB_FINGERPRINT = 'SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU'
TARGETS = {'tap': ('homebrew-tap', ''), 'fdroid': ('FlClash-fdroid-repo', 'tmp')}


class NativeTools:
    def __init__(self, git, ssh, lfs, context=None):
        self.git = regular_file(Path(git).resolve(strict=True))
        self.ssh = regular_file(Path(ssh).resolve(strict=True))
        self.lfs = regular_file(Path(lfs).resolve(strict=True)) if lfs else None
        for tool in (self.git, self.ssh, self.lfs):
            require(tool is None or os.access(tool, os.X_OK), 'Missing executable native tool')
        self.context = context or {'trust': 'Local controlled test tools; not cloud verification'}

    @classmethod
    def hosted(cls, environment):
        require(environment.get('GITHUB_ACTIONS') == 'true' and environment.get('RUNNER_OS') == 'Linux'
                and environment.get('ImageOS', '').startswith('ubuntu') and environment.get('ImageVersion'),
                'Native publication requires its declared GitHub-hosted Ubuntu context')
        return cls('/usr/bin/git', '/usr/bin/ssh', '/usr/bin/git-lfs', {
            'trust': 'GitHub-hosted preinstalled platform tools; observations are not independent authentication',
            'ImageOS': environment['ImageOS'], 'ImageVersion': environment['ImageVersion'],
            'ImageRelease': environment.get('ImageRelease', '')})


class PushSession:
    def __init__(self, parent, tools, *, local_remote=None, local_lfs=None):
        parent = Path(parent).absolute()
        require(parent.is_dir() and parent.resolve(strict=True) == parent, 'Publication parent must be canonical')
        self.root = Path(tempfile.mkdtemp(prefix='native-publication-', dir=parent))
        self.root.chmod(0o700)
        self.tools = tools
        self.local_remote = local_remote
        self.local_lfs = local_lfs
        if local_remote is not None:
            require(Path(local_remote).resolve(strict=True).is_relative_to(parent), 'Test remote leaves its owned parent')
        if local_lfs is not None:
            require(local_remote is not None and re.fullmatch(r'http://127\.0\.0\.1:[1-9][0-9]*/lfs', local_lfs), 'Unaccepted local LFS fixture receiver')
        self.children = []
        self.quiescent = True
        self.observations = dict(tools.context)
        for name in ('home', 'hooks', 'templates', 'bin'):
            (self.root / name).mkdir(mode=0o700)
        for name, tool in [('git', tools.git), ('ssh', tools.ssh), ('git-lfs', tools.lfs)]:
            if tool:
                (self.root / 'bin' / name).symlink_to(tool)
        self.environment = {'HOME': str(self.root / 'home'), 'XDG_CONFIG_HOME': str(self.root / 'home/.config'),
            'PATH': str(self.root / 'bin') + ':/usr/bin:/bin', 'LANG': 'C', 'LC_ALL': 'C',
            'GIT_CONFIG_NOSYSTEM': '1', 'GIT_CONFIG_SYSTEM': '/dev/null', 'GIT_CONFIG_GLOBAL': '/dev/null',
            'GIT_ATTR_NOSYSTEM': '1', 'GIT_CONFIG_COUNT': '0', 'GIT_EXEC_PATH': str(self.root / 'bin'),
            'GIT_TEMPLATE_DIR': str(self.root / 'templates'), 'GIT_TERMINAL_PROMPT': '0', 'GIT_ASKPASS': '/usr/bin/false',
            'GIT_SSH_VARIANT': 'ssh', 'GCM_INTERACTIVE': 'never', 'GIT_LFS_SKIP_SMUDGE': '1', 'PYTHONNOUSERSITE': '1',
            'GIT_ALLOW_PROTOCOL': 'file' if local_remote is not None else 'ssh'}
        self.config = {'core.hooksPath': str(self.root / 'hooks'), 'core.attributesFile': '/dev/null',
            'core.fsmonitor': 'false', 'core.autocrlf': 'false', 'credential.helper': '', 'commit.gpgsign': 'false',
            'user.name': 'chen08029', 'user.email': 'chen08209@gmail.com', 'filter.lfs.process': '',
            'filter.lfs.smudge': '', 'filter.lfs.clean': '', 'filter.lfs.required': 'false',
            'lfs.basictransfersonly': 'true', 'lfs.remote.autodetect': 'false', 'lfs.remote.searchall': 'false',
            'lfs.ssh.automultiplex': 'false', 'http.sslVerify': 'true'}
        self._config_environment()
        for name, tool, arguments in [('git', tools.git, ['--version']), ('ssh', tools.ssh, ['-V'])]:
            result = self.run([tool, *arguments], self.root)
            self.observations[name] = {'path': str(tool), 'sha256': hashlib.sha256(tool.read_bytes()).hexdigest(),
                                       'version': (result.stdout + result.stderr).decode().strip()}
        self.key = self.root / 'identity'
        self.known_hosts = self.root / 'known_hosts'

    def _config_environment(self):
        for key in list(self.environment):
            if key.startswith(('GIT_CONFIG_KEY_', 'GIT_CONFIG_VALUE_')):
                del self.environment[key]
        self.environment['GIT_CONFIG_COUNT'] = str(len(self.config))
        for index, (name, value) in enumerate(self.config.items()):
            self.environment['GIT_CONFIG_KEY_' + str(index)] = name
            self.environment['GIT_CONFIG_VALUE_' + str(index)] = value

    def run(self, command, cwd, *, input=None, allowed=(0,)):
        process = subprocess.Popen([str(arg) for arg in command], cwd=cwd, env=self.environment,
                                   stdin=subprocess.PIPE if input is not None else subprocess.DEVNULL,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
        self.children.append(process)
        timed_out = False
        try:
            try:
                stdout, stderr = process.communicate(input, timeout=180)
            except subprocess.TimeoutExpired:
                timed_out = True
                os.killpg(process.pid, signal.SIGKILL)
                stdout, stderr = process.communicate(timeout=10)
        except BaseException:
            self.quiescent = False
            raise
        try:
            os.killpg(process.pid, 0)
        except ProcessLookupError:
            pass
        except OSError:
            self.quiescent = False
            raise ReleaseError('Native child group exit is unproven; private workspace retained') from None
        else:
            self.quiescent = False
            raise ReleaseError('Native child group remains active; private workspace retained')
        require(not timed_out and process.returncode in allowed, 'Native publication command failed or timed out')
        return subprocess.CompletedProcess(command, process.returncode, stdout, stderr)

    def git(self, *arguments, allowed=(0,)):
        return self.run([self.tools.git, *arguments], self.root / 'clone', allowed=allowed)

    def prepare_identity(self, secret):
        actual = 'SHA256:' + base64.b64encode(hashlib.sha256(base64.b64decode(GITHUB_KEY.split()[1])).digest()).decode().rstrip('=')
        require(actual == GITHUB_FINGERPRINT, 'GitHub host key acceptance differs')
        require(isinstance(secret, str) and secret.startswith('-----BEGIN ') and 64 <= len(secret) <= 4 * 1024**2,
                'Missing publication key')
        self.known_hosts.write_text('github.com ' + GITHUB_KEY + '\n')
        self.known_hosts.chmod(0o600)
        self.key.write_text(secret if secret.endswith('\n') else secret + '\n')
        self.key.chmod(0o600)
        options = [self.tools.ssh, '-F', '/dev/null', '-i', self.key,
                   '-o', 'IdentityAgent=none', '-o', 'IdentitiesOnly=yes', '-o', 'BatchMode=yes',
                   '-o', 'StrictHostKeyChecking=yes', '-o', 'HostKeyAlgorithms=ssh-ed25519',
                   '-o', 'GlobalKnownHostsFile=/dev/null', '-o', 'UserKnownHostsFile=' + str(self.known_hosts),
                   '-o', 'ClearAllForwardings=yes', '-o', 'ForwardAgent=no', '-o', 'ControlMaster=no',
                   '-o', 'ControlPath=none', '-o', 'ProxyCommand=none', '-o', 'ProxyJump=none', '-o', 'PermitLocalCommand=no']
        self.environment['GIT_SSH_COMMAND'] = shlex.join(map(str, options))
        self.check_identity()
        self.run([*options, '-G', 'github.com'], self.root)

    def check_identity(self):
        require(self.known_hosts.read_text() == 'github.com ' + GITHUB_KEY + '\n'
                and stat.S_IMODE(self.key.stat().st_mode) == 0o600
                and stat.S_IMODE(self.known_hosts.stat().st_mode) == 0o600
                and stat.S_IMODE(self.root.stat().st_mode) == 0o700
                and not self.key.is_symlink() and not self.known_hosts.is_symlink(), 'Publication key material or host identity changed')

    def close(self):
        if self.quiescent and all(child.poll() is not None for child in self.children):
            shutil.rmtree(self.root)
        else:
            raise ReleaseError('Publication child exit is unproven; private workspace retained')


def source_files(source, target, version):
    source = Path(source).absolute()
    require(source.is_dir() and source.resolve(strict=True) == source, 'Noncanonical publication source')
    expected = {'Casks/flclash.rb'} if target == 'tap' else {'FlClash-' + version + '-android-arm64-v8a.apk'}
    result = {}
    for path in source.rglob('*'):
        require(not path.is_symlink(), 'Publication source contains a link')
        if path.is_dir():
            require(any(name.startswith(path.relative_to(source).as_posix() + '/') for name in expected), 'Unexpected source directory')
            continue
        path = regular_file(path)
        relative = path.relative_to(source).as_posix()
        require(relative in expected and path.stat().st_nlink == 1, 'Unexpected or linked publication source')
        result[relative] = {'path': path, 'size': path.stat().st_size,
                            'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
    require(set(result) == expected, 'Publication source set differs from role')
    return result


def safe_tree(path):
    if not path.exists():
        require(not path.is_symlink(), 'Target is a dangling link')
        return
    if not path.is_dir():
        regular_file(path)
        return
    for directory, directories, files in os.walk(path, followlinks=False):
        if Path(directory) == path:
            directories[:] = [name for name in directories if name != '.git']
            files = [name for name in files if name != '.git']
        for name in [*directories, *files]:
            child = Path(directory) / name
            require(not child.is_symlink() and (child.is_dir() or stat.S_ISREG(child.stat().st_mode)), 'Target tree has an unsafe type')


def lfs_configuration(session, remote, files):
    repo = session.root / 'clone'
    for path in [repo / '.gitattributes', repo / '.lfsconfig']:
        if path.exists() or path.is_symlink(): regular_file(path)
    attributes = session.git('check-attr', '-z', 'filter', '--', *files).stdout.split(b'\0')[:-1]
    require(len(attributes) == 3 * len(files), 'Attribute consumer returned an incomplete result')
    needed = []
    for index in range(0, len(attributes), 3):
        path, name, value = attributes[index:index + 3]
        require(name == b'filter' and value in (b'unspecified', b'unset', b'lfs'), 'Unknown publication filter')
        if value == b'lfs': needed.append(os.fsdecode(path))
    if not needed: return []
    require(session.tools.lfs is not None, 'Required native Git-LFS is missing')
    config_path = repo / '.lfsconfig'
    if config_path.exists():
        pairs = session.git('config', '--no-includes', '--null', '--file', '.lfsconfig', '--list').stdout.split(b'\0')
        expected_endpoint = 'https://github.com/chen08209/' + remote + '.git/info/lfs'
        for pair in pairs:
            if not pair: continue
            key, separator, value = pair.partition(b'\n')
            require(separator and key in (b'lfs.url', b'lfs.pushurl') and value.decode() == expected_endpoint,
                    'LFS configuration selects an unknown receiver or behavior')
    version = session.run([session.tools.lfs, 'version'], repo).stdout.decode().strip()
    require(re.search(r'git-lfs/3\.[0-9]+\.[0-9]+', version), 'Unsupported native Git-LFS capability')
    session.observations['git-lfs'] = {'path': str(session.tools.lfs), 'version': version,
                                      'sha256': hashlib.sha256(session.tools.lfs.read_bytes()).hexdigest()}
    session.config.update({'filter.lfs.clean': shlex.quote(str(session.tools.lfs)) + ' clean -- %f',
                           'filter.lfs.required': 'true'})
    del session.config['filter.lfs.process']
    if session.local_lfs:
        session.config.update({'lfs.url': session.local_lfs, 'lfs.pushurl': session.local_lfs})
    session._config_environment()
    facts = session.run([session.tools.lfs, 'env'], repo).stdout.decode()
    endpoint = session.local_lfs or 'https://github.com/chen08209/' + remote + '.git/info/lfs'
    require(('Endpoint=' + endpoint + ' (auth=none)') in facts
            and 'UploadTransfers=basic' in facts, 'Native LFS effective endpoint or transfer differs')
    if not session.local_lfs:
        require(('  SSH=git@github.com:chen08209/' + remote + '.git') in facts, 'Native LFS lost fixed SSH authentication')
    return needed


def pre_push_guard(environment, arguments, raw):
    require(len(arguments) == 2 and arguments[0] == 'origin' and arguments[1] == environment['CI_PUSH_REMOTE'], 'Unexpected Git push receiver')
    rows = raw.decode('ascii').splitlines()
    require(len(rows) == 1, 'Expected a single main update')
    fields = rows[0].split()
    require(len(fields) == 4 and fields[0] == fields[2] == 'refs/heads/main'
            and fields[1] == environment['CI_PUSH_NEW'] and fields[3] == environment['CI_PUSH_BASE']
            and re.fullmatch('[0-9a-f]{40}', fields[3]) and fields[3] != '0' * 40,
            'Main was removed or changed before the actual push')
    if environment.get('CI_PUSH_LFS_BIN'):
        completed = subprocess.run([environment['CI_PUSH_LFS_BIN'], 'pre-push', *arguments],
                                   input=raw, env=environment, capture_output=True)
        require(completed.returncode == 0, 'Required LFS object transfer failed')


def publish(source, target, version, secret, parent, tools, *, local_remote=None, local_lfs=None, before_push=None):
    require(target in TARGETS and re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+', version), 'Unknown publication target or version')
    files = source_files(source, target, version)
    remote, relative = TARGETS[target]
    session = PushSession(parent, tools, local_remote=local_remote, local_lfs=local_lfs)
    try:
        session.prepare_identity(secret)
        url = Path(local_remote).resolve(strict=True).as_uri() if local_remote else 'git@github.com:chen08209/' + remote + '.git'
        session.run([tools.git, 'clone', '--branch', 'main', '--single-branch', '--no-tags', url, session.root / 'clone'], session.root)
        require(session.git('remote', 'get-url', 'origin').stdout.decode().strip() == url, 'Clone receiver differs')
        base = session.git('rev-parse', 'refs/heads/main').stdout.decode().strip()
        require(re.fullmatch('[0-9a-f]{40}', base), 'Main branch is unavailable')
        old = set(os.fsdecode(value) for value in session.git('ls-files', '-z').stdout.split(b'\0') if value)
        clone = session.root / 'clone'
        destination = clone / relative if relative else clone
        require(destination.resolve(strict=False).is_relative_to(clone) and not destination.is_symlink(), 'Target leaves the clone')
        safe_tree(destination)
        if relative:
            if destination.is_dir(): shutil.rmtree(destination)
            elif destination.exists(): destination.unlink()
            destination.mkdir()
            session.git('rm', '-r', '--cached', '--ignore-unmatch', '--', relative)
        else:
            for entry in clone.iterdir():
                if entry.name == '.git': continue
                if entry.is_dir(): shutil.rmtree(entry)
                else: entry.unlink()
            session.git('read-tree', '--empty')
        expected_paths = {}
        for name, item in files.items():
            output = destination / name
            output.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(item['path'], output)
            expected_paths[output.relative_to(clone).as_posix()] = item
        lfs = lfs_configuration(session, remote, list(expected_paths))
        session.git('add', '-A', '--', relative or '.')
        current = set(os.fsdecode(value) for value in session.git('ls-files', '-z').stdout.split(b'\0') if value)
        protected = {name for name in old if relative and name != relative and not name.startswith(relative + '/')}
        require(current == protected | set(expected_paths), 'Index contains an unexpected publication path')
        changed = {os.fsdecode(value) for value in session.git('diff', '--cached', '--name-only', '--no-renames', '-z').stdout.split(b'\0') if value}
        require(not relative or all(name == relative or name.startswith(relative + '/') for name in changed), 'Index changed outside the owned target')
        for name, item in expected_paths.items():
            data = session.git('show', ':' + name).stdout
            if name in lfs:
                expected_pointer = f"version https://git-lfs.github.com/spec/v1\noid sha256:{item['sha256']}\nsize {item['size']}\n".encode()
                require(data == expected_pointer, 'LFS pointer does not bind the intended file')
            else:
                require(hashlib.sha256(data).hexdigest() == item['sha256'], 'Git transformed the intended publication bytes')
        if not changed: return {'status': 'no_change', 'tools': session.observations}
        session.git('commit', '--no-verify', '--no-gpg-sign', '-m', 'Update ' + target + ' from v' + version)
        head = session.git('rev-parse', 'HEAD').stdout.decode().strip()
        guard = session.root / 'hooks/pre-push'
        guard.write_text('#!/bin/sh\nexec ' + shlex.join([sys.executable, '-s', str(Path(__file__).resolve()), '_pre-push']) + ' "$@"\n')
        guard.chmod(0o700)
        session.environment.update(CI_PUSH_REMOTE=url, CI_PUSH_BASE=base, CI_PUSH_NEW=head)
        if lfs: session.environment['CI_PUSH_LFS_BIN'] = str(tools.lfs)
        if before_push: before_push(session)
        session.check_identity()
        session.git('push', 'origin', 'refs/heads/main:refs/heads/main')
        return {'status': 'published', 'commit': head, 'tools': session.observations}
    finally:
        session.close()


def main():
    if len(sys.argv) > 1 and sys.argv[1] == '_pre-push':
        try:
            pre_push_guard(dict(os.environ), sys.argv[2:], sys.stdin.buffer.read(8193))
            return 0
        except Exception:
            print('Publication ref or required LFS transfer was rejected', file=sys.stderr)
            return 1
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--target', choices=TARGETS, required=True)
    parser.add_argument('--source', type=Path, required=True)
    args = parser.parse_args()
    try:
        intent = event_context(os.environ, load_json(Path(os.environ['GITHUB_EVENT_PATH']).read_bytes()), Path('pubspec.yaml').read_text())
        require(intent['stable'] == 'true', 'SSH publication only accepts stable releases')
        parent = Path(os.environ['RUNNER_TEMP']).resolve(strict=True)
        require(args.source.absolute().is_relative_to(parent), 'Publication source leaves runner-owned staging')
        result = publish(args.source, args.target, intent['version'], os.environ['SSH_DEPLOY_KEY'], parent, NativeTools.hosted(os.environ))
        print(json.dumps(result, sort_keys=True))
        return 0
    except Exception:
        print('Native repository publication failed', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
