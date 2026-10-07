#!/usr/bin/env python3
"""Fail CI if a workflow consumes Supabase GitHub secrets or scripts restore them."""
from pathlib import Path
import re
import sys

root = Path(__file__).resolve().parent.parent
violations = []
for folder in (root / '.github/workflows', root / 'scripts'):
    for path in folder.rglob('*'):
        if not path.is_file() or path == Path(__file__).resolve():
            continue
        try:
            text = path.read_text()
        except UnicodeDecodeError:
            continue
        if (re.search(r"(?:secrets|vars)\s*(?:\.\s*\w*supabase\w*|\[\s*['\"][^'\"]*supabase[^'\"]*['\"])", text, re.I)
            or (re.search(r'gh\s+(?:secret|variable)\s+set\b', text, re.I) and 'supabase' in text.lower())
            or re.search(r'vercel\s+git\s+connect\b', text, re.I)):
            violations.append(str(path.relative_to(root)))
if violations:
    print('Supabase GitHub credential storage is forbidden: ' + ', '.join(violations), file=sys.stderr)
    sys.exit(1)
print('Supabase GitHub credential policy passed.')
