"""Parse compiler records as declarations, without filesystem access or execution."""

import json
import re
import shlex


MAX_PATHS = 100000


def words(text):
    result, word = [], []
    index = 0
    while index < len(text):
        char = text[index]
        if char == '\\':
            index += 1
            if index == len(text):
                raise ValueError('Incomplete depfile escape')
            word.append(text[index])
        elif char == '$':
            if text[index:index + 2] != '$$':
                raise ValueError('Unresolved depfile variable')
            word.append('$')
            index += 1
        elif char == '#':
            break
        elif char.isspace():
            if word:
                result.append(''.join(word))
                word = []
        else:
            word.append(char)
        index += 1
    if word:
        result.append(''.join(word))
    return result


def depfile(data):
    text = data.decode('utf-8').replace('\r\n', '\n')
    if ('\r' in text or re.search(r'\\{2,}\n', text)
            or re.search(r'(?m)^\s*\.POSIX\s*:', text)):
        raise ValueError('Unsupported depfile continuation semantics')
    text = re.sub(r'[ \t]*\\\n[ \t]*', ' ', text)
    inputs, outputs = set(), set()
    saw_rule = False
    for line in text.splitlines():
        if not line.strip() or line.lstrip().startswith('#'):
            continue
        escaped = False
        for index, char in enumerate(line):
            if char == ':' and not escaped:
                saw_rule = True
                outputs.update(words(line[:index]))
                inputs.update(words(line[index + 1:]))
                break
            escaped = char == '\\' and not escaped
        else:
            raise ValueError('Depfile rule has no separator')
        if len(inputs) + len(outputs) > MAX_PATHS:
            raise ValueError('Excessive depfile declarations')
    if not outputs and (inputs or not saw_rule):
        raise ValueError('Depfile has no output declarations')
    return {'inputs': sorted(inputs), 'outputs': sorted(outputs)}


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError('Duplicate compiler record field')
        result[key] = value
    return result


def compile_commands(data):
    value = json.loads(data, object_pairs_hook=unique_object)
    if not isinstance(value, list) or len(value) > MAX_PATHS:
        raise ValueError('Expected a bounded compiler command list')
    commands = []
    for item in value:
        if (not isinstance(item, dict) or not {'directory', 'file'} <= item.keys()
                or set(item) - {'directory', 'file', 'arguments', 'command', 'output'}
                or ('arguments' in item) == ('command' in item)
                or any(not isinstance(item[key], str) or not item[key]
                       for key in ('directory', 'file'))):
            raise ValueError('Unsupported compiler command record')
        if 'arguments' in item:
            arguments = item['arguments']
            if (not isinstance(arguments, list) or not arguments
                    or any(not isinstance(arg, str) for arg in arguments)):
                raise ValueError('Invalid compiler arguments')
        else:
            if not isinstance(item['command'], str):
                raise ValueError('Invalid compiler command')
            arguments = shlex.split(item['command'])
        if not arguments or ('output' in item and not isinstance(item['output'], str)):
            raise ValueError('Incomplete compiler command')
        commands.append({'directory': item['directory'], 'inputs': [item['file']],
                         'outputs': [item['output']] if item.get('output') else [],
                         'arguments': arguments})
    return commands
