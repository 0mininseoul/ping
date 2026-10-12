"""Read fixed Git objects without checkout hooks; reject symlink and archive escapes."""
import hashlib
import io
import os
from pathlib import Path, PurePosixPath
import subprocess
import tarfile
from .policy import valid_migration_name, check_unique_versions


def extract_archive(data, target):
    with tarfile.open(fileobj=io.BytesIO(data),mode='r:') as archive:
        for member in archive:
            path = PurePosixPath(member.name)
            if path.is_absolute() or '..' in path.parts or member.issym() or member.islnk():
                raise ValueError('Unsafe Git archive entry')
            if '.git' in path.parts or '.env' in path.name or '.vercel' in path.parts:
                raise ValueError('Credential or Git metadata path in archive')
            out = Path(target).joinpath(*path.parts)
            if member.isdir():
                out.mkdir(parents=True,exist_ok=True)
            elif member.isfile():
                out.parent.mkdir(parents=True,exist_ok=True)
                out.write_bytes(archive.extractfile(member).read())
                out.chmod(0o600)
            else:
                raise ValueError('Unsupported Git archive entry')


class Repository:
    def __init__(self, binary, cache):
        self.binary,self.cache = binary,Path(cache)
        if not self.cache.exists():
            subprocess.run([binary,'clone','--bare','https://github.com/0mininseoul/ping.git',str(cache)],check=True,capture_output=True)

    def git(self,*args,binary=False):
        r=subprocess.run([self.binary,'-c','core.hooksPath=/dev/null','--git-dir',str(self.cache),*args],capture_output=True,timeout=180)
        if r.returncode:
            raise RuntimeError('Cannot verify fixed Git objects')
        return r.stdout if binary else r.stdout.decode().strip()

    def fetch(self):
        self.git('fetch','--no-tags','origin','+refs/heads/main:refs/heads/main')

    def head(self):
        return self.git('rev-parse','refs/heads/main')

    def inventory(self,sha):
        files={}
        for row in self.git('ls-tree','-r','-z',sha,'--','supabase/migrations',binary=True).split(b'\0'):
            if not row:continue
            info,path=row.decode().split('\t');mode,kind,oid=info.split()
            name=path[len('supabase/migrations/'):]
            if not name.endswith('.sql'):continue
            if mode not in ('100644','100755') or kind!='blob' or not valid_migration_name(name):
                raise ValueError('Unsafe migration object')
            files[name]=hashlib.sha256(self.git('cat-file','blob',oid,binary=True)).hexdigest()
        check_unique_versions(files)
        return files

    def sql(self,sha,name):
        if not valid_migration_name(name):raise ValueError('Unsafe SQL filename')
        return self.git('show',f'{sha}:supabase/migrations/{name}',binary=True)

    def export_web(self,sha,target):
        data=self.git('archive',sha,'api','web','package.json','package-lock.json','vercel.json','.vercelignore',binary=True)
        extract_archive(data,target)
