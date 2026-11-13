package com.nihaisha.nihaisha_app

import java.util.concurrent.CountDownLatch
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LocalAiActivityTaskLifecycleTest {
    @Test
    fun oldActivityTeardownRunsBeforeNextActivityTasks() {
        val executor = Executors.newSingleThreadExecutor { runnable ->
            Thread(runnable, "local-ai-lifecycle-test").apply { isDaemon = true }
        }
        try {
            val events = CopyOnWriteArrayList<String>()
            val oldTaskStarted = CountDownLatch(1)
            val finishOldTask = CountDownLatch(1)
            val newActivityTaskFinished = CountDownLatch(1)

            val oldActivity = LocalAiActivityTaskLifecycle(executor) {
                events += "old.release"
            }
            oldActivity.submit(
                task = {
                    events += "old.running"
                    oldTaskStarted.countDown()
                    assertTrue(finishOldTask.await(5, TimeUnit.SECONDS))
                    events += "old.finished"
                },
                onRejected = { events += "old.first.rejected" }
            )
            assertTrue(oldTaskStarted.await(5, TimeUnit.SECONDS))

            oldActivity.submit(
                task = { events += "old.queued.executed" },
                onRejected = { events += "old.queued.rejected" }
            )
            oldActivity.destroy()

            val newActivity = LocalAiActivityTaskLifecycle(executor) {
                events += "new.release"
            }
            newActivity.submit(
                task = {
                    events += "new.load"
                    newActivityTaskFinished.countDown()
                },
                onRejected = { events += "new.rejected" }
            )

            finishOldTask.countDown()
            assertTrue(newActivityTaskFinished.await(5, TimeUnit.SECONDS))
            assertEquals(
                listOf(
                    "old.running",
                    "old.finished",
                    "old.queued.rejected",
                    "old.release",
                    "new.load"
                ),
                events.toList()
            )
            assertTrue(oldActivity.isDestroyed())
            assertFalse(newActivity.isDestroyed())
        } finally {
            executor.shutdownNow()
        }
    }

    @Test
    fun releaseFailureBlocksWorkQueuedByARecreatedActivity() {
        val executor = Executors.newSingleThreadExecutor { runnable ->
            Thread(runnable, "local-ai-release-failure-test").apply { isDaemon = true }
        }
        try {
            val health = LocalAiProcessHealth()
            val releaseError = IllegalStateException("native release failed")
            val releaseStarted = CountDownLatch(1)
            val finishRelease = CountDownLatch(1)
            val newTaskFinished = CountDownLatch(1)
            val queuedTaskRuns = AtomicInteger()
            val unavailableCount = AtomicInteger()

            val oldActivity = LocalAiActivityTaskLifecycle(
                executor = executor,
                release = {
                    releaseStarted.countDown()
                    assertTrue(finishRelease.await(5, TimeUnit.SECONDS))
                    throw releaseError
                },
                processHealth = health
            )
            oldActivity.destroy()
            assertTrue(releaseStarted.await(5, TimeUnit.SECONDS))

            val newActivity = LocalAiActivityTaskLifecycle(
                executor = executor,
                release = {},
                processHealth = health
            )
            newActivity.submit(
                task = {
                    queuedTaskRuns.incrementAndGet()
                    newTaskFinished.countDown()
                },
                onRejected = {
                    throw AssertionError("the recreated Activity was not destroyed")
                },
                onUnavailable = {
                    unavailableCount.incrementAndGet()
                    newTaskFinished.countDown()
                }
            )

            // Keep the old release blocked until the new Activity task is
            // enqueued, then let the release fail. The queued task must re-check
            // process health before touching Engine.
            finishRelease.countDown()
            assertTrue(newTaskFinished.await(5, TimeUnit.SECONDS))
            assertEquals(0, queuedTaskRuns.get())
            assertEquals(1, unavailableCount.get())
            assertTrue(health.releaseFailure() === releaseError)
            assertFalse(newActivity.isDestroyed())

            // Once the process is poisoned, later work is rejected immediately.
            var immediateUnavailable = 0
            newActivity.submit(
                task = { throw AssertionError("unavailable process must not execute") },
                onRejected = {
                    throw AssertionError("the recreated Activity is still active")
                },
                onUnavailable = { immediateUnavailable++ }
            )
            assertEquals(1, immediateUnavailable)
        } finally {
            executor.shutdownNow()
        }
    }

    @Test
    fun destroyReleasesExactlyOnceAndRejectsLaterWork() {
        val executor = Executors.newSingleThreadExecutor { runnable ->
            Thread(runnable, "local-ai-lifecycle-test").apply { isDaemon = true }
        }
        try {
            val releaseCount = AtomicInteger()
            val rejectedCount = AtomicInteger()
            val gate = LocalAiActivityTaskLifecycle(executor) {
                releaseCount.incrementAndGet()
            }

            gate.destroy()
            gate.destroy()
            gate.submit(
                task = { throw AssertionError("destroyed Activity task must not run") },
                onRejected = { rejectedCount.incrementAndGet() }
            )
            val queueDrained = CountDownLatch(1)
            executor.execute { queueDrained.countDown() }

            assertTrue(queueDrained.await(5, TimeUnit.SECONDS))
            assertTrue(gate.isDestroyed())
            assertEquals(1, releaseCount.get())
            assertEquals(1, rejectedCount.get())
        } finally {
            executor.shutdownNow()
        }
    }
}
