from pathlib import Path

path = Path(__file__).with_name('reader_direct_flow_refactor.py')
s = path.read_text(encoding='utf-8')
bad = '''s = sub_once(
    s,
    r"\\n  bool get needsForwardFriction =>[\\s\\S]*?\\n  bool _backwardFrictionLatched = false;\\n",
    "\\n",
    "remove friction policy block",
) if "_backwardFrictionLatched" in s else s
'''
if bad not in s:
    raise RuntimeError('expected obsolete friction-driver block not found')
path.write_text(s.replace(bad, '', 1), encoding='utf-8')
print('refactor driver repaired')
