package com.inkpage.reader

import android.content.ContentResolver
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.DocumentsContract.Document
import java.io.File
import java.util.Locale

/**
 * 本地漫畫的作品資料夾（ADR 0052）：使用者用系統的資料夾授權（Storage
 * Access Framework）選了一個資料夾，App 沒有儲存權限、讀不到它的路徑，
 * 這裡經 ContentResolver 把裡面的漫畫檔複製到 App 自己的資料夾，Dart 那邊
 * 再照一般檔案匯入。只複製兩層：作品資料夾裡的 CBZ／ZIP 與圖，以及每個
 * 子資料夾（一話）裡的圖；更深的資料夾、其他檔案、隱藏檔都不複製。
 */
object ComicFolderCopy {
    private val archiveExtensions = setOf("cbz", "zip")
    private val imageExtensions = setOf(
        "jpg", "jpeg", "png", "webp", "gif", "bmp", "avif", "heif", "heic", "jxl",
    )

    /** 樹狀授權 [tree] 的資料夾名稱。 */
    fun nameOf(resolver: ContentResolver, tree: Uri): String {
        val rootId = DocumentsContract.getTreeDocumentId(tree)
        val uri = DocumentsContract.buildDocumentUriUsingTree(tree, rootId)
        resolver.query(uri, arrayOf(Document.COLUMN_DISPLAY_NAME), null, null, null)
            ?.use { cursor -> if (cursor.moveToFirst()) return cursor.getString(0) }
        return "本地漫畫"
    }

    /**
     * 把 [tree] 裡的漫畫檔複製到 [target]（不存在時建立），每複製完一個檔呼叫
     * [onProgress]（第幾個、共幾個）。
     */
    fun copy(
        resolver: ContentResolver,
        tree: Uri,
        target: File,
        onProgress: (Int, Int) -> Unit,
    ) {
        val files = mutableListOf<Pair<String, File>>()
        collect(resolver, tree, DocumentsContract.getTreeDocumentId(tree), target, 0, files)
        for ((index, entry) in files.withIndex()) {
            val (documentId, file) = entry
            file.parentFile?.mkdirs()
            val uri = DocumentsContract.buildDocumentUriUsingTree(tree, documentId)
            val partial = File(file.path + ".part")
            resolver.openInputStream(uri)?.use { input ->
                partial.outputStream().use { output -> input.copyTo(output) }
            } ?: throw IllegalStateException("讀不到 ${file.name}")
            if (!partial.renameTo(file)) throw IllegalStateException("存不進 ${file.name}")
            onProgress(index + 1, files.size)
        }
    }

    private fun collect(
        resolver: ContentResolver,
        tree: Uri,
        documentId: String,
        dir: File,
        depth: Int,
        out: MutableList<Pair<String, File>>,
    ) {
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, documentId)
        val columns = arrayOf(
            Document.COLUMN_DOCUMENT_ID,
            Document.COLUMN_DISPLAY_NAME,
            Document.COLUMN_MIME_TYPE,
        )
        resolver.query(children, columns, null, null, null)?.use { cursor ->
            while (cursor.moveToNext()) {
                val id = cursor.getString(0)
                val name = cursor.getString(1) ?: continue
                val mime = cursor.getString(2)
                if (name.startsWith(".")) continue
                val file = File(dir, safeName(name))
                if (mime == Document.MIME_TYPE_DIR) {
                    if (depth == 0) collect(resolver, tree, id, file, depth + 1, out)
                    continue
                }
                val extension = name.substringAfterLast('.', "").lowercase(Locale.ROOT)
                val wanted = extension in imageExtensions ||
                    (depth == 0 && extension in archiveExtensions)
                if (wanted) out.add(id to file)
            }
        }
    }

    private fun safeName(name: String): String =
        name.replace(Regex("[\\\\/:*?\"<>|\\u0000-\\u001f]"), "_").ifBlank { "_" }
}
