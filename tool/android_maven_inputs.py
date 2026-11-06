"""Check selected raw Maven data against the native Gradle acceptance metadata."""

import os
import re
import xml.etree.ElementTree as ET

from android_input_materials import MaterialError, SelectedRoot, hash_stream, relative


NAMESPACE = 'https://schema.gradle.org/dependency-verification'


def maven_references(path):
    with SelectedRoot(path, directory=False) as selected, selected.file() as stream:
        data = stream.read(4 * 1024 * 1024 + 1)
    if len(data) > 4 * 1024 * 1024 or b'<!DOCTYPE' in data or b'<!ENTITY' in data:
        raise MaterialError('Unsupported verification metadata document')
    try:
        root = ET.fromstring(data)
    except ET.ParseError as error:
        raise MaterialError('Malformed native Gradle verification metadata') from error
    tag = lambda name: '{' + NAMESPACE + '}' + name
    if root.tag != tag('verification-metadata'):
        raise MaterialError('Expected native Gradle verification metadata')
    configurations = root.findall(tag('configuration'))
    components = root.findall(tag('components'))
    if len(configurations) != 1 or len(components) != 1:
        raise MaterialError('Expected one native verification configuration and component set')
    config = configurations[0]
    if any(node.tag not in {tag(name) for name in (
            'verify-metadata', 'verify-signatures', 'key-servers', 'trusted-keys')}
           for node in config):
        raise MaterialError('Unaccepted Maven verification configuration')
    for name in ('verify-metadata', 'verify-signatures'):
        nodes = config.findall(tag(name))
        if len(nodes) != 1 or nodes[0].text != 'true':
            raise MaterialError('Managed Maven inputs require metadata and signature verification')
    servers = config.findall(tag('key-servers'))
    if len(servers) != 1 or servers[0].attrib != {'enabled': 'false'}:
        raise MaterialError('Managed verification cannot discover new accepted keys online')
    if config.find(tag('trusted-artifacts')) is not None:
        raise MaterialError('Unverified artifact exemptions are not accepted')
    if config.find(tag('ignored-keys')) is not None:
        raise MaterialError('Signature exemptions are not accepted')
    for key in config.findall(tag('trusted-keys') + '/' + tag('trusted-key')):
        if (set(key.attrib) != {'id', 'group', 'name', 'version'} or len(key)
                or not re.fullmatch('[0-9a-fA-F]{40}', key.attrib['id'])
                or any(not key.attrib[name] for name in ('group', 'name', 'version'))):
            raise MaterialError('Accepted PGP keys require full fingerprints and finite component scope')
    references = {}
    for component in components[0]:
        if component.tag != tag('component') or set(component.attrib) != {'group', 'name', 'version'}:
            raise MaterialError('Unexpected Maven component identity')
        group, name, version = (component.attrib[key] for key in ('group', 'name', 'version'))
        if any(not re.fullmatch('[A-Za-z0-9_+-][A-Za-z0-9_.+-]*', part)
               for part in [*group.split('.'), name, version]):
            raise MaterialError('Invalid finite Maven component coordinates')
        for artifact in component:
            if artifact.tag != tag('artifact') or set(artifact.attrib) != {'name'}:
                raise MaterialError('Unexpected Maven artifact identity')
            filename = relative(artifact.attrib['name'])
            if '/' in filename:
                raise MaterialError('Maven artifact name is not a filename')
            if any(node.tag not in {tag('sha256'), tag('pgp')} for node in artifact):
                raise MaterialError('Unaccepted artifact verification alternatives')
            fingerprints = set()
            for key in artifact.findall(tag('pgp')):
                fingerprint = key.get('value', '')
                if (set(key.attrib) != {'value'} or len(key)
                        or not re.fullmatch('[0-9a-fA-F]{40}', fingerprint)
                        or fingerprint.lower() in fingerprints):
                    raise MaterialError('Artifact PGP acceptance needs unique full fingerprints')
                fingerprints.add(fingerprint.lower())
            hashes = artifact.findall(tag('sha256'))
            if (len(hashes) != 1 or len(hashes[0])
                    or not re.fullmatch('[0-9a-f]{64}', hashes[0].get('value', ''))):
                raise MaterialError('Every raw Maven artifact needs one accepted SHA256')
            path = '/'.join([group.replace('.', '/'), name, version, filename])
            if path in references:
                raise MaterialError('Duplicate Maven acceptance reference')
            references[path] = hashes[0].attrib['value']
    return references


def verify_maven_files(metadata, selected_root, files):
    references = maven_references(metadata)
    if not isinstance(files, dict):
        raise MaterialError('An explicit raw Maven selection map is required')
    with SelectedRoot(selected_root, directory=True) as root:
        for coordinate_path, selected_path in files.items():
            relative(coordinate_path)
            if coordinate_path not in references:
                raise MaterialError('Selected Maven artifact has no accepted reference')
            with root.file(selected_path) as stream:
                size = os.fstat(stream.fileno()).st_size
                if hash_stream(stream, size) != references[coordinate_path]:
                    raise MaterialError('Raw Maven bytes differ from the accepted artifact')
    return {'raw_artifacts_checked': len(files), 'profile_ready': False,
            'gradle_internal_cache_accepted': False}


def verify_native_metadata(canonical_directory, consumer_directory):
    with SelectedRoot(canonical_directory, True) as canonical:
        with SelectedRoot(consumer_directory, True) as consumer:
            for name in ('verification-metadata.xml', 'verification-keyring.keys'):
                with canonical.file(name) as reference, consumer.file(name) as selected:
                    size = os.fstat(reference.fileno()).st_size
                    if size > 4 * 1024 * 1024:
                        raise MaterialError('Excessive native verification input')
                    if hash_stream(reference, size) != hash_stream(selected, size):
                        raise MaterialError('Native Gradle would consume a different acceptance root')
    return {'native_metadata_matches_canonical': True, 'profile_ready': False}
