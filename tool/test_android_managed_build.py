import os
from pathlib import Path
import subprocess
import shutil
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

from android_input_materials import MaterialError
from android_managed_build import BuildWorkspace


class WorkspaceTest(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp(prefix='android-workspace-test-'))
        self.original = self.root / 'original-config'
        self.original.write_bytes(b'preserve original')
        self.workspace = BuildWorkspace(self.root / 'owned')
        self.env = {'PATH': '/usr/bin:/bin', 'HOME': str(self.workspace.root)}
        self.addCleanup(self.cleanup_owned_fixture)

    def cleanup_owned_fixture(self):
        deadline = time.monotonic() + 3
        for command in self.workspace.commands:
            while True:
                try:
                    os.killpg(command['pid'], 0)
                except ProcessLookupError:
                    break
                if time.monotonic() >= deadline:
                    self.fail(f'Owned fixture group remains active; retained {self.root}')
                time.sleep(0.02)
        shutil.rmtree(self.root)

    def test_success_keeps_owned_files_and_never_reclaims_an_existing_position(self):
        result = self.workspace.run([sys.executable, '-c', 'print("owned")'],
                                    self.workspace.root, self.env, 'positive')
        self.assertTrue(result['process_group_empty'])
        self.assertTrue((self.workspace.logs / 'positive.log').exists())
        with self.assertRaises(FileExistsError):
            BuildWorkspace(self.workspace.root)
        self.assertEqual(self.original.read_bytes(), b'preserve original')

    def test_parent_exit_does_not_allow_reclaim_while_grandchild_can_write(self):
        late = self.workspace.root / 'late-write'
        script = (
            'import subprocess,sys; '
            'subprocess.Popen([sys.executable,"-c",'
            f'"import time;time.sleep(0.15);open({str(late)!r},\'w\').write(\'late\')"])'
        )
        with self.assertRaises(MaterialError):
            self.workspace.run([sys.executable, '-c', script], self.workspace.root,
                               self.env, 'late-writer')
        deadline = time.monotonic() + 3
        while not late.exists() and time.monotonic() < deadline:
            time.sleep(0.02)
        self.assertTrue(late.exists())
        self.assertTrue(self.workspace.root.exists())
        self.assertEqual(self.original.read_bytes(), b'preserve original')

    def test_interruption_retains_position_until_the_known_child_has_exited(self):
        original_wait = subprocess.Popen.wait

        def interrupted(process, *args, **kwargs):
            if process.poll() is None:
                raise KeyboardInterrupt()
            return original_wait(process, *args, **kwargs)

        with patch.object(subprocess.Popen, 'wait', interrupted):
            with self.assertRaises(KeyboardInterrupt):
                self.workspace.run([sys.executable, '-c', 'import time;time.sleep(0.2)'],
                                   self.workspace.root, self.env, 'interrupted')
        child = self.workspace.children[0]
        child.wait(timeout=3)
        self.assertTrue(self.workspace.root.exists())
        self.assertTrue(self.workspace.commands[0]['exit_not_proven'])
        self.assertEqual(self.original.read_bytes(), b'preserve original')


if __name__ == '__main__':
    unittest.main()
