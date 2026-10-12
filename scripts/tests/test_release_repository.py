import io,sys,tarfile,tempfile,unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
class RepositoryTests(unittest.TestCase):
 def test_unsafe_archive_paths_cannot_reach_local_credentials(self):
  from release_policy.repository import extract_archive
  for name,kind in [('../keychain',tarfile.REGTYPE),('/tmp/keychain',tarfile.REGTYPE),('web/link',tarfile.SYMTYPE),('.vercel/project.json',tarfile.REGTYPE),('api/.env',tarfile.REGTYPE)]:
   b=io.BytesIO()
   with tarfile.open(fileobj=b,mode='w') as t:
    m=tarfile.TarInfo(name);m.type=kind;m.linkname='/Users/youngminpark';m.size=0;t.addfile(m)
   with tempfile.TemporaryDirectory() as d:
    with self.assertRaises(ValueError):extract_archive(b.getvalue(),d)
 def test_plain_files_are_materialized_without_hooks(self):
  from release_policy.repository import extract_archive
  b=io.BytesIO()
  with tarfile.open(fileobj=b,mode='w') as t:
   m=tarfile.TarInfo('api/test.ts');m.size=3;t.addfile(m,io.BytesIO(b'yes'))
  with tempfile.TemporaryDirectory() as d:
   extract_archive(b.getvalue(),d);self.assertEqual(Path(d,'api/test.ts').read_bytes(),b'yes')
