package com.nihaisha.nihaisha_app

import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

/**
 * Process-wide health state. A failed Engine/Conversation release is terminal
 * for this process: a recreated Activity must not initialize another Engine
 * while the previous native resources may still be alive.
 */
internal class LocalAiProcessHealth {
    private val releaseFailure = AtomicReference<Throwable?>(null)

    fun releaseFailure(): Throwable? = releaseFailure.get()

    fun markReleaseFailure(error: Throwable) {
        releaseFailure.compareAndSet(null, error)
    }

    fun isAvailable(): Boolean = releaseFailure.get() == null
}

/**
 * Serializes native AI work across Activity instances in the same process.
 *
 * Activity teardown is queued on this process-wide executor. A newly created
 * Activity submits its work to the same queue, so model release always precedes
 * the next Activity's model initialization.
 */
internal object LocalAiProcessExecutor {
    val health = LocalAiProcessHealth()
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
    private val processHealth: LocalAiProcessHealth? = null,
    private val release: () -> Unit
) {
    private val destroyed = AtomicBoolean(false)

    fun isDestroyed(): Boolean = destroyed.get()

    fun releaseFailure(): Throwable? = processHealth?.releaseFailure()

    fun submit(
        task: () -> Unit,
        onRejected: () -> Unit,
        onUnavailable: () -> Unit = onRejected
    ) {
        if (destroyed.get()) {
            onRejected()
            return
        }
        if (processHealth?.isAvailable() == false) {
            onUnavailable()
            return
        }
        try {
            executor.execute {
                when {
                    destroyed.get() -> onRejected()
                    processHealth?.isAvailable() == false -> onUnavailable()
                    else -> task()
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
                    processHealth?.markReleaseFailure(error)
                    onReleaseError(error)
                }
            }
        } catch (error: Throwable) {
            processHealth?.markReleaseFailure(error)
            onReleaseError(error)
        }
    }
}
