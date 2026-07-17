# 2026-07-17 工作摘要

- [sdk-3446-typography-probe-regression](sdk-3446-typography-probe-regression.md) — 打磨方向 5：Flutter 3.44.6 下重跑排版探針，justify/placeholder/letterSpacing 引擎行為與 3.44.0 實證完全一致，無需變更。
- [ambiguous-width-punctuation](ambiguous-width-punctuation.md) — 歧義寬度標點佔一格：彎引號成對轉「」『』、間隔號轉・，讓 Android 字型回退落到 CJK 字型與漢字同寬；新增對照表單測，736 測試全過。
- [b2-conditional-pass2-and-tts-geometry](b2-conditional-pass2-and-tts-geometry.md) — 打磨方向 1（程式部分）＋方向 6：必為單行的 block 不進 B2 兩段式路徑（單行寬度上界估算，與 cost model 共用判斷）；新增 B2×TTS 末行 boxes 幾何契約測試。
- [telemetry-session-export](telemetry-session-export.md) — 打磨方向 4：telemetry 加 session 累計直方圖與 JSON 摘要、dispose 時寫入 AppLog；建立真機驗收劇本（docs/scratchpad/device-acceptance-playbook.md）。
- [pair-quotes-per-line](pair-quotes-per-line.md) — 打磨方向 3：pairQuotes 直引號配對改逐行，雜訊引號影響隔離單行；補激進項誤傷對照表測試。全日終驗證：analyze 乾淨、743 測試全過。
