"""Temporary transport of the locally inspected repair, removed before delivery."""
import base64
import gzip
import hashlib
import json
import os
import runpy
import shutil
from pathlib import Path

payload = Path('.github/reader-v2-edits.b64').read_text().strip()
# Correct a transcription error in the temporary transport, never in source.
payload = payload.replace('WHOnUncac', 'WHOnUcac')
expected = '176a0c62d6d0743f296bb33f2a8c52de3272b8d67ec0d9dc541393460e91934f'
actual = hashlib.sha256(payload.encode()).hexdigest()
print('Transport:', len(payload), actual, flush=True)
assert actual == expected, 'Transport differs from the locally inspected source edits'
changes = json.loads(gzip.decompress(base64.b64decode(payload)))
root = Path.cwd().resolve()
for change in changes:
    path = Path(change['path'])
    path.resolve().relative_to(root)
    assert hashlib.sha256(path.read_bytes()).hexdigest() == change['sha256'], path
for change in changes:
    path = Path(change['path'])
    if change.get('delete'):
        backup = Path(os.environ['RUNNER_TEMP']) / 'reader-deleted' / path
        backup.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(path), str(backup))
    else:
        lines = path.read_text().splitlines(keepends=True)
        for start, end, replacement in reversed(change['edits']):
            lines[start:end] = [replacement]
        path.write_text(''.join(lines))
print(f'Applied {len(changes)} verified source edits', flush=True)
fixes = Path('.github/reader-v2-fixes.py')
if fixes.exists():
    runpy.run_path(str(fixes), run_name='__main__')
