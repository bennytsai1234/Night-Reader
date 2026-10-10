# Domain 文件

工程技能探索這個 repo 時，怎麼讀它的 domain 文件。

## 探索前先讀

- 根目錄的 **`GLOSSARY.md`**。
- **`docs/adr/`**：讀和這次要動的區域有關的 ADR。

這些檔案不存在時**直接繼續**，不要提出它們不存在，也不要建議先建立。`/domain-modeling` 技能（經由 `/grill-with-docs` 與 `/improve-codebase-architecture` 觸發）會在用語或決定真的定案時才建立它們。

## 檔案結構

單一 context：

```
/
├── GLOSSARY.md
├── docs/adr/
│   ├── 0001-....md
│   └── 0002-....md
└── lib/
```

## 使用用語表的詞彙

產出裡提到 domain 概念時（issue 標題、重構提案、假設、測試名稱），用 `GLOSSARY.md` 定義的詞，不要換成用語表明確列為 _Avoid_ 的同義詞。

需要的概念不在用語表裡時，代表兩種可能：你在發明專案沒在用的說法（重新考慮），或真的有缺口（記下來給 `/domain-modeling`）。

## 標出與 ADR 的衝突

產出和既有 ADR 牴觸時，明確指出，不要默默覆蓋：

> _與 ADR-0007（event-sourced orders）牴觸，但值得重新討論，因為……_
