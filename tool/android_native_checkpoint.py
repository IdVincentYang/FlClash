"""Inspect actual outputs inside the current managed Native Assets invocation."""

import argparse
import json
from pathlib import Path
import re
import sys

from android_hook_environment import check_hook_outputs, read_hook_context
from android_input_materials import MaterialError, SelectedRoot


def inspect(workspace):
    root = Path(workspace).resolve(strict=True)
    with SelectedRoot(root, True) as selected, selected.file('source/tool/android_hook_binding.dart') as stream:
        binding = stream.read(4097)
    if len(binding) > 4096:
        raise MaterialError('Excessive owned hook binding')
    match = re.search(rb"const String\? androidHookContextDigest = '([0-9a-f]{64})';", binding)
    if not match:
        raise MaterialError('Missing current compiled hook binding')
    digest = match[1].decode()
    context = read_hook_context(root / 'hook-environment.json', digest, 'setup', root / 'source')
    outputs = check_hook_outputs(root, digest, context['request_sha256'])
    return {hook: record['generated'] for hook, record in outputs.items()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('workspace')
    args = parser.parse_args()
    try:
        print(json.dumps(inspect(args.workspace), sort_keys=True))
    except (MaterialError, OSError, ValueError, TypeError, KeyError):
        print('Managed Native Assets output inspection failed', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
