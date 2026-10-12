"""Idempotent state transitions separated from network and credentials."""
from .policy import applicable, approved_comment, carry_approval, check_unique_versions, is_owner, manifest_digest


def ingest(state, pr, inventory, changed, applied, effects):
    check_unique_versions(inventory)
    ledger = state['ledger']
    for name, old in list(ledger.items()):
        if name[:14] in applied and inventory.get(name) != old['sha256']:
            raise ValueError('An applied migration was changed or removed')
        if name not in inventory:
            del ledger[name]
    files = {name: digest for name, digest in inventory.items() if name in changed and name[:14] not in applied}
    fingerprint = manifest_digest(files)
    owner = is_owner(pr.get('merged_by'))
    for name, digest in inventory.items():
        old = ledger.get(name)
        if old and old['sha256'] == digest:
            if name in files and owner:
                old['approved'] = True
            continue
        ledger[name] = {'sha256': digest, 'approved': name[:14] in applied or (name in changed and owner),
                        'commit': pr['merge_commit_sha'], 'pr': pr['number'], 'manifest': fingerprint, 'issue': None}
    if not owner and files:
        issue = effects.issue(pr, files)
        for name in files:
            ledger[name].update(issue=issue,commit=pr['merge_commit_sha'],manifest=fingerprint,pr=pr['number'])
    if owner:
        state['jobs'].setdefault(pr['merge_commit_sha'], {'status':'pending','pr':pr['number'],'files':files})


def approve(state, commit, manifest, comment):
    if not approved_comment(comment, commit, manifest):
        return False
    matching = {n:e['sha256'] for n,e in state['ledger'].items() if e.get('commit') == commit and e.get('manifest') == manifest}
    if not matching or manifest_digest(matching) != manifest:
        return False
    for name in matching:
        state['ledger'][name]['approved'] = True
    return True


def release(state, inventory, applied, effects):
    ready, blocked = applicable(state['ledger'], applied)
    pending = [(sha,j) for sha,j in state['jobs'].items() if j['status'] == 'pending']
    if blocked:
        for sha, job in pending:
            effects.status(sha, 'pending', 'Approved SQL waits for earlier unapproved migrations')
        return applied
    if ready:
        migrated = effects.migrate(ready, inventory)
        required = {n[:14] for n in ready}
        if not required.issubset(migrated):
            raise RuntimeError('Remote migration history did not confirm success')
        applied = applied | migrated
    for sha, job in pending:
        if any(inventory.get(n) != digest for n,digest in job['files'].items()):
            effects.status(sha, 'failure', 'Migration contents changed after this merge')
            job['status'] = 'superseded'
            continue
        if not {n[:14] for n in job['files']}.issubset(applied):
            continue
        effects.status(sha, 'success', 'Approved migrations verified; releasing Vercel')
        job['status'] = effects.deploy(sha)
    return applied
