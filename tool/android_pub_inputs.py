"""Inspect native pub resolution data; dependency resolution remains owned by pub."""

import json
from contextlib import nullcontext
import os
from pathlib import Path
import re
from urllib.parse import unquote, urlsplit

from android_input_materials import MaterialError, SelectedRoot, compare_tree, read_archive
from android_git_inputs import source_index


def read_data(path, limit=4 * 1024 * 1024):
    with SelectedRoot(path, directory=False) as root, root.file() as stream:
        data = stream.read(limit + 1)
    if len(data) > limit:
        raise MaterialError('Pub metadata exceeds the limit')
    return data.decode('utf-8')


def scalar(text):
    if text.startswith('"'):
        value = json.loads(text)
        if not isinstance(value, str):
            raise MaterialError('Expected a native lock scalar')
        return value
    if text.startswith("'"):
        if not text.endswith("'") or "'" in text[1:-1].replace("''", ''):
            raise MaterialError('Unterminated native lock scalar')
        return text[1:-1].replace("''", "'")
    if text in ('true', 'false'):
        return text == 'true'
    if not re.fullmatch(r'[a-zA-Z0-9_./:+@<>=~^ -]+', text):
        raise MaterialError('Unsupported native lock scalar')
    return text


def lock_mapping(text):
    result = {}
    stack = [(-2, result)]
    for line in text.splitlines():
        if not line.strip() or line.lstrip().startswith('#'):
            continue
        if '\t' in line:
            raise MaterialError('Noncanonical lock indentation')
        match = re.fullmatch(r'( *)([a-zA-Z0-9_.-]+):(.*)', line)
        if match is None:
            raise MaterialError('Unsupported native lock structure')
        indent, name, value = len(match[1]), match[2], match[3].strip()
        if indent % 2:
            raise MaterialError('Noncanonical lock indentation')
        while stack[-1][0] >= indent:
            stack.pop()
        if indent != stack[-1][0] + 2:
            raise MaterialError('Unexpected native lock nesting')
        parent = stack[-1][1]
        if name in parent:
            raise MaterialError('Duplicate native lock field')
        if value:
            parent[name] = scalar(value)
        else:
            parent[name] = {}
            stack.append((indent, parent[name]))
    return result


def public_url(value, hosted=False):
    if not isinstance(value, str):
        raise MaterialError('Invalid pub source URL')
    parsed = urlsplit(value)
    if (any(ord(c) < 33 for c in value) or parsed.scheme != 'https' or parsed.username or parsed.password
            or parsed.query or parsed.fragment):
        raise MaterialError('Pub sources must name accepted public HTTPS resources')
    if hosted:
        if value != 'https://pub.dev':
            raise MaterialError('Unaccepted hosted package receiver')
    elif (parsed.hostname != 'github.com'
          or not re.fullmatch(r'/[A-Za-z0-9][A-Za-z0-9_.-]*/[A-Za-z0-9][A-Za-z0-9_.-]*', parsed.path)
          or parsed.port not in (None, 443)):
        raise MaterialError('Unaccepted Git package receiver')
    return value


def read_native_lock(path):
    document = lock_mapping(read_data(path))
    if (set(document) != {'packages', 'sdks'} or not isinstance(document['packages'], dict)
            or not document['packages'] or not isinstance(document['sdks'], dict)
            or 'dart' not in document['sdks'] or set(document['sdks']) - {'dart', 'flutter'}
            or any(not isinstance(x, str) for x in document['sdks'].values())):
        raise MaterialError('Expected one nonempty native pub resolution')
    for name, package in document['packages'].items():
        if (not re.fullmatch('[a-z_][a-z0-9_]*', name) or not isinstance(package, dict)
                or set(package) != {'dependency', 'description', 'source', 'version'}
                or not isinstance(package['version'], str)
                or not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+(?:[-+][0-9A-Za-z.-]+)*', package['version'])
                or package['dependency'] not in ('direct main', 'direct dev', 'transitive')):
            raise MaterialError('Unsupported native package identity')
        source, description = package['source'], package['description']
        if source == 'hosted':
            if (not isinstance(description, dict)
                    or set(description) != {'name', 'sha256', 'url'}
                    or description['name'] != name
                    or not isinstance(description['sha256'], str)
                    or not re.fullmatch('[0-9a-f]{64}', description['sha256'])):
                raise MaterialError('Hosted package lacks an accepted content hash')
            public_url(description['url'], hosted=True)
        elif source == 'git':
            if (not isinstance(description, dict)
                    or set(description) != {'path', 'ref', 'resolved-ref', 'url'}
                    or not isinstance(description['resolved-ref'], str)
                    or not re.fullmatch('[0-9a-f]{40}', description['resolved-ref'])
                    or not isinstance(description['ref'], str)
                    or not isinstance(description['path'], str)):
                raise MaterialError('Git package lacks a fixed source object')
            public_url(description['url'])
            path_parts = description['path'].split('/')
            if description['path'] != '.' and any(x in ('', '.', '..') for x in path_parts):
                raise MaterialError('Git package path escapes its source tree')
            if '\\' in description['path'] or description['path'].startswith('/'):
                raise MaterialError('Git package path escapes its source tree')
        elif source == 'path':
            if (not isinstance(description, dict) or set(description) != {'path', 'relative'}
                    or description['relative'] is not True or not isinstance(description['path'], str)):
                raise MaterialError('Local package must use a declared relative source')
        elif source == 'sdk':
            if description not in ('flutter', 'dart'):
                raise MaterialError('Unaccepted SDK package source')
        else:
            raise MaterialError('Unaccepted native package source')
    return document


def unique_fields(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise MaterialError('Duplicate package_config field')
        result[key] = value
    return result


def uri_path(value, base):
    if not isinstance(value, str):
        raise MaterialError('Expected a package root URI')
    parsed = urlsplit(value)
    if parsed.scheme not in ('', 'file') or parsed.netloc or parsed.query or parsed.fragment:
        raise MaterialError('Package root is not a local file URI')
    decoded = unquote(parsed.path)
    if '\0' in decoded or '\\' in decoded:
        raise MaterialError('Invalid package root path')
    return Path(os.path.abspath(base / decoded))


def verify_package_config(path, expected_roots, expected_languages,
                          sdk_root=None, cache_root=None):
    config = json.loads(read_data(path), object_pairs_hook=unique_fields)
    allowed = {'configVersion', 'packages', 'generator', 'generatorVersion',
               'flutterRoot', 'flutterVersion', 'pubCache'}
    if (not isinstance(config, dict) or set(config) - allowed
            or type(config.get('configVersion')) is not int
            or config.get('configVersion') != 2 or not isinstance(config.get('packages'), list)):
        raise MaterialError('Unsupported package_config structure')
    if set(expected_roots) != set(expected_languages):
        raise MaterialError('Expected package inputs are incomplete')
    base = Path(path).absolute().parent
    observed = set()
    for entry in config['packages']:
        if (not isinstance(entry, dict)
                or set(entry) != {'name', 'rootUri', 'packageUri', 'languageVersion'}
                or not isinstance(entry['name'], str)
                or entry['name'] in observed or entry['name'] not in expected_roots):
            raise MaterialError('Extra, duplicate or malformed package_config entry')
        name = entry['name']
        observed.add(name)
        expected = Path(os.path.abspath(expected_roots[name]))
        if uri_path(entry['rootUri'], base) != expected:
            raise MaterialError('Package config selects an unaccepted source root')
        if (entry['packageUri'] != 'lib/'
                or entry['languageVersion'] != expected_languages[name]):
            raise MaterialError('Package config changes accepted loading semantics')
    if observed != set(expected_roots):
        raise MaterialError('Package config omits accepted dependencies')
    for field, expected in [('flutterRoot', sdk_root), ('pubCache', cache_root)]:
        if field in config:
            if expected is None or uri_path(config[field], base) != Path(os.path.abspath(expected)):
                raise MaterialError('Package config changes a tool or cache root')
    return {'packages_checked': len(observed), 'config_roots_match': True,
            'source_contents_verified_here': False, 'profile_ready': False}


def package_language(pubspec):
    pubspec = '\n'.join(line for line in pubspec.splitlines()
                        if not line.lstrip().startswith('#'))
    sections = re.findall(r'^environment:[ \t]*(?:#[^\n]*)?\n((?:[ \t]+[^\n]*\n|\n)*)',
                          pubspec + '\n', re.M)
    if len(sections) != 1:
        raise MaterialError('Expected one explicit package environment')
    constraints = re.findall(r'^ +sdk:[ \t]*([^\n]+)$', sections[0], re.M)
    if len(constraints) != 1:
        raise MaterialError('Expected one explicit Dart SDK constraint')
    constraint = scalar(constraints[0].split('#', 1)[0].strip())
    if not isinstance(constraint, str):
        raise MaterialError('Expected a Dart SDK version range')
    match = re.fullmatch(r'(?:\^|>=)([0-9]+)\.([0-9]+)\.[0-9]+(?:-[0-9A-Za-z.-]+)?'
                         r'(?: +<[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?)?', constraint)
    if match is None:
        raise MaterialError('Unsupported package language constraint')
    return str(int(match[1])) + '.' + str(int(match[2]))


def verify_hosted_packages(lock, cache_root, archives):
    roots = {}
    languages = {}
    with SelectedRoot(cache_root, directory=True) as cache:
        for name, package in lock['packages'].items():
            if package['source'] != 'hosted':
                continue
            identity = name + '-' + package['version']
            if identity not in archives:
                raise MaterialError('Hosted package lacks an explicitly selected accepted archive')
            path = Path(archives[identity])
            specification = {'format': 'tar.gz', 'prefix': '', 'size': path.stat().st_size,
                             'sha256': package['description']['sha256']}
            index = read_archive(path, specification)
            relative_root = 'hosted/pub.dev/' + identity
            with cache.directory_at(relative_root) as tree:
                compare_tree(tree, index)
                with tree.file('pubspec.yaml') as stream:
                    data = stream.read(4 * 1024 * 1024 + 1)
                if len(data) > 4 * 1024 * 1024:
                    raise MaterialError('Excessive accepted package pubspec')
                try:
                    languages[name] = package_language(data.decode('utf-8'))
                except MaterialError as error:
                    raise MaterialError(f'Unsupported accepted pubspec language for {identity}: {error}') from error
            roots[name] = Path(cache_root).absolute() / relative_root
    return roots, languages


def verify_git_packages(lock, cache_root, repositories, git_home):
    roots = {}
    languages = {}
    checked = set()
    with SelectedRoot(cache_root, directory=True) as cache:
        for name, package in lock['packages'].items():
            if package['source'] != 'git':
                continue
            description = package['description']
            url, commit = description['url'], description['resolved-ref']
            identity = url + '@' + commit
            if identity not in repositories:
                raise MaterialError('Git package lacks an explicitly selected fixed source repository')
            base_name = urlsplit(url).path.rsplit('/', 1)[-1].removesuffix('.git')
            checkout = 'git/' + base_name + '-' + commit
            with cache.directory_at(checkout) as tree:
                if identity not in checked:
                    index = source_index(repositories[identity], commit, git_home)
                    compare_tree(tree, index, complete=False)
                    extra = set(tree.inventory()) - set(index)
                    if any(path != '.git' and not path.startswith('.git/') for path in extra):
                        raise MaterialError('Git package checkout has unaccepted extra contents')
                    checked.add(identity)
                package_path = description['path']
                selected = nullcontext(tree) if package_path == '.' else tree.directory_at(package_path)
                with selected as package_root, package_root.file('pubspec.yaml') as stream:
                    data = stream.read(4 * 1024 * 1024 + 1)
                if len(data) > 4 * 1024 * 1024:
                    raise MaterialError('Excessive Git package pubspec')
                languages[name] = package_language(data.decode('utf-8'))
            roots[name] = Path(cache_root).absolute() / checkout / package_path
    return roots, languages


def verify_pub_graph(canonical_root, graph, graph_root, sdk_root, cache_root,
                     archives, repositories, git_home, require_plugin_map=False):
    canonical_root, graph_root = Path(canonical_root), Path(graph_root).absolute()
    sdk_root = Path(sdk_root).absolute()
    lock_paths = {'app': canonical_root / 'pubspec.lock',
                  'flutter_tools': canonical_root / 'tool/android_bootstrap/flutter_tools.pubspec.lock',
                  'distributor': canonical_root / 'tool/android_bootstrap/distributor.pubspec.lock'}
    if graph not in lock_paths:
        raise MaterialError('Unknown native pub consumer')
    lock_path = lock_paths[graph]
    if read_data(graph_root / 'pubspec.lock') != read_data(lock_path):
        raise MaterialError('Native consumer changes its accepted resolution')
    if (graph_root / 'pubspec_overrides.yaml').exists():
        raise MaterialError('Native consumer has an unaccepted pub override')
    lock = read_native_lock(lock_path)
    roots, languages = verify_hosted_packages(lock, cache_root, archives)
    git_roots, git_languages = verify_git_packages(lock, cache_root, repositories, git_home)
    roots.update(git_roots)
    languages.update(git_languages)
    with SelectedRoot(graph_root, True) as source, SelectedRoot(sdk_root, True) as sdk:
        for name, package in lock['packages'].items():
            if package['source'] == 'path':
                path = Path(os.path.abspath(graph_root / package['description']['path']))
                if not path.is_relative_to(graph_root):
                    raise MaterialError('Local package leaves the selected project source')
                relative_root = path.relative_to(graph_root).as_posix()
                selected = source.directory_at(relative_root)
            elif package['source'] == 'sdk':
                relative_root = 'packages/' + name
                try:
                    with sdk.directory_at(relative_root):
                        pass
                except FileNotFoundError:
                    relative_root = 'bin/cache/pkg/' + name
                path = sdk_root / relative_root
                selected = sdk.directory_at(relative_root)
            else:
                continue
            with selected as tree, tree.file('pubspec.yaml') as stream:
                data = stream.read(4 * 1024 * 1024 + 1)
            if len(data) > 4 * 1024 * 1024:
                raise MaterialError('Excessive local or SDK package pubspec')
            roots[name] = path
            languages[name] = package_language(data.decode('utf-8'))
    pubspec = read_data(graph_root / 'pubspec.yaml')
    names = re.findall(r'^name: ([a-z_][a-z0-9_]*)$', pubspec, re.M)
    if len(names) != 1 or names[0] in roots:
        raise MaterialError('Native consumer has an ambiguous package name')
    roots[names[0]] = graph_root
    languages[names[0]] = package_language(pubspec)
    result = verify_package_config(graph_root / '.dart_tool/package_config.json',
                                   roots, languages, sdk_root=sdk_root, cache_root=cache_root)
    result.update(graph=graph, hosted_and_git_contents_match=True,
                  local_and_sdk_source_identity='caller_precondition')
    if require_plugin_map:
        if graph != 'app':
            raise MaterialError('Only the app consumer has a Flutter plugin map')
        result['plugin_entries_checked'] = verify_plugin_map(
            graph_root / '.flutter-plugins-dependencies', roots,
        )
    return result, roots


def verify_plugin_map(path, roots):
    document = json.loads(read_data(path), object_pairs_hook=unique_fields)
    fields = {'info', 'plugins', 'dependencyGraph', 'date_created', 'version',
              'swift_package_manager_enabled'}
    if (not isinstance(document, dict) or set(document) != fields
            or not isinstance(document['plugins'], dict)
            or set(document['plugins']) != {'android', 'ios', 'linux', 'macos', 'web', 'windows'}
            or not isinstance(document['dependencyGraph'], list)):
        raise MaterialError('Unsupported native Flutter plugin map')
    count = 0
    for entries in document['plugins'].values():
        if not isinstance(entries, list):
            raise MaterialError('Expected native Flutter plugin entries')
        names = set()
        for entry in entries:
            if (not isinstance(entry, dict) or not isinstance(entry.get('name'), str)
                    or entry['name'] not in roots
                    or entry['name'] in names or not isinstance(entry.get('path'), str)
                    or not isinstance(entry.get('dependencies'), list)
                    or any(not isinstance(name, str) or name not in roots
                           for name in entry['dependencies'])):
                raise MaterialError('Extra, duplicate or malformed Flutter plugin selection')
            names.add(entry['name'])
            if Path(os.path.abspath(entry['path'])) != Path(os.path.abspath(roots[entry['name']])):
                raise MaterialError('Flutter plugin map selects an unaccepted package root')
            count += 1
    names = set()
    for entry in document['dependencyGraph']:
        if (not isinstance(entry, dict) or set(entry) != {'name', 'dependencies'}
                or not isinstance(entry['name'], str)
                or entry['name'] not in roots or entry['name'] in names
                or not isinstance(entry['dependencies'], list)
                or any(not isinstance(name, str) or name not in roots
                       for name in entry['dependencies'])):
            raise MaterialError('Flutter plugin dependency graph changes accepted package identities')
        names.add(entry['name'])
    return count
