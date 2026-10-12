"""GitHub metadata and explicitly requested owner-assigned issues; no repo execution."""
import json
import subprocess
from .policy import REPO, manifest_digest


class GitHub:
    def __init__(self, binary):
        self.binary = binary

    def api(self, path, method='GET', data=None, pages=False):
        args = [self.binary, 'api', f'repos/{REPO}/{path}', '--method', method]
        if pages:
            args += ['--paginate', '--slurp']
        body = None
        if data is not None:
            args += ['--input', '-']
            body = json.dumps(data)
        result = subprocess.run(args, input=body, capture_output=True, text=True, timeout=90)
        if result.returncode:
            raise RuntimeError(f'GitHub {method} request failed: {path.split("?")[0]}')
        value = json.loads(result.stdout) if result.stdout.strip() else None
        return [item for page in value for item in page] if pages else value

    def merged_since(self, cutoff):
        pulls = self.api('pulls?state=closed&base=main&sort=updated&direction=desc&per_page=100', pages=True)
        result = []
        for p in pulls:
            if p.get('merged_at') and p['merged_at'] > cutoff:
                full = self.api(f'pulls/{p["number"]}')
                if full['base']['ref'] != 'main' or full['base']['repo']['id'] != 1241650801:
                    raise ValueError('Wrong merged PR target')
                result.append(full)
        return sorted(result,key=lambda p:(p['merged_at'],p['number']))

    def changed(self, number):
        files = self.api(f'pulls/{number}/files?per_page=100', pages=True)
        if len(files) >= 3000:
            raise ValueError('PR file list cannot be verified completely')
        return {f['filename'][len('supabase/migrations/'):] for f in files
                if f['filename'].startswith('supabase/migrations/')}

    def issue(self, pr, files):
        marker = f'<!-- ping-migration-pr:{pr["number"]} -->'
        issues = self.api('issues?state=all&per_page=100', pages=True)
        found = next((i for i in issues if not i.get('pull_request') and marker in (i.get('body') or '')),None)
        digest = manifest_digest(files)
        body = '\n'.join([marker, 'Supabase 마이그레이션 승인 대기',
                          f'PR: #{pr["number"]}', f'머지 커밋: {pr["merge_commit_sha"]}',
                          'Vercel 배포와 별도로, 아래 SQL은 자동 적용되지 않습니다.', '',
                          *[f'- `{name}` — SHA256 `{value}`' for name,value in sorted(files.items())], '',
                          '검토 후 0mininseoul 계정으로 아래 명령을 이 Issue의 댓글에 그대로 작성하세요.',
                          f'`/ping-approve-migrations {pr["merge_commit_sha"]} {digest}`', '',
                          'Issue 닫기/라벨 변경/다른 사람의 댓글은 승인이 아닙니다. 파일 내용 변경 시 재승인이 필요합니다.',
                          '관리 키는 이 Mac의 Keychain에만 유지합니다.'])
        if found:
            if found.get('body') != body:
                self.api(f'issues/{found["number"]}', 'PATCH', {'body':body,'assignees':['0mininseoul']})
            return found['number']
        value = self.api('issues', 'POST', {'title':f'Supabase 마이그레이션 승인 대기 — PR #{pr["number"]}',
                                           'body':body,'assignees':['0mininseoul']})
        return value['number']

    def status(self, sha, state, message):
        self.api(f'statuses/{sha}','POST',{'state':state,'description':message[:140],'context':'ping/migrations'})
