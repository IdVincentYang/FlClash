"""Qualify release jobs and consume exact producer artifacts without publishing."""

import argparse
import base64
import hashlib
import json
import tarfile
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import tomllib
import urllib.error
import urllib.parse
import urllib.request
import zipfile

REPOSITORY = 'chen08209/FlClash'
TAG = re.compile(r'v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-pre\.[1-9][0-9]*)?')
SLOTS = ('android-candidate', 'windows-amd64', 'windows-arm64', 'linux-amd64',
         'linux-arm64', 'macos-amd64', 'macos-arm64')
ROLES = SLOTS + ('android-final', 'notes')
MAX_ARCHIVE = 2 * 1024**3


class ReleaseError(Exception):
    pass


def require(condition, reason):
    if not condition:
        raise ReleaseError(reason)


def unique_fields(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, 'Duplicate JSON field')
        result[key] = value
    return result


def load_json(data):
    return json.loads(data, object_pairs_hook=unique_fields)


def digest(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def regular_file(path):
    path = Path(path).absolute()
    require(not any(parent.is_symlink() for parent in (path, *path.parents)), 'File path contains a link')
    require(stat.S_ISREG(path.stat().st_mode), 'Expected a regular file')
    return path


def numeric(value):
    require(isinstance(value, str) and re.fullmatch('[1-9][0-9]*', value), 'Missing numeric GitHub identity')
    return int(value)


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


class GitHubAPI:
    def __init__(self, token, *, origin='https://api.github.com', allow_loopback=False):
        parts = urllib.parse.urlsplit(origin)
        self.loopback = allow_loopback and parts.scheme == 'http' and parts.hostname in ('127.0.0.1', 'localhost')
        require(origin == 'https://api.github.com' or self.loopback, 'Unaccepted API origin')
        self.origin = origin.rstrip('/')
        self.token = token
        self.opener = urllib.request.build_opener(urllib.request.ProxyHandler({}) if self.loopback
                                                  else urllib.request.ProxyHandler(), NoRedirect())

    def _open(self, url, *, authorization=False):
        headers = {'Accept': 'application/octet-stream', 'User-Agent': 'release-artifact-checker'}
        if authorization:
            headers.update({'Accept': 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28'})
        if authorization:
            require(url.startswith(self.origin + '/'), 'Authorization receiver differs from GitHub')
            if self.token:
                headers['Authorization'] = 'Bearer ' + self.token
        try:
            return self.opener.open(urllib.request.Request(url, headers=headers), timeout=60)
        except urllib.error.HTTPError as error:
            if error.code == 302:
                return error
            raise ReleaseError('GitHub or artifact request failed') from None
        except (OSError, urllib.error.URLError):
            raise ReleaseError('GitHub or artifact request unavailable') from None

    def url(self, path, parameters=None):
        require(isinstance(path, str) and re.fullmatch('[A-Za-z0-9_./-]+', path)
                and all(part not in ('', '.', '..') for part in path.split('/')), 'Invalid fixed API path')
        suffix = '?' + urllib.parse.urlencode(parameters) if parameters else ''
        return self.origin + '/repos/' + REPOSITORY + '/' + path + suffix

    def get(self, path, parameters=None):
        with self._open(self.url(path, parameters), authorization=True) as response:
            require(response.status == 200, 'Unexpected API redirect or status')
            data = response.read(16 * 1024**2 + 1)
        require(len(data) <= 16 * 1024**2, 'Excessive API response')
        return load_json(data)

    def jobs(self, run_id, attempt):
        result = []
        total = None
        for page in range(1, 101):
            data = self.get(f'actions/runs/{run_id}/attempts/{attempt}/jobs', {'per_page': 100, 'page': page})
            require(isinstance(data, dict) and type(data.get('total_count')) is int
                    and isinstance(data.get('jobs'), list), 'Invalid jobs API response')
            if total is None:
                total = data['total_count']
            require(total == data['total_count'] and 0 <= total <= 10000, 'Jobs pagination changed')
            chunk = data['jobs']
            require(chunk or len(result) == total, 'Incomplete jobs API response')
            result.extend(chunk)
            if len(result) == total:
                require(len({job['id'] for job in result}) == total, 'Duplicate jobs API result')
                return result
            require(len(result) < total, 'Invalid jobs pagination')
        raise ReleaseError('Jobs API pagination exceeded its bound')

    def download(self, artifact_id, archive_digest, destination):
        url = self.url(f'actions/artifacts/{numeric(str(artifact_id))}/zip')
        response = self._open(url, authorization=True)
        try:
            require(response.status == 302, 'Expected the official artifact redirect')
            location = response.headers.get('Location', '')
        finally:
            response.close()
        for _ in range(4):
            parts = urllib.parse.urlsplit(location)
            host = parts.hostname or ''
            local = self.loopback and parts.scheme == 'http' and host in ('127.0.0.1', 'localhost')
            official = parts.scheme == 'https' and any(host.endswith(suffix) for suffix in (
                '.blob.core.windows.net', '.actions.githubusercontent.com', '.githubusercontent.com'))
            require((local or official) and not parts.username and not parts.password and not parts.fragment,
                    'Artifact redirect has an unaccepted receiver')
            with self._open(location) as response:
                if response.status == 302:
                    location = response.headers.get('Location', '')
                    continue
                require(response.status == 200, 'Unexpected artifact download status')
                checksum = hashlib.sha256()
                size = 0
                with Path(destination).open('xb') as stream:
                    while block := response.read(1024**2):
                        size += len(block)
                        require(size <= MAX_ARCHIVE, 'Artifact exceeds size policy')
                        checksum.update(block)
                        stream.write(block)
                require(checksum.hexdigest() == archive_digest, 'Artifact archive digest mismatch')
                return
        raise ReleaseError('Artifact redirect limit exceeded')


def event_context(environment, event, pubspec):
    require(environment.get('GITHUB_REPOSITORY') == REPOSITORY
            and environment.get('GITHUB_EVENT_NAME') == 'push'
            and environment.get('GITHUB_REF_TYPE') == 'tag'
            and event.get('deleted') is False, 'Event has no release role')
    ref = environment.get('GITHUB_REF', '')
    require(ref.startswith('refs/tags/'), 'Expected a tag ref')
    tag = ref.removeprefix('refs/tags/')
    require(TAG.fullmatch(tag) and event.get('ref') == ref, 'Release tag syntax or event mismatch')
    sha = environment.get('GITHUB_SHA', '')
    require(re.fullmatch('[0-9a-f]{40}', sha), 'Invalid release commit')
    version = tag.removeprefix('v').split('-pre.')[0]
    match = re.search(r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)(?:\+([0-9]+))?\s*$', pubspec, re.M)
    require(match and match[1] == version, 'Tag and source version differ')
    repository_id = numeric(environment.get('GITHUB_REPOSITORY_ID', ''))
    repo = event.get('repository', {})
    require(repo.get('full_name') == REPOSITORY and repo.get('id') == repository_id, 'Event repository differs')
    return {'eligible': 'true', 'stable': str('-pre.' not in tag).lower(), 'version': version,
            'build_number': int(match[2] or '1'), 'tag': tag, 'commit': sha,
            'run_id': numeric(environment.get('GITHUB_RUN_ID', '')),
            'attempt': numeric(environment.get('GITHUB_RUN_ATTEMPT', '')),
            'repository_id': repository_id}


def tag_commit(api, tag):
    require(TAG.fullmatch(tag), 'Unaccepted tag lookup')
    obj = api.get('git/ref/tags/' + tag)['object']
    for _ in range(6):
        require(isinstance(obj, dict) and re.fullmatch('[0-9a-f]{40}', obj.get('sha', '')), 'Invalid tag object')
        if obj.get('type') == 'commit':
            return obj['sha']
        require(obj.get('type') == 'tag', 'Tag does not point at a commit')
        obj = api.get('git/tags/' + obj['sha'])['object']
    raise ReleaseError('Excessive annotated tag chain')


def qualify(api, intent):
    run = api.get(f"actions/runs/{intent['run_id']}")
    require(run.get('id') == intent['run_id'] and run.get('head_sha') == intent['commit'] and run.get('event') == 'push'
            and run.get('run_attempt') == intent['attempt']
            and run.get('repository', {}).get('id') == intent['repository_id']
            and run.get('head_repository', {}).get('id') == intent['repository_id'], 'Workflow run identity differs')
    require(tag_commit(api, intent['tag']) == intent['commit'], 'Tag no longer binds the release commit')
    return intent


def gate_binding(intent):
    return {'eligible': 'true', 'run_id': intent['run_id'], 'attempt': intent['attempt'], 'commit': intent['commit']}


def expected_names(role, version):
    require(role in ROLES and re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+', version), 'Invalid artifact role or version')
    prefix = 'FlClash-' + version + '-'
    if role.startswith('android-'):
        return {prefix + f'android-{abi}.apk' for abi in ('armeabi-v7a', 'arm64-v8a', 'x86_64')}
    if role == 'notes':
        return {'release.md', 'telegram.md'}
    platform, arch = role.split('-')
    stem = prefix + platform + '-' + arch
    if platform == 'windows':
        return {stem + '-setup.exe', stem + '.zip'}
    if platform == 'linux':
        return {stem + suffix for suffix in ('.deb', '.AppImage', '.rpm')}
    return {stem + '.dmg'}


def artifact_name(intent, role):
    require(role in ROLES, 'Invalid artifact role')
    return f"build-{intent['run_id']}-{intent['attempt']}-{role}"


def pack(source, destination, role, intent):
    source, destination = Path(source), Path(destination)
    names = expected_names(role, intent['version'])
    require(set(path.name for path in source.iterdir()) == names, 'Producer directory differs from its role')
    destination.mkdir()
    (destination / 'payload').mkdir()
    files = {}
    for name in sorted(names):
        path = regular_file(source / name)
        require(path.stat().st_size <= MAX_ARCHIVE and (role == 'notes' or path.stat().st_size > 0), 'Invalid producer size')
        shutil.copyfile(path, destination / 'payload' / name)
        copied = regular_file(destination / 'payload' / name)
        files[name] = {'size': copied.stat().st_size, 'sha256': digest(copied)}
    inventory = {'schema': 1, 'role': role, 'run_id': intent['run_id'], 'attempt': intent['attempt'],
                 'commit': intent['commit'], 'files': files}
    (destination / 'inventory.json').write_text(json.dumps(inventory, sort_keys=True) + '\n')


def producer(needs, role, intent, jobs):
    name = 'sign_android' if role == 'android-final' else 'notes' if role == 'notes' else 'build'
    data = needs.get(name, {})
    require(data.get('result') == 'success', 'Producer job did not succeed')
    outputs = data.get('outputs', {})
    key = role.replace('-', '_')
    artifact_id = numeric(outputs.get(key + '_id', ''))
    sha = outputs.get(key + '_sha256', '')
    require(re.fullmatch('[0-9a-f]{64}', sha) and outputs.get(key + '_attempt') == str(intent['attempt']),
            'Producer artifact output is missing or from another attempt')
    job_name = 'Sign Android' if role == 'android-final' else 'Notes' if role == 'notes' else 'Build (' + role + ')'
    candidates = [job for job in jobs if job.get('name') == job_name]
    require(len(candidates) == 1 and candidates[0].get('conclusion') == 'success'
            and candidates[0].get('run_id') == intent['run_id']
            and candidates[0].get('head_sha') == intent['commit'], 'Producer job API fact differs')
    steps = candidates[0].get('steps', [])
    require(sum(step.get('name') == 'Upload producer artifact' and step.get('conclusion') == 'success'
                for step in steps) == 1, 'Producer upload step did not succeed')
    return artifact_id, sha


def artifact_metadata(api, intent, role, artifact_id, sha):
    data = api.get(f'actions/artifacts/{artifact_id}')
    run = data.get('workflow_run', {})
    require(data.get('id') == artifact_id and data.get('name') == artifact_name(intent, role)
            and data.get('expired') is False and data.get('digest') == 'sha256:' + sha
            and run.get('id') == intent['run_id'] and run.get('head_sha') == intent['commit']
            and run.get('repository_id') == intent['repository_id']
            and run.get('head_repository_id') == intent['repository_id'], 'GitHub artifact identity differs')
    return data


def unpack(archive, destination, role, intent):
    destination = Path(destination)
    require(not destination.exists(), 'Artifact destination already exists')
    expected = expected_names(role, intent['version'])
    allowed = {'inventory.json'} | {'payload/' + name for name in expected}
    with zipfile.ZipFile(regular_file(archive)) as bundle:
        entries = bundle.infolist()
        require(len(entries) <= len(allowed) + 1, 'Unexpected artifact entry count')
        seen, files, total = set(), {}, 0
        for entry in entries:
            name = entry.filename
            require(name not in seen and name.casefold() not in {value.casefold() for value in seen}, 'Duplicate artifact path')
            seen.add(name)
            require(not name.startswith('/') and '\\' not in name and '\x00' not in name
                    and all(part not in ('', '.', '..') for part in name.rstrip('/').split('/')), 'Unsafe artifact path')
            kind = stat.S_IFMT(entry.external_attr >> 16)
            if entry.is_dir():
                require(name == 'payload/' and kind in (0, stat.S_IFDIR), 'Unexpected artifact directory')
                continue
            require(name in allowed and kind in (0, stat.S_IFREG), 'Unexpected artifact file or type')
            total += entry.file_size
            require(0 <= entry.file_size <= MAX_ARCHIVE and total <= MAX_ARCHIVE, 'Excessive artifact payload')
            files[name] = entry
        require(set(files) == allowed, 'Artifact is missing expected files')
        require(files['inventory.json'].file_size <= 1024**2, 'Excessive candidate inventory')
        inventory = load_json(bundle.read(files['inventory.json']))
        require(isinstance(inventory, dict) and set(inventory) == {'schema', 'role', 'run_id', 'attempt', 'commit', 'files'}
                and inventory['schema'] == 1 and inventory['role'] == role
                and inventory['run_id'] == intent['run_id'] and inventory['attempt'] == intent['attempt']
                and inventory['commit'] == intent['commit'] and set(inventory['files']) == expected,
                'Candidate inventory differs from trusted job selection')
        destination.mkdir()
        for name in sorted(expected):
            metadata = inventory['files'][name]
            require(isinstance(metadata, dict) and set(metadata) == {'size', 'sha256'}
                    and type(metadata['size']) is int and metadata['size'] == files['payload/' + name].file_size
                    and isinstance(metadata['sha256'], str) and re.fullmatch('[0-9a-f]{64}', metadata['sha256']),
                    'Invalid candidate file metadata')
            checksum = hashlib.sha256()
            with bundle.open(files['payload/' + name]) as source, (destination / name).open('xb') as target:
                while chunk := source.read(1024**2):
                    checksum.update(chunk)
                    target.write(chunk)
            require(checksum.hexdigest() == metadata['sha256'], 'Payload differs from producer inventory')
    return sorted(destination / name for name in expected)


def consume(api, intent, needs, roles, destination):
    require(len(roles) == len(set(roles)), 'Duplicate artifact role')
    destination = Path(destination)
    destination.mkdir()
    jobs = api.jobs(intent['run_id'], intent['attempt'])
    ids, result = set(), {}
    for role in roles:
        artifact_id, sha = producer(needs, role, intent, jobs)
        require(artifact_id not in ids, 'Producer slots share an artifact ID')
        ids.add(artifact_id)
        artifact_metadata(api, intent, role, artifact_id, sha)
        archive = destination / (role + '.zip')
        api.download(artifact_id, sha, archive)
        result[role] = unpack(archive, destination / role, role, intent)
    return result


def pages_intent(api, environment, event):
    require(environment.get('GITHUB_REPOSITORY') == REPOSITORY
            and event.get('repository', {}).get('default_branch') == 'main', 'Pages repository or default branch differs')
    kind = environment.get('GITHUB_EVENT_NAME')
    sha = environment.get('GITHUB_SHA', '')
    require(re.fullmatch('[0-9a-f]{40}', sha), 'Invalid Pages execution commit')
    if kind in ('push', 'workflow_dispatch'):
        require(environment.get('GITHUB_REF') == 'refs/heads/main' and
                (kind != 'push' or event.get('ref') == 'refs/heads/main' and event.get('deleted') is False),
                'Pages only executes main')
    else:
        require(kind == 'workflow_run' and event.get('action') == 'completed', 'Unaccepted Pages event')
        source = event.get('workflow_run', {})
        run_id = numeric(str(source.get('id', '')))
        attempt = numeric(str(source.get('run_attempt', '')))
        run = api.get(f'actions/runs/{run_id}')
        workflow = api.get('actions/workflows/build.yaml')
        repository_id = numeric(environment.get('GITHUB_REPOSITORY_ID', ''))
        require(run.get('id') == run_id and run.get('workflow_id') == workflow.get('id') and run.get('path') == '.github/workflows/build.yaml'
                and run.get('event') == 'push' and run.get('conclusion') == 'success'
                and run.get('status') == 'completed' and run.get('run_attempt') == attempt
                and run.get('repository', {}).get('id') == repository_id
                and run.get('head_repository', {}).get('id') == repository_id
                and source.get('head_sha') == run.get('head_sha'), 'Pages producer is not trusted')
        tag = run.get('head_branch', '')
        require(TAG.fullmatch(tag) and '-pre.' not in tag and tag_commit(api, tag) == run['head_sha'], 'Pages source is not a stable tag')
        jobs = api.jobs(run_id, attempt)
        for name in ('Release gate', 'Publish GitHub'):
            require(sum(job.get('name') == name and job.get('conclusion') == 'success'
                        and job.get('head_sha') == run['head_sha'] for job in jobs) == 1, 'Pages producer did not qualify the tag event')
        require(environment.get('GITHUB_REF') == 'refs/heads/main', 'Pages default execution branch changed')
    return {'eligible': 'true', 'checkout_sha': sha, 'commit': sha,
            'run_id': numeric(environment.get('GITHUB_RUN_ID', '')),
            'attempt': numeric(environment.get('GITHUB_RUN_ATTEMPT', ''))}


def site_entries(source):
    source = Path(source).absolute()
    require(source.is_dir() and source.resolve(strict=True) == source, 'Site root is not an owned canonical directory')
    entries = []
    for directory, directories, files in os.walk(source, followlinks=False):
        directories[:] = sorted(name for name in directories if name not in ('.git', '.github'))
        files = sorted(name for name in files if name not in ('.git', '.github'))
        for name in [*directories, *files]:
            path = Path(directory) / name
            relative = path.relative_to(source).as_posix()
            require(not path.is_symlink() and all(part not in ('', '.', '..') for part in relative.split('/')),
                    'Site contains an unsafe path or link')
            status = path.stat()
            require(stat.S_ISDIR(status.st_mode) or stat.S_ISREG(status.st_mode), 'Site contains a special file')
            require(status.st_mode & stat.S_IRUSR and (not path.is_dir() or status.st_mode & stat.S_IXUSR),
                    'Site input cannot be read or traversed')
            require(path.is_dir() or status.st_nlink == 1, 'Site contains a hardlinked file')
            entries.append((relative, path, path.is_dir()))
            require(len(entries) <= 10000, 'Excessive site entries')
    return entries


def site_manifest(source):
    result = {}
    for relative, path, directory in site_entries(source):
        if not directory:
            result[relative] = {'size': path.stat().st_size, 'sha256': digest(path)}
    require(result and sum(item['size'] for item in result.values()) <= 1024**3, 'Site payload is empty or excessive')
    return result


def pack_pages(source, destination):
    expected = site_digest(site_manifest(source))
    destination = Path(destination)
    with tarfile.open(destination, mode='w', format=tarfile.PAX_FORMAT) as archive:
        root = tarfile.TarInfo('.')
        root.type = tarfile.DIRTYPE
        root.mode = 0o755
        archive.addfile(root)
        for relative, path, directory in site_entries(source):
            entry = tarfile.TarInfo('./' + relative)
            entry.mode = 0o755 if directory else 0o644
            entry.type = tarfile.DIRTYPE if directory else tarfile.REGTYPE
            if directory:
                archive.addfile(entry)
            else:
                entry.size = path.stat().st_size
                with regular_file(path).open('rb') as stream:
                    archive.addfile(entry, stream)
    with regular_file(destination).open('rb') as stream:
        read_pages_tar(stream, expected)
    return expected


def site_digest(manifest):
    return hashlib.sha256(json.dumps(manifest, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def read_pages_tar(stream, expected_digest):
    result, seen = {}, set()
    with tarfile.open(fileobj=stream, mode='r|') as tar:
        count, total = 0, 0
        for member in tar:
            count += 1
            require(count <= 10000, 'Excessive Pages tar entries')
            name = member.name.removeprefix('./')
            if name in ('', '.') and member.isdir():
                name = '.'
            else:
                require(not name.startswith('/') and '\\' not in name and '\x00' not in name
                        and all(part not in ('', '.', '..', '.git', '.github') for part in name.rstrip('/').split('/')),
                        'Unsafe Pages tar path')
            require(name not in seen, 'Duplicate Pages archive path')
            seen.add(name)
            require(member.isdir() or member.isfile(), 'Pages tar contains a link or special file')
            mask = 0o555 if member.isdir() else 0o444
            require(member.mode & mask == mask and member.mode & 0o7000 == 0, 'Pages member is not readable or traversable')
            if member.isdir():
                continue
            total += member.size
            require(total <= 1024**3, 'Excessive Pages file content')
            with tar.extractfile(member) as content:
                checksum = hashlib.file_digest(content, 'sha256').hexdigest()
            result[name] = {'size': member.size, 'sha256': checksum}
    require(site_digest(result) == expected_digest, 'Pages payload differs from its trusted build output')


def pages_payload(archive, expected_digest):
    with zipfile.ZipFile(regular_file(archive)) as bundle:
        require(bundle.namelist() == ['artifact.tar'], 'Pages archive has an unexpected wrapper')
        entry = bundle.getinfo('artifact.tar')
        require(entry.file_size <= 1024**3 and stat.S_IFMT(entry.external_attr >> 16) in (0, stat.S_IFREG),
                'Invalid Pages tar member')
        with bundle.open(entry) as stream:
            read_pages_tar(stream, expected_digest)


def verify_pages_artifact(api, environment, event, needs, destination):
    pages_intent(api, environment, event)
    data = needs.get('pages_build', {})
    require(data.get('result') == 'success', 'Pages build did not succeed')
    outputs = data.get('outputs', {})
    run_id = numeric(environment.get('GITHUB_RUN_ID', ''))
    attempt = numeric(environment.get('GITHUB_RUN_ATTEMPT', ''))
    repository_id = numeric(environment.get('GITHUB_REPOSITORY_ID', ''))
    artifact_id = numeric(outputs.get('artifact_id', ''))
    name = f'pages-{run_id}-{attempt}'
    require(outputs.get('artifact_name') == name and outputs.get('attempt') == str(attempt)
            and re.fullmatch('[0-9a-f]{64}', outputs.get('site_sha256', '')), 'Pages producer output is missing or stale')
    jobs = api.jobs(run_id, attempt)
    matches = [job for job in jobs if job.get('name') == 'Pages build']
    require(len(matches) == 1 and matches[0].get('conclusion') == 'success'
            and matches[0].get('run_id') == run_id and matches[0].get('head_sha') == environment['GITHUB_SHA'],
            'Pages producer API fact differs')
    artifact = api.get(f'actions/artifacts/{artifact_id}')
    run = artifact.get('workflow_run', {})
    sha = artifact.get('digest', '')
    require(artifact.get('name') == name and artifact.get('id') == artifact_id and artifact.get('expired') is False
            and re.fullmatch('sha256:[0-9a-f]{64}', sha)
            and sha == 'sha256:' + outputs.get('artifact_sha256', '') and run.get('id') == run_id
            and run.get('repository_id') == repository_id and run.get('head_repository_id') == repository_id
            and run.get('head_sha') == environment['GITHUB_SHA'], 'Pages artifact identity differs')
    found, total = [], None
    for page in range(1, 101):
        listing = api.get(f'actions/runs/{run_id}/artifacts', {'per_page': 100, 'page': page})
        require(type(listing.get('total_count')) is int and isinstance(listing.get('artifacts'), list), 'Invalid Pages artifact listing')
        if total is None:
            total = listing['total_count']
        require(total == listing['total_count'] and 0 <= total <= 10000, 'Pages artifact pagination changed')
        found.extend(listing['artifacts'])
        require(listing['artifacts'] or len(found) == total, 'Incomplete Pages artifact listing')
        if len(found) == total:
            break
        require(len(found) < total, 'Invalid Pages artifact count')
    else:
        raise ReleaseError('Pages artifact pagination exceeded its bound')
    same_name = [item for item in found if item.get('name') == name]
    require(len(same_name) == 1 and same_name[0].get('id') == artifact_id, 'Pages name is not unique to its trusted ID')
    Path(destination).mkdir()
    archive = Path(destination) / 'pages.zip'
    api.download(artifact_id, sha.removeprefix('sha256:'), archive)
    pages_payload(archive, outputs['site_sha256'])
    return {'eligible': 'true', 'artifact_name': name, 'artifact_id': artifact_id,
            'run_id': run_id, 'attempt': attempt, 'commit': environment['GITHUB_SHA']}


def java_environment(environment):
    return {key: environment[key] for key in ('PATH', 'HOME', 'JAVA_HOME', 'TMPDIR', 'TEMP', 'LANG', 'LC_ALL', 'SystemRoot') if key in environment}


def apk_info(apk, jar, java, classes):
    completed = subprocess.run([str(java), '-cp', str(jar) + os.pathsep + str(classes),
                                'CiAndroidManifest', str(regular_file(apk))], env=java_environment(os.environ), capture_output=True)
    require(completed.returncode == 0, 'APK manifest could not be read by the accepted SDK parser')
    lines = completed.stdout.decode('utf-8').splitlines()
    require(len(lines) == 4 and re.fullmatch('[1-9][0-9]*', lines[2])
            and re.fullmatch('[0-9a-f]{64}', lines[3]), 'Invalid APK manifest or signer facts')
    return {'package': lines[0], 'version': lines[1], 'version_code': int(lines[2]), 'certificate': lines[3]}


def verify_apk(apk, role, intent, jar, java, classes, certificate=None):
    require(role in ('android-candidate', 'android-final'), 'Wrong Android artifact role')
    require(Path(apk).name in expected_names(role, intent['version']), 'Unexpected APK filename')
    abi = Path(apk).name.removeprefix('FlClash-' + intent['version'] + '-android-').removesuffix('.apk')
    expected_class, expected_machine, version_offset = {
        'armeabi-v7a': (1, 40, 1000), 'arm64-v8a': (2, 183, 2000), 'x86_64': (2, 62, 4000)}[abi]
    seen = set()
    with zipfile.ZipFile(regular_file(apk)) as bundle:
        require(len(bundle.infolist()) <= 100000, 'Excessive APK entries')
        for entry in bundle.infolist():
            require(entry.filename not in seen, 'Duplicate APK entry')
            seen.add(entry.filename)
            if entry.filename.startswith('lib/') and not entry.is_dir():
                parts = entry.filename.split('/')
                require(len(parts) == 3 and parts[1] == abi and parts[2].endswith('.so'), 'APK native ABI differs')
                with bundle.open(entry) as stream:
                    header = stream.read(20)
                require(len(header) == 20 and header[:4] == b'\x7fELF' and header[4] == expected_class
                        and header[5] == 1 and int.from_bytes(header[18:20], 'little') == expected_machine,
                        'APK native ELF target differs')
        require(any(name.startswith('lib/' + abi + '/') for name in seen), 'APK lacks its target native library')
    info = apk_info(apk, jar, java, classes)
    actual_certificate = info.pop('certificate')
    require(info == {'package': 'com.follow.clash', 'version': intent['version'],
                     'version_code': intent['build_number'] + version_offset},
            'APK package or version differs from release intent')
    require(certificate is None or actual_certificate == certificate,
            'APK signer differs from the selected signing key')
    return info


def sign_android(source, destination, intent, jar, java, classes, keytool, environment, expected):
    source, destination = Path(source), Path(destination)
    require(set(path.name for path in source.iterdir()) == expected_names('android-candidate', intent['version']), 'Candidate Android set differs')
    require(isinstance(expected, dict) and set(expected) == expected_names('android-candidate', intent['version']), 'Missing keyless candidate verification')
    for apk in source.iterdir():
        apk = regular_file(apk)
        require(expected[apk.name] == {'size': apk.stat().st_size, 'sha256': digest(apk)}, 'Candidate changed after keyless verification')
    destination.mkdir()
    private = destination / '.signing'
    private.mkdir(mode=0o700)
    try:
        key = private / 'key.jks'
        key.write_bytes(base64.b64decode(''.join(environment['KEYSTORE'].split()), validate=True))
        key.chmod(0o600)
        export = subprocess.run([str(keytool), '-exportcert', '-keystore', str(key), '-alias', environment['KEY_ALIAS'],
            '-storepass:env', 'STORE_PASSWORD'], env=dict(java_environment(environment), STORE_PASSWORD=environment['STORE_PASSWORD']), capture_output=True)
        require(export.returncode == 0 and export.stdout, 'Selected signing certificate could not be read')
        certificate = hashlib.sha256(export.stdout).hexdigest()
        for apk in sorted(source.iterdir()):
            target = destination / apk.name
            completed = subprocess.run([str(java), '-jar', str(jar), 'sign', '--ks', str(key),
                '--ks-key-alias', environment['KEY_ALIAS'], '--ks-pass', 'env:STORE_PASSWORD',
                '--key-pass', 'env:KEY_PASSWORD', '--v4-signing-enabled', 'false', '--out', str(target), str(apk)], env=dict(java_environment(environment), STORE_PASSWORD=environment['STORE_PASSWORD'], KEY_PASSWORD=environment['KEY_PASSWORD']), capture_output=True)
            require(completed.returncode == 0, 'APK re-signing failed')
            verify_apk(target, 'android-final', intent, jar, java, classes, certificate)
            with zipfile.ZipFile(apk) as before, zipfile.ZipFile(target) as after:
                def payload(bundle):
                    return {entry.filename: hashlib.sha256(bundle.read(entry)).hexdigest()
                            for entry in bundle.infolist() if not entry.is_dir() and not (
                                entry.filename.upper().startswith('META-INF/') and
                                (entry.filename.upper() == 'META-INF/MANIFEST.MF' or
                                 entry.filename.upper().endswith(('.SF', '.RSA', '.DSA', '.EC'))))}
                require(payload(before) == payload(after), 'Re-signing changed APK payload bytes')
    finally:
        shutil.rmtree(private)
    return certificate


def prepare_signer(root, destination):
    from android_input_materials import read_archive
    root, destination = Path(root), Path(destination)
    policy = tomllib.loads((root / 'tool/android_artifacts.toml').read_text())['artifacts']['android_build_tools']
    require(policy['url'].startswith('https://dl.google.com/android/repository/')
            and re.fullmatch('[0-9a-f]{64}', policy['sha256']), 'Signer is outside the accepted SDK policy')
    destination.mkdir()
    archive = destination / 'build-tools.zip'
    try:
        with urllib.request.urlopen(policy['url'], timeout=60) as response, archive.open('xb') as stream:
            total = 0
            while block := response.read(1024**2):
                total += len(block)
                require(total <= policy['size'], 'SDK signer archive is oversized')
                stream.write(block)
        require(total == policy['size'] and digest(archive) == policy['sha256'], 'SDK signer archive differs from accepted bytes')
        index = read_archive(archive, policy)
        expected = index['lib/apksigner.jar']
        with zipfile.ZipFile(archive) as bundle:
            data = bundle.read(policy['prefix'] + '/lib/apksigner.jar')
        require(hashlib.sha256(data).hexdigest() == expected['sha256'], 'Signer JAR identity differs')
        (destination / 'apksigner.jar').write_bytes(data)
    except (OSError, urllib.error.URLError):
        raise ReleaseError('Accepted SDK signer could not be downloaded') from None


def output(values):
    path = os.environ.get('GITHUB_OUTPUT')
    if path:
        with Path(path).open('a') as stream:
            for key, value in values.items():
                require(re.fullmatch('[a-z_]+', key) and '\n' not in str(value) and '\r' not in str(value), 'Unsafe job output')
                stream.write(f'{key}={value}\n')
    print(json.dumps(values, sort_keys=True))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['release-gate', 'sign-gate', 'publish-gate', 'consume', 'pack',
                                         'verify-android-candidate', 'pages-gate', 'pack-pages', 'pages-inputs', 'pages-deploy-gate', 'prepare-signer', 'sign'])
    parser.add_argument('--role', choices=ROLES)
    parser.add_argument('--source', type=Path)
    parser.add_argument('--destination', type=Path)
    parser.add_argument('--jar', type=Path)
    parser.add_argument('--classes', type=Path)
    args = parser.parse_args()
    try:
        if args.command == 'pack-pages':
            output({'site_sha256': pack_pages(args.source, args.destination)})
            return 0
        if args.command == 'pages-inputs':
            output({'site_sha256': site_digest(site_manifest(args.source))})
            return 0
        if args.command == 'prepare-signer':
            prepare_signer(Path.cwd(), args.destination)
            return 0
        event = load_json(regular_file(os.environ['GITHUB_EVENT_PATH']).read_bytes())
        api = GitHubAPI(os.environ.get('GH_TOKEN', ''))
        if args.command == 'pages-deploy-gate':
            output(verify_pages_artifact(api, os.environ, event, load_json(os.environ['CI_NEEDS']), args.destination))
            return 0
        if args.command == 'pages-gate':
            output(pages_intent(api, os.environ, event))
            return 0
        intent = event_context(os.environ, event, Path('pubspec.yaml').read_text())
        if args.command == 'pack':
            pack(args.source, args.destination, args.role, intent)
            return 0
        if args.command == 'verify-android-candidate':
            java = Path(os.environ['JAVA_HOME']) / 'bin/java'
            require(set(path.name for path in args.source.iterdir()) == expected_names('android-candidate', intent['version']), 'Candidate set differs')
            candidates = {}
            for apk in args.source.iterdir():
                verify_apk(apk, 'android-candidate', intent, args.jar, java, args.classes)
                candidates[apk.name] = {'size': apk.stat().st_size, 'sha256': digest(apk)}
            output({'android_candidates': json.dumps(candidates, sort_keys=True)})
            return 0
        if args.command == 'sign':
            java_home = Path(os.environ['JAVA_HOME']) / 'bin'
            sign_android(args.source, args.destination, intent, args.jar, java_home / 'java', args.classes,
                         java_home / 'keytool', dict(os.environ), load_json(os.environ['CI_EXPECTED_ANDROID']))
            return 0
        qualify(api, intent)
        if args.command == 'release-gate':
            output(intent)
            return 0
        needs = load_json(os.environ['CI_NEEDS'])
        roles = ['android-candidate'] if args.command == 'sign-gate' else (
            ['android-final', *SLOTS[1:], 'notes'] if args.command == 'publish-gate' else [args.role])
        consume(api, intent, needs, roles, args.destination)
        output(gate_binding(intent))
        return 0
    except Exception:
        print('Release qualification or artifact consumption failed', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
