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

start = s.find('s = replace_once(\n    s,\n    """    } finally {')
if start < 0:
    raise RuntimeError('restore finalizer transform start not found')
end_marker = '    "restore finalizer",\n)\n'
end = s.find(end_marker, start)
if end < 0:
    raise RuntimeError('restore finalizer transform end not found')
end += len(end_marker)
replacement = r'''s = sub_once(
    s,
    r"    \\} finally \\{\\n      if \\(mounted && identical\\(_pump, binding\\) && ticket == _restoreTicket\\) \\{\\n(?:        _restorePinning = false;\\n)?        _pump\\.onScrollStateChanged\\(\\n[\\s\\S]*?        \\);\\n      \\}\\n    \\}\\n",
    """    } finally {
      if (mounted && identical(_pump, binding) && ticket == _restoreTicket) {
        _pump.onScrollStateChanged(PumpState.idle);
      }
    }
""",
    "restore finalizer",
)
'''
s = s[:start] + replacement + s[end:]

path.write_text(s, encoding='utf-8')
print('refactor driver repaired')
