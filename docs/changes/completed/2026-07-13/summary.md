# 2026-07-13 工作摘要

- [justify-indent-placeholder](justify-indent-placeholder.md) — 修正 justify 折疊行首 U+3000 縮排造成 soft-wrap 行字距異常放大、單行/多行段落間距不一致；縮排改用 placeholder 呈現，並升級 metrics 快取版本。
- [b2-lastline-offbyone](b2-lastline-offbyone.md) — 修正末行補償安全上限的 off-by-one（分母間隙數→字數），近滿末行不再把末字擠成孤行；隨 v0.2.137 發布。
