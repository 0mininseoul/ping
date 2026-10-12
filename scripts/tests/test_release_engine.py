import copy,sys,unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
SHA='a'*40
NAME='20261012000000_example.sql'
class Effects:
    def __init__(self,fail=False):self.calls=[];self.fail=fail
    def issue(self,pr,files):self.calls.append(('issue',pr['number']));return 9
    def migrate(self,names,inventory):
        self.calls.append(('migrate',names))
        if self.fail:raise RuntimeError('Migration failed')
        return {n[:14] for n in names}
    def deploy(self,sha):self.calls.append(('deploy',sha));return 'ready'
    def status(self,*args):pass
class EngineTests(unittest.TestCase):
    def setUp(self):
        try:from release_policy import engine;self.e=engine
        except ImportError:self.fail('The coordinator engine does not exist yet')
    def pr(self,owner=True):return {'number':1,'merge_commit_sha':SHA,'merged_by':{'id':229801971 if owner else 7}}
    def state(self):return {'ledger':{},'jobs':{}}
    def test_owner_migration_finishes_before_deployment(self):
        s=self.state();f=Effects();self.e.ingest(s,self.pr(),{NAME:'hash'},{NAME},set(),f);self.e.release(s,{NAME:'hash'},set(),f)
        self.assertEqual([x[0] for x in f.calls],['migrate','deploy'])
    def test_other_merger_never_runs_sql_or_local_deploy(self):
        s=self.state();f=Effects();self.e.ingest(s,self.pr(False),{NAME:'hash'},{NAME},set(),f);self.e.release(s,{NAME:'hash'},set(),f)
        self.assertEqual(f.calls,[('issue',1)])
    def test_failed_migration_never_deploys(self):
        s=self.state();f=Effects(True);self.e.ingest(s,self.pr(),{NAME:'hash'},{NAME},set(),f)
        with self.assertRaises(RuntimeError):self.e.release(s,{NAME:'hash'},set(),f)
        self.assertNotIn('deploy',[x[0] for x in f.calls])
    def test_next_owner_merge_does_not_approve_previous_hold(self):
        s=self.state();f=Effects();self.e.ingest(s,self.pr(False),{NAME:'hash'},{NAME},set(),f)
        p={**self.pr(),'number':2,'merge_commit_sha':'b'*40};self.e.ingest(s,p,{NAME:'hash'},set(),set(),f);self.e.release(s,{NAME:'hash'},set(),f)
        self.assertFalse(s['ledger'][NAME]['approved']);self.assertFalse(any(x[0]=='migrate' for x in f.calls))
    def test_changed_applied_migration_is_rejected(self):
        s=self.state();s['ledger'][NAME]={'sha256':'old','approved':True};f=Effects()
        with self.assertRaises(ValueError):self.e.ingest(s,self.pr(),{NAME:'new'},{NAME},{NAME[:14]},f)
    def test_repeated_run_does_not_deploy_twice(self):
        s=self.state();f=Effects();self.e.ingest(s,self.pr(),{},set(),set(),f);self.e.release(s,{},set(),f);self.e.release(s,{},set(),f)
        self.assertEqual([x[0] for x in f.calls],['deploy'])
    def test_explicit_owner_comment_applies_only_exact_issue_manifest(self):
        s=self.state();f=Effects();self.e.ingest(s,self.pr(False),{NAME:'hash'},{NAME},set(),f)
        entry=s['ledger'][NAME];self.e.approve(s,entry['commit'],entry['manifest'],{'user':{'id':7},'body':f'/ping-approve-migrations {entry["commit"]} {entry["manifest"]}'})
        self.assertFalse(entry['approved'])
        self.e.approve(s,entry['commit'],entry['manifest'],{'user':{'id':229801971},'body':f'/ping-approve-migrations {entry["commit"]} {entry["manifest"]}'})
        self.assertTrue(entry['approved'])
if __name__=='__main__':unittest.main()
