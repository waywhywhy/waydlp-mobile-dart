package io.github.waywhywhy.waydlp

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.content.ContextCompat
import com.yausername.ffmpeg.FFmpeg
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLException
import com.yausername.youtubedl_android.YoutubeDLRequest
import io.flutter.plugin.common.EventChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.concurrent.ConcurrentHashMap

/**
 * Runs yt-dlp jobs on the device (via youtubedl-android) with a concurrency
 * limit. It lives as long as the process; [DownloadService] keeps the process
 * in the foreground while jobs run. Output lines are forwarded to Dart, which
 * parses waydlp's progress templates (the same as on desktop).
 */
object DownloadEngine {
    private const val TAG = "waydlp"
    private val main = Handler(Looper.getMainLooper())
    val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    @Volatile var sink: EventChannel.EventSink? = null
    @Volatile private var initialized = false

    data class JobRecord(
        val id: String,
        val url: String,
        val args: List<String>,
        val title: String,
        val audio: Boolean,
        val historyId: Int?,
        @Volatile var keepPartial: Boolean = false,
        @Volatile var stopping: Boolean = false,
        @Volatile var progressText: String = "",
        @Volatile var fraction: Float = -1f,
    )

    private val jobs = ConcurrentHashMap<String, JobRecord>()
    private val pending = ArrayDeque<String>()
    private val running = mutableSetOf<String>()
    @Volatile var maxConcurrent = 2

    @Synchronized
    fun init(ctx: Context): Map<String, Any?> {
        if (!initialized) {
            YoutubeDL.getInstance().init(ctx.applicationContext)
            FFmpeg.getInstance().init(ctx.applicationContext)
            initialized = true
        }
        return mapOf(
            "ytDlpVersion" to YoutubeDL.getInstance().version(ctx.applicationContext),
        )
    }

    fun emit(kind: String, payload: Map<String, Any?>) {
        main.post { sink?.success(payload + ("kind" to kind)) }
    }

    private fun emitJob(type: String, id: String, data: Map<String, Any?> = emptyMap()) =
        emit("job", mapOf("type" to type, "id" to id, "data" to data))

    fun jobDir(ctx: Context, id: String): File {
        require(id.matches(Regex("^[0-9A-Za-z-]{1,64}$"))) { "invalid job id" }
        return File(ctx.filesDir, "jobs/$id")
    }

    fun jobPaths(ctx: Context, id: String): Map<String, String> {
        val d = jobDir(ctx, id)
        File(d, "out").mkdirs()
        File(d, "tmp").mkdirs()
        return mapOf("output" to File(d, "out").absolutePath, "temp" to File(d, "tmp").absolutePath)
    }

    fun enqueue(ctx: Context, rec: JobRecord) {
        synchronized(this) {
            jobs[rec.id] = rec
            pending.addLast(rec.id)
        }
        DownloadService.start(ctx)
        pump(ctx)
    }

    fun activeCount(): Int = synchronized(this) { pending.size + running.size }

    fun pump(ctx: Context) {
        val toStart = mutableListOf<JobRecord>()
        synchronized(this) {
            while (running.size < maxConcurrent.coerceIn(1, 4) && pending.isNotEmpty()) {
                val id = pending.removeFirst()
                val rec = jobs[id] ?: continue
                running += id
                toStart += rec
            }
        }
        toStart.forEach { rec -> scope.launch { run(ctx.applicationContext, rec) } }
        DownloadService.refresh(ctx)
    }

    fun stop(ctx: Context, id: String, keepPartial: Boolean) {
        val rec = jobs[id] ?: return
        val wasPending = synchronized(this) { pending.remove(id) }
        if (wasPending) {
            if (!keepPartial) jobDir(ctx, id).deleteRecursively()
            jobs.remove(id)
            emitJob("cancelled", id, mapOf("paused" to keepPartial))
            DownloadService.refresh(ctx)
            return
        }
        rec.keepPartial = keepPartial
        rec.stopping = true
        YoutubeDL.getInstance().destroyProcessById(id)
    }

    private fun run(ctx: Context, rec: JobRecord) {
        emitJob("started", rec.id)
        val files = mutableListOf<String>()
        try {
            val request = YoutubeDLRequest(rec.url).addCommands(rec.args)
            YoutubeDL.getInstance().execute(request, rec.id) { _, _, line ->
                if (line.startsWith("[waydlp:file]")) files += line.removePrefix("[waydlp:file]").trim()
                if (line.startsWith("[waydlp:dl]")) updateProgress(rec, line)
                emitJob("line", rec.id, mapOf("line" to line))
                DownloadService.refresh(ctx)
            }
            val saved = mutableListOf<Map<String, Any?>>()
            for (path in files) {
                val f = File(path)
                if (!f.isFile) continue
                val r = Saver.save(ctx, f, rec.audio)
                saved += r
                emitJob("saved", rec.id, r)
            }
            jobDir(ctx, rec.id).deleteRecursively()
            emitJob("finished", rec.id)
            remember(ctx, rec, ok = true, saved = saved, error = null)
            DownloadService.notifyDone(ctx, rec.title, true)
        } catch (e: YoutubeDL.CanceledException) {
            if (!rec.keepPartial) jobDir(ctx, rec.id).deleteRecursively()
            emitJob("cancelled", rec.id, mapOf("paused" to rec.keepPartial))
        } catch (e: YoutubeDLException) {
            if (rec.stopping) {
                if (!rec.keepPartial) jobDir(ctx, rec.id).deleteRecursively()
                emitJob("cancelled", rec.id, mapOf("paused" to rec.keepPartial))
            } else {
                // Keep partial data so a retry can resume.
                emitJob("failed", rec.id, mapOf("error" to (e.message ?: "yt-dlp failed")))
                remember(ctx, rec, ok = false, saved = emptyList(), error = e.message)
                DownloadService.notifyDone(ctx, rec.title, false)
            }
        } catch (e: Exception) {
            Log.e(TAG, "job ${rec.id} failed", e)
            emitJob("failed", rec.id, mapOf("error" to "ERROR: ${e.message ?: e.javaClass.simpleName}"))
            remember(ctx, rec, ok = false, saved = emptyList(), error = e.message)
        } finally {
            synchronized(this) {
                running -= rec.id
                jobs.remove(rec.id)
            }
            pump(ctx)
        }
    }

    private fun updateProgress(rec: JobRecord, line: String) {
        val p = line.removePrefix("[waydlp:dl]").split('|')
        fun num(i: Int) = p.getOrNull(i)?.toDoubleOrNull()
        val done = num(1)
        val total = num(2) ?: num(3)
        rec.fraction = if (done != null && total != null && total > 0) (done / total).toFloat().coerceIn(0f, 1f) else -1f
        rec.progressText = if (rec.fraction >= 0) "${(rec.fraction * 100).toInt()}%" else "Downloading"
    }

    /** Overall progress for the notification: (text, fraction or -1). */
    fun summary(): Pair<String, Float> {
        val active = synchronized(this) { running.mapNotNull { jobs[it] } }
        val queued = synchronized(this) { pending.size }
        if (active.isEmpty()) return Pair(if (queued > 0) "$queued queued" else "Finishing…", -1f)
        val first = active.first()
        val more = active.size - 1 + queued
        val text = first.title.take(60) + (if (more > 0) " (+$more)" else "") + " · " + first.progressText
        return Pair(text, if (active.size == 1) first.fraction else -1f)
    }

    // ---- results that finished while no UI was listening ----

    private const val PREFS = "waydlp.engine"
    private const val FINISHED = "finished"

    private fun remember(ctx: Context, rec: JobRecord, ok: Boolean, saved: List<Map<String, Any?>>, error: String?) {
        if (sink != null || rec.historyId == null) return
        val prefs = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        synchronized(this) {
            val arr = JSONArray(prefs.getString(FINISHED, "[]"))
            arr.put(JSONObject().apply {
                put("historyId", rec.historyId)
                put("ok", ok)
                put("uris", JSONArray(saved.mapNotNull { it["uri"] }))
                put("size", saved.sumOf { (it["size"] as? Long) ?: 0L })
                put("mime", saved.firstOrNull()?.get("mime"))
                put("error", error?.take(4000))
            })
            prefs.edit().putString(FINISHED, arr.toString()).apply()
        }
    }

    fun drainFinished(ctx: Context): List<Map<String, Any?>> {
        val prefs = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val arr = synchronized(this) {
            val a = JSONArray(prefs.getString(FINISHED, "[]"))
            prefs.edit().remove(FINISHED).apply()
            a
        }
        return (0 until arr.length()).map { i ->
            val o = arr.getJSONObject(i)
            val uris = o.optJSONArray("uris") ?: JSONArray()
            mapOf(
                "historyId" to o.optInt("historyId"),
                "ok" to o.optBoolean("ok"),
                "uris" to (0 until uris.length()).map { uris.getString(it) },
                "size" to o.optLong("size"),
                "mime" to o.optString("mime").ifEmpty { null },
                "error" to o.optString("error").ifEmpty { null },
            )
        }
    }

    fun startServiceIfNeeded(ctx: Context) {
        if (activeCount() > 0) ContextCompat.startForegroundService(ctx, DownloadService.intent(ctx))
    }
}
