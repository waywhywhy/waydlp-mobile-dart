package io.github.waywhywhy.waydlp

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.DocumentsContract
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLException
import com.yausername.youtubedl_android.YoutubeDLRequest
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

class MainActivity : FlutterActivity() {
    private var pendingShared: String? = null
    private var folderResult: MethodChannel.Result? = null
    private var notifResult: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleShare(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleShare(intent)
    }

    /** Links shared from other apps (Share → waydlp). */
    private fun handleShare(intent: Intent?) {
        if (intent?.action != Intent.ACTION_SEND || intent.type?.startsWith("text/") != true) return
        val text = intent.getStringExtra(Intent.EXTRA_TEXT) ?: return
        if (DownloadEngine.sink != null) DownloadEngine.emit("shared", mapOf("text" to text)) else pendingShared = text
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        EventChannel(messenger, "io.github.waywhywhy.waydlp/events").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                DownloadEngine.sink = events
            }

            override fun onCancel(arguments: Any?) {
                DownloadEngine.sink = null
            }
        })
        MethodChannel(messenger, "io.github.waywhywhy.waydlp/engine").setMethodCallHandler { call, result ->
            try {
                handle(call, result)
            } catch (e: Exception) {
                result.error("native", e.message ?: e.javaClass.simpleName, null)
            }
        }
    }

    private fun io(result: MethodChannel.Result, block: suspend () -> Any?) {
        DownloadEngine.scope.launch {
            try {
                val v = block()
                withContext(Dispatchers.Main) { result.success(v) }
            } catch (e: YoutubeDL.CanceledException) {
                withContext(Dispatchers.Main) { result.error("cancelled", "Cancelled", null) }
            } catch (e: YoutubeDLException) {
                withContext(Dispatchers.Main) { result.error("ytdlp", e.message?.lineSequence()?.lastOrNull { it.isNotBlank() } ?: "yt-dlp failed", e.message) }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) { result.error("native", e.message ?: e.javaClass.simpleName, null) }
            }
        }
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        val ctx = applicationContext
        when (call.method) {
            "init" -> io(result) {
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q &&
                    ContextCompat.checkSelfPermission(this, Manifest.permission.WRITE_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED
                ) {
                    withContext(Dispatchers.Main) {
                        ActivityCompat.requestPermissions(this@MainActivity, arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE), 2)
                    }
                }
                DownloadEngine.init(ctx)
            }
            "probe" -> io(result) {
                val url = call.argument<String>("url")!!
                val args = call.argument<List<String>>("args")!!
                YoutubeDL.getInstance().destroyProcessById(PROBE_ID)
                val response = YoutubeDL.getInstance().execute(YoutubeDLRequest(url).addCommands(args), PROBE_ID, null)
                response.out
            }
            "cancelProbe" -> {
                YoutubeDL.getInstance().destroyProcessById(PROBE_ID)
                result.success(null)
            }
            "jobPaths" -> result.success(DownloadEngine.jobPaths(ctx, call.argument<String>("id")!!))
            "enqueue" -> {
                DownloadEngine.enqueue(
                    ctx,
                    DownloadEngine.JobRecord(
                        id = call.argument<String>("id")!!,
                        url = call.argument<String>("url")!!,
                        args = call.argument<List<String>>("args")!!,
                        title = call.argument<String>("title") ?: "",
                        audio = call.argument<Boolean>("audio") ?: false,
                        historyId = call.argument<Int>("historyId"),
                    ),
                )
                result.success(null)
            }
            "stop" -> {
                DownloadEngine.stop(ctx, call.argument<String>("id")!!, call.argument<Boolean>("keepPartial") ?: false)
                result.success(null)
            }
            "setMaxConcurrent" -> {
                DownloadEngine.maxConcurrent = (call.argument<Int>("n") ?: 2).coerceIn(1, 4)
                DownloadEngine.pump(ctx)
                result.success(null)
            }
            "updateYtDlp" -> io(result) {
                when (YoutubeDL.getInstance().updateYoutubeDL(ctx, YoutubeDL.UpdateChannel.STABLE)) {
                    YoutubeDL.UpdateStatus.DONE -> "Updated to ${YoutubeDL.getInstance().version(ctx)}"
                    YoutubeDL.UpdateStatus.ALREADY_UP_TO_DATE -> "Already up to date (${YoutubeDL.getInstance().version(ctx)})"
                    else -> "Update finished"
                }
            }
            "open" -> result.success(startView(call.argument<String>("uri")!!, call.argument<String>("mime") ?: "*/*", share = false))
            "share" -> result.success(startView(call.argument<String>("uri")!!, call.argument<String>("mime") ?: "*/*", share = true))
            "delete" -> io(result) {
                val uri = Uri.parse(call.argument<String>("uri")!!)
                try {
                    if (DocumentsContract.isDocumentUri(ctx, uri)) {
                        DocumentsContract.deleteDocument(ctx.contentResolver, uri)
                    } else {
                        ctx.contentResolver.delete(uri, null, null) > 0
                    }
                } catch (e: SecurityException) {
                    false // e.g. the file was created by a previous installation
                }
            }
            "exists" -> io(result) {
                try {
                    ctx.contentResolver.openFileDescriptor(Uri.parse(call.argument<String>("uri")!!), "r")?.use { true } ?: false
                } catch (e: Exception) {
                    false
                }
            }
            "isMetered" -> {
                val cm = getSystemService(ConnectivityManager::class.java)
                result.success(cm?.isActiveNetworkMetered ?: false)
            }
            "requestNotifications" -> {
                if (Build.VERSION.SDK_INT >= 33 &&
                    ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
                ) {
                    notifResult = result
                    ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
                } else {
                    result.success(true)
                }
            }
            "pickFolder" -> {
                folderResult = result
                @Suppress("DEPRECATION")
                startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE), PICK_FOLDER)
            }
            "setSaveLocation" -> {
                Saver.setTree(ctx, call.argument<String>("uri"))
                result.success(null)
            }
            "consumeSharedText" -> {
                result.success(pendingShared)
                pendingShared = null
            }
            "drainFinished" -> result.success(DownloadEngine.drainFinished(ctx))
            "cacheSize" -> io(result) { dirSize(File(ctx.filesDir, "jobs")) + dirSize(ctx.cacheDir) }
            "clearCache" -> io(result) {
                if (DownloadEngine.activeCount() == 0) File(ctx.filesDir, "jobs").deleteRecursively()
                ctx.cacheDir.listFiles()?.forEach { it.deleteRecursively() }
                null
            }
            else -> result.notImplemented()
        }
    }

    private fun dirSize(f: File): Long = if (f.isFile) f.length() else f.listFiles()?.sumOf { dirSize(it) } ?: 0L

    private fun startView(uri: String, mime: String, share: Boolean): Boolean {
        val u = Uri.parse(uri)
        val intent = if (share) {
            Intent.createChooser(
                Intent(Intent.ACTION_SEND).setType(mime).putExtra(Intent.EXTRA_STREAM, u).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION),
                null,
            )
        } else {
            Intent(Intent.ACTION_VIEW).setDataAndType(u, mime).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        return try {
            startActivity(intent)
            true
        } catch (e: ActivityNotFoundException) {
            false
        }
    }

    @Deprecated("Uses the platform result API to avoid an extra dependency")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != PICK_FOLDER) return
        val uri = data?.data
        if (resultCode == RESULT_OK && uri != null) {
            contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
            )
            folderResult?.success(uri.toString())
        } else {
            folderResult?.success(null)
        }
        folderResult = null
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 1) {
            notifResult?.success(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED)
            notifResult = null
        }
    }

    companion object {
        private const val PROBE_ID = "probe"
        private const val PICK_FOLDER = 42
    }
}
