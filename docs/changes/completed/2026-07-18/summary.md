# 2026-07-18 工作摘要

- [文字正規化內化與全形對齊補完](typography-internalization.md) — 四開關移除恆開；補破折號/括號/波浪號/單引號配對/空格規則；【】〖〗｢｣統一轉上下引號；內嵌 NightReaderPunct 標點字型（自製滿版 dash）根治 —/… 歧義寬度；fingerprint 簽名 bump。analyze/test 全綠（757）。
- [日文段落自動翻譯](japanese-translation.md) — ML Kit on-device ja→zh，假名偵測逐段翻譯（transformer 後、fromRaw 前，TTS 唸中文），簡繁後處理沿用既有 converter；worker 簡繁轉換恆跳過假名行；設定一列 switch＋模型狀態。feature freeze 下使用者明確要求，已記入索引 Architecture Decisions。
