"""Local Keychain management and fixed-project Vercel deployment adapters."""
import hashlib
import json
import re
from pathlib import Path
import subprocess
import tempfile
from .policy import PROJECT_REF


class Infrastructure:
    def __init__(self, config, home, repo, github, state):
        self.config,self.home,self.repo,self.github,self.state=config,Path(home),repo,github,state
        self.current_sha=repo.head()

    def history(self):
        token=subprocess.run(['/usr/bin/security','find-generic-password','-s','Ping Supabase Management (local)','-a',PROJECT_REF,'-w'],capture_output=True,text=True)
        if token.returncode:raise RuntimeError('This Mac management Keychain entry is unavailable')
        query={'query':'select version from supabase_migrations.schema_migrations order by version'}
        config='header = '+json.dumps('Authorization: Bearer '+token.stdout.strip())+'\nheader = "Content-Type: application/json"\ndata = '+json.dumps(json.dumps(query))+'\n'
        r=subprocess.run(['/usr/bin/curl','-sS','--fail-with-body','--max-time','30','--config','-',f'https://api.supabase.com/v1/projects/{PROJECT_REF}/database/query'],input=config,capture_output=True,text=True)
        if r.returncode:raise RuntimeError('This Mac Supabase history query failed; check scoped token expiry')
        data=json.loads(r.stdout)
        if not isinstance(data,list):raise RuntimeError('Invalid migration history response')
        return {row['version'] for row in data}

    def issue(self,pr,files):return self.github.issue(pr,files)
    def status(self,*args):return self.github.status(*args)

    def migrate(self,names,inventory):
        # Only applied files and exact approved hashes enter the CLI workdir.
        applied=self.history()
        included={name for name in inventory if name[:14] in applied}|set(names)
        with tempfile.TemporaryDirectory(prefix='migration-',dir=self.home/'work') as folder:
            root=Path(folder);target=root/'supabase/migrations';target.mkdir(parents=True)
            (root/'supabase/config.toml').write_text('project_id = "ping"\n')
            cache=root/'supabase/.temp';cache.mkdir()
            for f in ('project-ref','pooler-url'):
                source=self.home/'supabase/.temp'/f
                if source.exists():(cache/f).write_bytes(source.read_bytes())
            for name in sorted(included):
                blob=self.repo.sql(self.current_sha,name)
                if hashlib.sha256(blob).hexdigest()!=inventory[name]:raise ValueError('SQL approval hash mismatch')
                if name in names and not self.state['ledger'][name]['approved']:raise ValueError('Unapproved SQL reached CLI')
                (target/name).write_bytes(blob)
            args=['/bin/bash',str(self.home/'scripts/supabase-ping.sh'),'db','push','--workdir',str(root),'--yes']
            r=subprocess.run(args,capture_output=True,text=True,timeout=1200,env=self.config['environment'])
            if r.returncode:raise RuntimeError('Approved Supabase db push failed; Vercel deployment is held')
        return self.history()

    def deploy(self,sha):
        # Never roll production back to a superseded merge.
        self.repo.fetch()
        if self.repo.head()!=sha:return 'superseded'
        with tempfile.TemporaryDirectory(prefix='deploy-',dir=self.home/'work') as folder:
            self.repo.export_web(sha,folder)
            link=Path(folder)/'.vercel';link.mkdir()
            (link/'project.json').write_text(json.dumps({'orgId':'team_USVQhzAzs57gIGsmuHIRKv3f','projectId':'prj_Vhsw7XfpQhld1jYkXP58KNFlkPlu','projectName':'ping'}))
            # Remove Git-only ignoreCommand. This path runs only after verified SQL success.
            config=Path(folder)/'vercel.json';j=json.loads(config.read_text());j.pop('ignoreCommand',None);config.write_text(json.dumps(j))
            command=[self.config['vercel'],'deploy','--prod','--yes','--scope','0minseouls-projects','--skip-domain','--meta',f'githubCommitSha={sha}']
            r=subprocess.run(command,cwd=folder,capture_output=True,text=True,timeout=1200,env=self.config['environment'])
            if r.returncode:raise RuntimeError('Vercel release failed; migration success retained for retry')
            urls=re.findall(r'https://ping-[a-z0-9-]+\.vercel\.app',r.stdout+'\n'+r.stderr)
            deployment=None
            for url in reversed(urls):
                check=subprocess.run([self.config['vercel'],'api',f'/v13/deployments/{url.removeprefix("https://")}', '--scope','0minseouls-projects','--raw'],capture_output=True,text=True,env=self.config['environment'],timeout=60)
                if check.returncode:continue
                try:metadata=json.loads(check.stdout)
                except ValueError:continue
                if metadata.get('projectId')=='prj_Vhsw7XfpQhld1jYkXP58KNFlkPlu' and metadata.get('meta',{}).get('githubCommitSha')==sha and metadata.get('readyState')=='READY':
                    deployment=url;break
            if not deployment:raise RuntimeError('Cannot verify staged Vercel project, commit and readiness')
            self.repo.fetch()
            if self.repo.head()!=sha:return 'superseded'
            promote=subprocess.run([self.config['vercel'],'promote',deployment,'--yes','--scope','0minseouls-projects'],capture_output=True,text=True,env=self.config['environment'],timeout=120)
            if promote.returncode:raise RuntimeError('Verified production deployment could not be promoted')
        return 'released'
