"""One trusted Mac coordinator tick. Scheduler invokes this installed file, never Git code."""
import argparse
from datetime import datetime,timezone
import fcntl
import json
import os
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from release_policy import engine
from release_policy.github import GitHub
from release_policy.infrastructure import Infrastructure
from release_policy.repository import Repository
from release_policy.policy import REPO,PROJECT_REF


def save(path,state):
    temporary=path.with_suffix('.next');temporary.write_text(json.dumps(state,indent=2));temporary.chmod(0o600);temporary.replace(path)


def tick(home,initialize=False):
    home=Path(home);config=json.loads((home/'config.json').read_text());statefile=home/'state.json'
    with (home/'run.lock').open('a') as lock:
        try:fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        except BlockingIOError:return {'status':'busy'}
        github=GitHub(config['gh']);repo=Repository(config['git'],home/'repo.git');repo.fetch();sha=repo.head();inventory=repo.inventory(sha)
        if initialize:
            if statefile.exists():raise RuntimeError('Coordinator is already initialized; no approval reset allowed')
            state={'cutoff':datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),'ledger':{},'jobs':{},'seen':[],'applied':[]}
            infra=Infrastructure(config,home,repo,github,state);applied=infra.history()
            if applied!={n[:14] for n in inventory}:raise RuntimeError('Initialization requires current Git and database versions to match; review existing pending migrations first')
            state['applied']=sorted(applied)
            state['ledger']={n:{'sha256':v,'approved':True,'issue':None} for n,v in inventory.items()}
            save(statefile,state);return {'status':'initialized','applied':len(applied),'baseline':sha}
        state=json.loads(statefile.read_text());infra=Infrastructure(config,home,repo,github,state);applied=set(state['applied'])
        changed=False
        try:
            new_prs=[pr for pr in github.merged_since(state['cutoff']) if pr['number'] not in state['seen']]
            if new_prs:
                applied=engine.reconcile_history(state,infra.history())
                save(statefile,state)
            for pr in new_prs:
                snapshot=repo.inventory(pr['merge_commit_sha'])
                engine.ingest(state,pr,snapshot,github.changed(pr['number']),applied,infra)
                state['seen'].append(pr['number']);changed=True;save(statefile,state)
            if inventory != {n:e['sha256'] for n,e in state['ledger'].items()}:
                raise ValueError('main contains SQL changes not tied to a verified merged PR')
            groups={}
            for entry in state['ledger'].values():
                if entry.get('issue') and not entry['approved']:
                    groups[entry['issue']]=(entry['commit'],entry['manifest'])
            for issue,(commit,manifest) in groups.items():
                comments=github.api(f'issues/{issue}/comments?per_page=100',pages=True)
                for comment in comments:
                    if engine.approve(state,commit,manifest,comment):changed=True;save(statefile,state);break
            pending=[e for n,e in state['ledger'].items() if e['approved'] and n[:14] not in applied]
            jobs=[j for j in state['jobs'].values() if j['status']=='pending']
            if pending or jobs:
                before=json.dumps(state,sort_keys=True)
                applied=engine.reconcile_history(state,infra.history())
                save(statefile,state)
                applied=engine.release(state,inventory,applied,infra,lambda:save(statefile,state));state['applied']=sorted(applied);changed=changed or before!=json.dumps(state,sort_keys=True);save(statefile,state)
                for issue in {e.get('issue') for e in state['ledger'].values()}-{None}:
                    entries=[(n,e) for n,e in state['ledger'].items() if e.get('issue')==issue]
                    if entries and all(e['approved'] and n[:14] in applied for n,e in entries):
                        current=github.api(f'issues/{issue}')
                        if current['state']!='closed':github.api(f'issues/{issue}','PATCH',{'state':'closed','state_reason':'completed'})
            return {'status':'processed' if changed else 'unchanged','pending_migrations':sum(n[:14] not in applied for n in state['ledger']),
                    'pending_owner_releases':sum(j['status']=='pending' for j in state['jobs'].values())}
        except Exception as error:
            save(statefile,state)
            # No raw CLI/auth output is sent to GitHub or scheduler logs.
            for commit,job in state['jobs'].items():
                if job['status']=='pending':
                    try:github.status(commit,'failure',str(error))
                    except Exception:pass
            raise


if __name__=='__main__':
    args=argparse.ArgumentParser();args.add_argument('--home',default=str(Path(__file__).resolve().parents[2]));args.add_argument('--initialize',action='store_true');parsed=args.parse_args()
    try:print(json.dumps(tick(parsed.home,parsed.initialize)))
    except Exception as error:print(json.dumps({'status':'failed','reason':str(error)}));sys.exit(1)
