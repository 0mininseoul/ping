#!/usr/bin/env python3
"""Explicit local installation. Never run this from unreviewed repository code."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import urllib.parse

root=Path(__file__).resolve().parent.parent
home=Path.home()/'Library/Application Support/Ping Release Coordinator'
if (home/'state.json').exists():raise SystemExit('Existing coordinator preserved. Review and update its code explicitly; do not reset approval state.')
home.mkdir(parents=True,exist_ok=True);home.chmod(0o700)
for directory in ['scripts','work','supabase/.temp']:(home/directory).mkdir(parents=True,exist_ok=True)
shutil.copytree(root/'scripts/release_policy',home/'scripts/release_policy',ignore=shutil.ignore_patterns('__pycache__'),dirs_exist_ok=True)
shutil.copy2(root/'scripts/supabase-ping.sh',home/'scripts/supabase-ping.sh')
main=Path(subprocess.check_output(['git','-C',str(root),'rev-parse','--git-common-dir'],text=True).strip()).resolve().parent
cache=main/'supabase/.temp'
ref=(cache/'project-ref').read_text().strip()
if ref!='qxjtprxvjmaxlbtljcjw':raise SystemExit('Primary cached project link is not Ping')
url=(cache/'pooler-url').read_text().strip();parsed=urllib.parse.urlparse(url)
if parsed.password or 'qxjtprxvjmaxlbtljcjw' not in (parsed.username or ''):raise SystemExit('Unsafe pooler metadata')
for name in ['project-ref','pooler-url']:shutil.copy2(cache/name,home/'supabase/.temp'/name)
# Preserve only runtime configuration, never a snapshot of arbitrary environment secrets.
environment={'PATH':os.environ['PATH'],'HOME':str(Path.home()),'LANG':'en_US.UTF-8','PYTHONDONTWRITEBYTECODE':'1'}
config={name:shutil.which(name) for name in ['gh','git','vercel']};config['environment']=environment
if not all(config[name] for name in ['gh','git','vercel']):raise SystemExit('Required trusted CLIs unavailable')
(home/'config.json').write_text(json.dumps(config,indent=2));(home/'config.json').chmod(0o600)
result=subprocess.run([shutil.which('python3'),str(home/'scripts/release_policy/runner.py'),'--initialize'])
raise SystemExit(result.returncode)
