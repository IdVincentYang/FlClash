import json
import os
from pathlib import Path
import shutil
import subprocess
import unittest


def workflow(name):
    path = Path(__file__).resolve().parents[1] / '.github/workflows' / name
    try:
        import yaml
        return yaml.safe_load(path.read_text())
    except ImportError:
        if not shutil.which('ruby'): raise unittest.SkipTest('YAML parser required: PyYAML or Ruby Psych')
        result = subprocess.run(['ruby', '-rjson', '-ryaml', '-e',
                                 'puts JSON.generate(YAML.load_file(ARGV[0], aliases: true))', str(path)], capture_output=True, check=True)
        return json.loads(result.stdout)


class WorkflowBoundaryTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.release = workflow('build.yaml')
        cls.pages = workflow('pages.yaml')

    def test_secret_consumers_depend_on_successful_readonly_gate(self):
        jobs = self.release['jobs']
        for name, job in jobs.items():
            text = json.dumps(job)
            if 'secrets.' not in text and 'write' not in job.get('permissions', {}).values(): continue
            gate = 'sign_gate' if name == 'sign_android' else 'publish_gate'
            self.assertIn(gate, job['needs'], name)
            self.assertIn('needs.' + gate + ".result == 'success'", job['if'], name)
            self.assertIn('needs.' + gate + ".outputs.eligible == 'true'", job['if'], name)
            for field, context in [('run_id', 'github.run_id'), ('attempt', 'github.run_attempt'), ('commit', 'github.sha')]:
                self.assertIn('needs.' + gate + '.outputs.' + field + ' == ' + context, job['if'], name)
                self.assertEqual(jobs[gate]['outputs'][field], '${{ steps.gate.outputs.' + field + ' }}')
            self.assertIn("github.ref_type == 'tag'", job['if'], name)
            self.assertNotIn('always()', job['if'], name)
        for name in ('release_gate', 'sign_gate', 'publish_gate'):
            self.assertEqual(jobs[name].get('permissions', self.release['permissions']), {'contents': 'read', 'actions': 'read'})
            self.assertNotIn('secrets.', json.dumps(jobs[name]))
        self.assertIn('TELEGRAM_API_ID', jobs['publish_telegram']['services']['telegram-bot-api']['env'])
        for name in ('build', 'notes'):
            self.assertNotIn('secrets.', json.dumps(jobs[name]))
            self.assertNotIn('write', json.dumps(jobs[name].get('permissions', self.release['permissions'])))
        steps = jobs['sign_android']['steps']
        verify = next(i for i, step in enumerate(steps) if 'verify-android-candidate' in step.get('run', ''))
        secret_steps = [i for i, step in enumerate(steps) if 'secrets.' in json.dumps(step)]
        self.assertEqual(len(secret_steps), 1)
        self.assertLess(verify, secret_steps[0])
        for name in ('publish_tap', 'publish_fdroid'):
            consumers = [step for step in jobs[name]['steps'] if 'secrets.' in json.dumps(step)]
            self.assertEqual(len(consumers), 1)
            self.assertIn('python tool/ci_push.py --target', consumers[0]['run'])

    def test_fixed_actions_checkout_and_unique_matrix_outputs(self):
        for document in (self.release, self.pages):
            for name, job in document['jobs'].items():
                for step in job.get('steps', []):
                    if 'uses' not in step: continue
                    self.assertRegex(step['uses'], r'^[\w.-]+/[\w./-]+@[0-9a-f]{40}$', name)
                    if step['uses'].startswith('actions/checkout@'):
                        self.assertIs(step['with']['persist-credentials'], False, name)
        build = self.release['jobs']['build']
        slots = {item['role'].replace('-', '_') for item in build['strategy']['matrix']['include']}
        self.assertEqual(len(slots), 7)
        self.assertEqual(set(build['outputs']), {slot + suffix for slot in slots for suffix in ('_id', '_sha256', '_attempt')})
        for name, value in build['outputs'].items(): self.assertIn('steps.bind.outputs.' + name, value)
        self.assertNotIn('merge-multiple', json.dumps(self.release))
        self.assertNotIn('cpina/', json.dumps(self.release))
        self.assertRegex(self.release['jobs']['publish_telegram']['services']['telegram-bot-api']['image'], r'@sha256:[0-9a-f]{64}$')

    def test_pages_only_deployment_has_write_and_has_no_checkout_or_site_execution(self):
        jobs = self.pages['jobs']
        for name, job in jobs.items():
            permissions = job.get('permissions', self.pages['permissions'])
            if name == 'pages_deploy':
                self.assertEqual(permissions, {'actions': 'read', 'pages': 'write', 'id-token': 'write'})
                self.assertIn('pages_deploy_gate', job['needs'])
                self.assertIn("needs.pages_deploy_gate.outputs.eligible == 'true'", job['if'])
                for field, context in [('run_id', 'github.run_id'), ('attempt', 'github.run_attempt'), ('commit', 'github.sha')]:
                    self.assertIn('needs.pages_deploy_gate.outputs.' + field + ' == ' + context, job['if'])
                    self.assertEqual(jobs['pages_deploy_gate']['outputs'][field], '${{ steps.gate.outputs.' + field + ' }}')
                self.assertNotIn('actions/checkout', json.dumps(job))
                self.assertNotIn('build_site.sh', json.dumps(job))
            else:
                self.assertNotIn('write', json.dumps(permissions))
        self.assertEqual(jobs['pages_build']['steps'][0]['with']['ref'], '${{ needs.pages_gate.outputs.checkout_sha }}')
        deploy = jobs['pages_deploy']['steps'][-1]
        self.assertEqual(deploy['with']['artifact_name'], '${{ needs.pages_deploy_gate.outputs.artifact_name }}')

    @unittest.skipUnless(shutil.which('node'), 'Node required for actual inline deployment consumer')
    def test_actual_pages_node_consumer_rejects_wrong_id_attempt_and_incomplete_api(self):
        step = self.pages['jobs']['pages_deploy']['steps'][0]
        script = step['run'].split("<<'JS'\n", 1)[1].rsplit('\nJS', 1)[0]
        environment = {key: value for key, value in os.environ.items() if key in ('PATH', 'HOME', 'TMPDIR')}
        environment.update(GITHUB_RUN_ID='12', GITHUB_RUN_ATTEMPT='2', GITHUB_REPOSITORY_ID='42',
                           GITHUB_SHA='a' * 40, EXPECTED_ID='99', EXPECTED_NAME='pages-12-2',
                           EXPECTED_SHA256='b' * 64, GH_TOKEN='synthetic-only-token')
        artifact = {'id': 99, 'name': 'pages-12-2', 'expired': False, 'digest': 'sha256:' + 'b' * 64,
                    'workflow_run': {'id': 12, 'repository_id': 42, 'head_repository_id': 42, 'head_sha': 'a' * 40}}
        cases = [('accepted', {'total_count': 1, 'artifacts': [artifact]}, {}, 0),
                 ('old-attempt', {'total_count': 1, 'artifacts': [dict(artifact, name='pages-12-1')]}, {}, 1),
                 ('wrong-id', {'total_count': 1, 'artifacts': [dict(artifact, id=100)]}, {}, 1),
                 ('duplicate-name', {'total_count': 2, 'artifacts': [artifact, artifact]}, {}, 1),
                 ('pagination-empty', {'total_count': 2, 'artifacts': []}, {}, 1),
                 ('old-output', {'total_count': 1, 'artifacts': [artifact]}, {'EXPECTED_NAME': 'pages-12-1'}, 1)]
        for name, facts, changed, expected in cases:
            with self.subTest(case=name):
                prefix = ('globalThis.fetch=async(url,options)=> { '
                          'if(url!=="https://api.github.com/repos/chen08209/FlClash/actions/runs/12/artifacts?per_page=100&page=1" || '
                          'options.headers.Authorization!=="Bearer synthetic-only-token" || options.redirect!=="error") throw Error(); '
                          'return {ok:true,json:async()=>(' + json.dumps(facts) + ')}; };\n')
                result = subprocess.run(['node', '--input-type=module'], input=(prefix + script).encode(),
                                        env=dict(environment, **changed), capture_output=True, timeout=10)
                self.assertEqual(result.returncode, expected, result.stderr.decode())
                self.assertNotIn(b'synthetic-only-token', result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
