from pathlib import Path

path = Path(__file__).with_name('reader_direct_flow_refactor.py')
s = path.read_text(encoding='utf-8')

bad_friction = '''s = sub_once(
    s,
    r"\\n  bool get needsForwardFriction =>[\\s\\S]*?\\n  bool _backwardFrictionLatched = false;\\n",
    "\\n",
    "remove friction policy block",
) if "_backwardFrictionLatched" in s else s
'''
if bad_friction not in s:
    raise RuntimeError('expected obsolete friction-driver block not found')
s = s.replace(bad_friction, '', 1)

cache_target_tail = '''      return;\n    }\n    _cancelParagraphWait();\n""",'''
if cache_target_tail not in s:
    raise RuntimeError('expected cache target tail not found')
s = s.replace(cache_target_tail, '''      return;\n    }\n""",''', 1)

restore_target = '''      if (mounted && identical(_pump, binding) && ticket == _restoreTicket) {\n        _restorePinning = false;\n        _pump.onScrollStateChanged('''
if restore_target not in s:
    raise RuntimeError('expected restore finalizer target not found')
s = s.replace(
    restore_target,
    '''      if (mounted && identical(_pump, binding) && ticket == _restoreTicket) {\n        _pump.onScrollStateChanged(''',
    1,
)

path.write_text(s, encoding='utf-8')
print('refactor driver repaired')
