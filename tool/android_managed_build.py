"""Own the files and child processes of one managed Android build."""

import json
import os
from pathlib import Path
import subprocess

from android_input_materials import MaterialError


class BuildWorkspace:
    def __init__(self, path):
        path = Path(path).absolute()
        self.root = path.parent.resolve(strict=True) / path.name
        self.root.mkdir(mode=0o700)
        self.logs = self.root / 'logs'
        self.logs.mkdir()
        self.children = []
        self.commands = []
        self.record()

    def record(self):
        (self.root / 'commands.json').write_text(json.dumps({
            'workspace_retained': True, 'commands': self.commands,
        }, indent=2) + '\n')

    def run(self, command, cwd, environment, label):
        if not label.replace('-', '').replace('_', '').isalnum():
            raise MaterialError('Invalid owned command label')
        with (self.logs / (label + '.log')).open('xb') as log:
            process = subprocess.Popen(command, cwd=cwd, env=environment,
                                       stdin=subprocess.DEVNULL, stdout=log,
                                       stderr=subprocess.STDOUT, start_new_session=True)
            self.children.append(process)
            record = {'command': [str(value) for value in command], 'cwd': str(cwd),
                      'pid': process.pid, 'label': label, 'exit_code': None}
            self.commands.append(record)
            self.record()
            try:
                record['exit_code'] = process.wait()
            except BaseException:
                record['exit_not_proven'] = True
                self.record()
                raise
        try:
            os.killpg(process.pid, 0)
        except ProcessLookupError:
            record['process_group_empty'] = True
        else:
            record['process_group_empty'] = False
            self.record()
            raise MaterialError('Owned child group remains active; workspace retained')
        self.record()
        if record['exit_code']:
            raise MaterialError(f'Owned command failed: {label}; workspace retained')
        return record
