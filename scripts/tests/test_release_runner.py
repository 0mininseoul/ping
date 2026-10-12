import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from release_policy import runner

NAME='20261012000000_example.sql'
SHA='a'*40


class RunnerTests(unittest.TestCase):
    def test_remote_success_is_saved_before_new_pr_can_change_sql(self):
        with tempfile.TemporaryDirectory() as directory:
            home=Path(directory)
            (home/'config.json').write_text(json.dumps({'gh':'fake','git':'fake'}))
            state={'cutoff':'2026-10-12T00:00:00Z','ledger':{NAME:{'sha256':'old','approved':True,'issue':None}},
                   'jobs':{},'seen':[],'applied':[]}
            runner.save(home/'state.json',state)
            with patch.object(runner,'GitHub') as github,patch.object(runner,'Repository') as repository,patch.object(runner,'Infrastructure') as infrastructure:
                github.return_value.merged_since.return_value=[{'number':1,'merge_commit_sha':SHA,'merged_by':{'id':229801971}}]
                github.return_value.changed.return_value={NAME}
                repository.return_value.head.return_value=SHA
                repository.return_value.inventory.return_value={NAME:'changed'}
                infrastructure.return_value.history.return_value={NAME[:14]}
                with self.assertRaisesRegex(ValueError,'applied migration was changed'):
                    runner.tick(home)
                saved=json.loads((home/'state.json').read_text())
                self.assertEqual(saved['applied'],[NAME[:14]])
                self.assertEqual(saved['ledger'][NAME]['sha256'],'old')
                self.assertEqual(saved['seen'],[])
                infrastructure.return_value.migrate.assert_not_called()
                infrastructure.return_value.deploy.assert_not_called()


if __name__=='__main__':unittest.main()
