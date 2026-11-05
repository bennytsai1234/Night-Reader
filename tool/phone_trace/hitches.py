"""從 Perfetto 追蹤找出夜讀「動畫播放中」的掉幀。

一幀和上一幀的間隔超過 1.5 拍，而且前後幾幀都是連續的（畫面在動），才算掉幀；
畫面靜止時沒有幀，不算（ADR 0036、0037）。也列出主執行緒或繪製執行緒單幀超過
8.3ms 的幀。每一處列出那段時間主執行緒上幀以外的工作、觸控事件，方便對到操作。

用法：python tool/phone_trace/hitches.py trace.pftrace
"""
import sys

from trace_common import BEAT_MS, Trace

t = Trace(sys.argv[1])
begin = t.begin_frames()
draw = t.draws()
inputs = t.q(f"""select s.ts, s.name from slice s join thread_track tt on s.track_id=tt.id
 where tt.utid={t.main} and s.depth=0 and s.name like 'dispatchInputEvent MotionEvent ACTION_%' order by s.ts""")
other = t.q(f"""select s.ts, s.dur, s.name from slice s join thread_track tt on s.track_id=tt.id
 where tt.utid={t.main} and s.depth=0 and s.dur > 2000000
   and s.name not in ('VsyncProcessCallback','AChoreographer_frameCallback64') order by s.ts""")

frames = []
di = 0
for b in begin:
    while di < len(draw) and draw[di].ts < b.ts:
        di += 1
    d = draw[di] if di < len(draw) else None
    frames.append((b.ts, b.dur / 1e6, d.dur / 1e6 if d else 0.0))

print('觸控：', ', '.join(f"{t.ms(i.ts):.0f}ms {i.name.split('ACTION_')[1].split()[0]}" for i in inputs))
issues = 0
for i in range(1, len(frames)):
    ts, ui, ra = frames[i]
    gap = (ts - frames[i - 1][0]) / 1e6
    # 前後各兩幀是不是連續的（畫面在動）。
    before = i >= 3 and all(
        (frames[j][0] - frames[j - 1][0]) / 1e6 < BEAT_MS * 1.5 for j in range(max(1, i - 2), i)
    )
    after = any(
        (frames[j][0] - frames[j - 1][0]) / 1e6 < BEAT_MS * 1.5
        for j in range(i + 1, min(len(frames), i + 4))
    )
    lo = frames[i - 1][0]
    # 間隔裡手指按下：這一幀是點下去的反應（ADR 0036 第 1 條不算掉幀）。
    pressed = any(lo <= x.ts < ts and 'ACTION_DOWN' in x.name for x in inputs)
    # 超過 400ms 沒有幀是畫面靜止（兩段動畫之間），不是卡住；間隔裡主執行緒
    # 幾乎沒在跑也是畫面靜止（沒有人要求畫新的一幀）。
    stalled = BEAT_MS * 1.5 < gap < 400 and before and after and not pressed
    if stalled and gap > 25:
        busy = t.q(f"""select sum(min(ts+dur,{ts}) - max(ts,{lo})) as d from sched
         where utid={t.main} and ts < {ts} and ts+dur > {lo}""")[0].d or 0
        stalled = busy / 1e6 > gap * 0.3
    heavy = (ui > BEAT_MS or ra > BEAT_MS) and (before or after)
    if not (stalled or heavy):
        continue
    issues += 1
    notes = [f"{o.name[:70]} {o.dur/1e6:.1f}ms" for o in other if lo <= o.ts < ts + 1]
    touch = [f"{x.name.split('ACTION_')[1].split()[0]}@{t.ms(x.ts):.0f}" for x in inputs if lo - 50e6 <= x.ts < ts]
    tag = f"漏 {round(gap / BEAT_MS) - 1} 拍" if stalled else ('點下去' if pressed else '單幀超過')
    print(f"{t.ms(ts):8.0f}ms {tag:6} 間隔 {gap:5.1f}  主 {ui:5.1f}  繪 {ra:5.1f}  {' '.join(touch)}  {'; '.join(notes)}")
print(f'共 {issues} 處；總幀數 {len(frames)}')
