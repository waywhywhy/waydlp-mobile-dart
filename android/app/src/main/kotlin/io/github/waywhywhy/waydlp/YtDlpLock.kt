package io.github.waywhywhy.waydlp

import android.util.Log
import java.util.concurrent.locks.ReentrantReadWriteLock

/**
 * Keeps yt-dlp updates away from running yt-dlp processes.
 *
 * yt-dlp is a Python zip application that reads its modules lazily, so
 * replacing it while an analysis or download runs breaks that process
 * ("zipimport.ZipImportError: bad local file header"). Every run holds the
 * shared lock; an update takes the exclusive lock.
 *
 * The lock is non-fair and the updater only polls with tryLock(), so a
 * waiting update never blocks new analyses or downloads; it runs as soon as
 * nothing is using yt-dlp. While an update runs, new work waits for it.
 */
object YtDlpLock {
    private val lock = ReentrantReadWriteLock(false)

    class Busy : Exception("yt-dlp is in use by running downloads. Try again when they finish.")

    fun <T> shared(block: () -> T): T {
        lock.readLock().lock()
        try {
            return block()
        } finally {
            lock.readLock().unlock()
        }
    }

    /** Run [block] once yt-dlp is idle, waiting at most [waitMs]; throws [Busy] otherwise. */
    fun <T> exclusive(waitMs: Long, block: () -> T): T {
        val deadline = System.currentTimeMillis() + waitMs
        while (!lock.writeLock().tryLock()) {
            if (System.currentTimeMillis() >= deadline) throw Busy()
            Thread.sleep(250)
        }
        Log.i("waydlp", "yt-dlp idle; updating")
        try {
            return block()
        } finally {
            lock.writeLock().unlock()
        }
    }
}
