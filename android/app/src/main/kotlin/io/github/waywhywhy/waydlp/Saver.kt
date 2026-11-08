package io.github.waywhywhy.waydlp

import android.content.ContentValues
import android.content.Context
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import androidx.documentfile.provider.DocumentFile
import java.io.File

/**
 * Moves finished downloads from app storage into a place the user can see:
 * a folder chosen with the Storage Access Framework, or Download/waydlp via
 * MediaStore (Android 10+), or the public Download folder on older Android.
 */
object Saver {
    private const val PREFS = "waydlp.engine"
    private const val TREE = "saveTree"

    fun setTree(ctx: Context, uri: String?) {
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(TREE, uri).apply()
    }

    private fun tree(ctx: Context): Uri? =
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(TREE, null)?.let(Uri::parse)

    fun mimeOf(name: String): String {
        val ext = name.substringAfterLast('.', "").lowercase()
        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext) ?: when (ext) {
            "opus" -> "audio/ogg"
            "mkv" -> "video/x-matroska"
            "m4a" -> "audio/mp4"
            else -> "application/octet-stream"
        }
    }

    /** Returns {uri, mime, size, name}. */
    fun save(ctx: Context, file: File, audio: Boolean): Map<String, Any?> {
        val mime = mimeOf(file.name)
        val size = file.length()
        val uri = tree(ctx)?.let { saveToTree(ctx, it, file, mime) }
            ?: if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) saveToMediaStore(ctx, file, mime) else saveLegacy(ctx, file)
        file.delete()
        return mapOf("uri" to uri.toString(), "mime" to mime, "size" to size, "name" to file.name)
    }

    private fun saveToTree(ctx: Context, treeUri: Uri, file: File, mime: String): Uri? {
        val dir = DocumentFile.fromTreeUri(ctx, treeUri) ?: return null
        if (!dir.canWrite()) return null
        val doc = dir.createFile(mime, file.name) ?: return null
        ctx.contentResolver.openOutputStream(doc.uri)?.use { out -> file.inputStream().use { it.copyTo(out) } } ?: return null
        return doc.uri
    }

    private fun saveToMediaStore(ctx: Context, file: File, mime: String): Uri {
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, file.name)
            put(MediaStore.MediaColumns.MIME_TYPE, mime)
            put(MediaStore.MediaColumns.RELATIVE_PATH, "${Environment.DIRECTORY_DOWNLOADS}/waydlp")
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val resolver = ctx.contentResolver
        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: throw IllegalStateException("MediaStore refused to create ${file.name}")
        try {
            resolver.openOutputStream(uri)?.use { out -> file.inputStream().use { it.copyTo(out) } }
                ?: throw IllegalStateException("cannot write ${file.name}")
            values.clear()
            values.put(MediaStore.MediaColumns.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
        } catch (e: Exception) {
            resolver.delete(uri, null, null)
            throw e
        }
        return uri
    }

    @Suppress("DEPRECATION")
    private fun saveLegacy(ctx: Context, file: File): Uri {
        // Android 7–9: public Download/waydlp (needs WRITE_EXTERNAL_STORAGE), else app-specific storage.
        val publicDir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), "waydlp")
        val dir = if (publicDir.mkdirs() || publicDir.canWrite()) publicDir else
            File(ctx.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS), "waydlp").apply { mkdirs() }
        var dest = File(dir, file.name)
        var n = 1
        while (dest.exists()) dest = File(dir, "${file.nameWithoutExtension} ($n).${file.extension}").also { n++ }
        file.copyTo(dest)
        MediaScannerConnection.scanFile(ctx, arrayOf(dest.absolutePath), null, null)
        return FileProvider.getUriForFile(ctx, "${ctx.packageName}.files", dest)
    }
}
