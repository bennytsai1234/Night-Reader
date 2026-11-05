"""phone_trace 各腳本共用：開追蹤、找夜讀的主執行緒與繪製執行緒、時間換算。

時間一律是「追蹤起點起算的毫秒」，和 hitches.py 印出來的一樣，可以直接拿來當
frames.py、window.py 的起訖。
"""
from perfetto.trace_processor import TraceProcessor

PACKAGE = 'com.inkpage.reader'
BEAT_MS = 1000 / 120


class Trace:
    def __init__(self, path):
        self.tp = TraceProcessor(trace=path)
        p = self.q(f"select upid, pid from process where name='{PACKAGE}' order by upid desc limit 1")
        if not p:
            raise SystemExit('追蹤裡沒有夜讀的程序')
        self.upid, self.pid = p[0].upid, p[0].pid
        self.main = self.q(f"select utid from thread where tid={self.pid}")[0].utid
        self.raster = self.q(f"select utid from thread where upid={self.upid} and name='1.raster'")[0].utid
        self.t0 = self.q("select start_ts from trace_bounds")[0].start_ts

    def q(self, sql):
        return list(self.tp.query(sql))

    def ms(self, ts):
        return (ts - self.t0) / 1e6

    def ts(self, ms):
        return self.t0 + ms * 1e6

    def slices(self, utid, name):
        return self.q(f"""select s.id, s.ts, s.dur from slice s join thread_track tt on s.track_id=tt.id
         where tt.utid={utid} and s.name='{name}' order by s.ts""")

    def begin_frames(self):
        """主執行緒每一幀（Animator::BeginFrame）。"""
        return self.slices(self.main, 'Animator::BeginFrame')

    def draws(self):
        """繪製執行緒每一幀（Rasterizer::DrawToSurfaces）。"""
        return self.slices(self.raster, 'Rasterizer::DrawToSurfaces')
