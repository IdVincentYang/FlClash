package com.follow.clash

import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.CompletableFuture
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit

internal class CrashReportWorker(
    private val clock: () -> Long = { System.nanoTime() / 1_000_000 },
) : AutoCloseable {
    private val executor = ThreadPoolExecutor(1, 1, 0, TimeUnit.MILLISECONDS,
        ArrayBlockingQueue(4), { task -> Thread(task, "FlClashReports").apply { isDaemon = true } })

    fun submit(budget: Long = 1500, task: (Long) -> String): CompletableFuture<String> {
        return submitValue({ it }, budget, task)
    }

    fun <T> submitValue(failure: (String) -> T, budget: Long = 1500, task: (Long) -> T): CompletableFuture<T> {
        val result = CompletableFuture<T>()
        val deadline = clock() + budget
        try {
            executor.execute {
                val status = if (clock() >= deadline) failure("deadline") else try {
                    task(deadline)
                } catch (_: Throwable) { failure("io") }
                result.complete(status)
            }
        } catch (_: RejectedExecutionException) { result.complete(failure("busy")) }
        return result
    }

    override fun close() { executor.shutdown() }
}
