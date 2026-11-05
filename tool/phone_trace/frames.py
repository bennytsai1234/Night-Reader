"""列出一段時間的每一幀：主執行緒與繪製執行緒各花多久，繪製超過 6ms 的列出大項
（字貼圖、背景模糊、圖層……），再列主執行緒上幀以外超過 2ms 的工作。

用法：python tool/phone_trace/frames.py trace.pftrace 起ms 迄ms
"""
import sys

from trace_common import Trace

DRAW_PARTS = ('CreateGlyphAtlas', 'BackdropFilter', 'SaveLayer', 'DrawImageRect',
              'EntityPass::Render', 'RenderTarget', 'Snapshot')

t = Trace(sys.argv[1])
lo, hi = t.ts(float(sys.argv[2])), t.ts(float(sys.argv[3]))
rows = []
for tag, frames in (('主', t.begin_frames()), ('繪', t.draws())):
    for r in frames:
        if not lo <= r.ts <= hi:
            continue
        extra = ''
        if tag == '繪' and r.dur > 6e6:
            names = ','.join(f"'{n}'" for n in DRAW_PARTS)
            kids = t.q(f"""select name, sum(dur) d from descendant_slice({r.id})
              where name in ({names}) group by name""")
            extra = ' '.join(f"{k.name} {k.d/1e6:.1f}" for k in kids)
        rows.append((t.ms(r.ts), tag, r.dur / 1e6, extra))
for ms, tag, d, e in sorted(rows):
    print(f"{ms:8.1f} {tag} {d:5.1f} {e}")
for o in t.q(f"""select s.ts, s.dur, s.name from slice s join thread_track tt on s.track_id=tt.id
 where tt.utid={t.main} and s.depth=0 and s.dur>2000000 and s.ts between {lo} and {hi}
 and s.name not in ('VsyncProcessCallback','AChoreographer_frameCallback64','Choreographer#doFrame')"""):
    print('  其他', f"{t.ms(o.ts):.0f}", f"{o.dur/1e6:.1f}", o.name[:80])
