"""列出一段時間裡主執行緒與繪製執行緒上超過 1ms 的工作，各展開到第四層。
找某一幀是誰花的時間時用（例如繪製裡哪一段最重）。

用法：python tool/phone_trace/window.py trace.pftrace 起ms 迄ms [最小ms]
"""
import sys

from trace_common import Trace

t = Trace(sys.argv[1])
lo, hi = t.ts(float(sys.argv[2])), t.ts(float(sys.argv[3]))
min_ns = float(sys.argv[4]) * 1e6 if len(sys.argv) > 4 else 1e6
for utid, label in ((t.main, '主'), (t.raster, '繪')):
    print(f'--- {label}執行緒')
    for r in t.q(f"""select s.id, s.ts, s.dur, s.name from slice s join thread_track tt on s.track_id=tt.id
     where tt.utid={utid} and s.depth=0 and s.ts between {lo} and {hi} and s.dur > {min_ns} order by s.ts"""):
        print(f"{t.ms(r.ts):8.1f} {r.dur / 1e6:6.1f} {r.name[:90]}")
        for c in t.q(f"""select ts, dur, name, depth from descendant_slice({r.id})
         where dur > {min_ns * 1.5} and depth <= 4 order by ts limit 12"""):
            print(f"   {'  ' * c.depth}{t.ms(c.ts):8.1f} {c.dur / 1e6:6.1f} {c.name[:80]}")
