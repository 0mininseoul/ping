"""Credential-free approval decisions; this module never runs SQL or repository code."""
import hashlib
import json
import re

OWNER_ID = 229801971
REPO_ID = 1241650801
REPO = '0mininseoul/ping'
PROJECT_REF = 'qxjtprxvjmaxlbtljcjw'


def is_owner(user):
    return isinstance(user, dict) and user.get('id') == OWNER_ID


def valid_migration_name(name):
    return bool(re.fullmatch(r'[0-9]{14}_[A-Za-z0-9_-]+\.sql', name))


def check_unique_versions(names):
    versions = []
    for name in names:
        if not valid_migration_name(name):
            raise ValueError('Invalid migration filename')
        versions.append(name[:14])
    if len(versions) != len(set(versions)):
        raise ValueError('Duplicate migration versions')


def manifest_digest(files):
    return hashlib.sha256(json.dumps(files, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def approved_comment(comment, commit, manifest):
    return (is_owner(comment.get('user')) and
            comment.get('body', '').strip() == f'/ping-approve-migrations {commit} {manifest}')


def carry_approval(previous, sha256):
    return previous.get('sha256') == sha256 and previous.get('approved') is True


def applicable(ledger, applied):
    ready, blocked = [], []
    waiting = False
    for name, entry in sorted(ledger.items()):
        if name[:14] in applied:
            continue
        if not entry['approved']:
            waiting = True
        elif waiting:
            blocked.append(name)
        else:
            ready.append(name)
    return ready, blocked
