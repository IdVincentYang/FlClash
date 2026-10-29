package dev.steenbakker.mobile_scanner

import java.util.concurrent.Executor
import java.util.concurrent.Executors

internal object QrCameraWork {
    private var owner: Lease? = null

    @Synchronized fun acquire(): Lease? {
        if (owner != null) return null
        return Lease().also { owner = it }
    }

    internal class Lease : Executor {
        private val executor = Executors.newSingleThreadExecutor { Thread(it, "qr-camera") }
        private var pending = 0
        private var closed = false

        override fun execute(command: Runnable) {
            synchronized(QrCameraWork) {
                if (closed) throw java.util.concurrent.RejectedExecutionException()
                pending++
            }
            executor.execute {
                try { command.run() } finally {
                    synchronized(QrCameraWork) { pending--; releaseIfDone() }
                }
            }
        }

        fun close() = synchronized(QrCameraWork) {
            closed = true
            releaseIfDone()
        }

        private fun releaseIfDone() {
            if (closed && pending == 0) {
                executor.shutdown()
                if (owner === this) owner = null
            }
        }
    }
}
