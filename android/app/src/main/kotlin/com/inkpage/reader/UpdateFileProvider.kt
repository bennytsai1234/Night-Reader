package com.inkpage.reader

import androidx.core.content.FileProvider

// 自己的子類別：其他外掛也宣告 FileProvider 時，manifest 合併才不會衝突。
class UpdateFileProvider : FileProvider()
