import sys, unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

class ReleasePolicyTests(unittest.TestCase):
    def setUp(self):
        try:
            from release_policy import policy
            self.p = policy
        except ImportError:
            self.fail('The merge release policy implementation does not exist yet')

    def test_owner_identity_uses_id_not_login_or_commit_author(self):
        self.assertTrue(self.p.is_owner({'id': 229801971, 'login': '0mininseoul'}))
        self.assertFalse(self.p.is_owner({'id': 7, 'login': '0mininseoul'}))
        self.assertFalse(self.p.is_owner(None))

    def test_manifest_binds_paths_and_contents(self):
        a={'20260101000000_one.sql': 'hash-one'}
        self.assertNotEqual(self.p.manifest_digest(a), self.p.manifest_digest({'20260101000000_one.sql': 'hash-two'}))
        self.assertEqual(self.p.manifest_digest(a), self.p.manifest_digest(dict(a)))

    def test_approval_requires_exact_commit_hash_owner_and_comment(self):
        sha='a'*40; manifest='b'*64
        valid={'user':{'id':229801971},'body':f'/ping-approve-migrations {sha} {manifest}'}
        self.assertTrue(self.p.approved_comment(valid,sha,manifest))
        for change in [{'user':{'id':7}}, {'body':f'/ping-approve-migrations {"c"*40} {manifest}'}, {'body':f'quoted approval: {valid["body"]}'}]:
            self.assertFalse(self.p.approved_comment({**valid,**change},sha,manifest))

    def test_old_unapproved_migration_blocks_new_approved_migration(self):
        ledger={'20260101000000_old.sql':{'approved':False},'20260102000000_new.sql':{'approved':True}}
        ready,blocked=self.p.applicable(ledger,set())
        self.assertEqual(ready,[]);self.assertEqual(blocked,['20260102000000_new.sql'])

    def test_applied_and_unrelated_unapproved_files_are_not_reapplied(self):
        ledger={'20260101000000_old.sql':{'approved':True},'20260102000000_hold.sql':{'approved':False}}
        ready,blocked=self.p.applicable(ledger,{'20260101000000'})
        self.assertEqual((ready,blocked),([],[]))

    def test_pending_approval_never_carries_over_to_new_content(self):
        old={'sha256':'a','approved':True}; self.assertFalse(self.p.carry_approval(old,'b'))
        self.assertTrue(self.p.carry_approval(old,'a'))

    def test_safe_sql_names_reject_path_escape_and_duplicate_versions(self):
        for name in ['../20260101000000_test.sql','20260101_test.sql','20260101000000_bad.sql/secret']:
            self.assertFalse(self.p.valid_migration_name(name))
        self.assertTrue(self.p.valid_migration_name('20260101000000_test.sql'))
        with self.assertRaises(ValueError):self.p.check_unique_versions(['20260101000000_one.sql','20260101000000_two.sql'])

if __name__ == '__main__':unittest.main()
