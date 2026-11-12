package com.nihaisha.nihaisha_app

import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Serializes native AI work across Activity instances in the same process.
 *
 * Activity teardown is queued on this process-wide executor. A newly created
 * Activity submits its work to the same queue, so model release always precedes
 * the next Activity's model initialization.
 */
internal object LocalAiProcessExecutor {
    val executor: ExecutorService = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "local-ai-process-serial").apply { isDaemon = true }
    }
}

/**
 * Activity-scoped admission gate over the process-wide serial executor.
 *
 * Once destroyed, queued-but-not-started tasks are rejected and one release
 * task is appended to the shared queue. An already-running task is allowed to
 * finish before release; a subsequent Activity queues behind that release.
 */
internal class LocalAiActivityTaskLifecycle(
    private val executor: ExecutorService,
    private val release: () -> Unit
) {
    private val destroyed = AtomicBoolean(false)

    fun isDestroyed(): Boolean = destroyed.get()

    fun submit(task: () -> Unit, onRejected: () -> Unit) {
        if (destroyed.get()) {
            onRejected()
            return
        }
        try {
            executor.execute {
                if (destroyed.get()) {
                    onRejected()
                } else {
                    task()
                }
            }
        } catch (_: RejectedExecutionException) {
            onRejected()
        }
    }

    fun destroy(onReleaseError: (Throwable) -> Unit = {}) {
        if (!destroyed.compareAndSet(false, true)) return
        try {
            executor.execute {
                try {
                    release()
                } catch (error: Throwable) {
                    onReleaseError(error)
                }
            }
        } catch (error: Throwable) {
            onReleaseError(error)
        }
    }
}
