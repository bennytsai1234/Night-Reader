# 2026-07-02

- Reader V2 架構目錄改為 screen / session / use_cases / chapter / layout / render / viewport / features，並同步更新 import 與 atlas 文件。
- Reader V2 新增 state machine 與 operation token，集中 open/jump/restore/presentation/contentReload 的 phase 與過期操作檢查。
