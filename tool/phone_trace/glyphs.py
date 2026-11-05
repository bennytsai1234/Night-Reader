"""列出一段時間裡繪製執行緒建字貼圖（CreateGlyphAtlas，第一次畫到某些字時）超過
0.5ms 的那幾次，和它是不是在拍定格畫面（toImage）時建的。

用法：python tool/phone_trace/glyphs.py trace.pftrace 起ms 迄ms
"""
import sys

from trace_common import Trace

t = Trace(sys.argv[1])
lo, hi = t.ts(float(sys.argv[2])), t.ts(float(sys.argv[3]))
for r in t.q(f"""select s.ts, s.dur, (select p.name from slice p where p.id = s.parent_id) parent,
   (select count(*) from ancestor_slice(s.id) x
     where x.name like '%Snapshot%' or x.name like '%ToImage%') snap
  from slice s where s.name='CreateGlyphAtlas' and s.dur>500000 and s.ts between {lo} and {hi} order by s.ts"""):
    print(f"{t.ms(r.ts):8.1f} {r.dur/1e6:5.1f} {'拍圖時' if r.snap else ''} parent={r.parent}")
