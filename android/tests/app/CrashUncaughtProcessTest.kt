package com.follow.clash

import com.google.gson.Gson
import java.io.File
import java.nio.file.Files
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Test

class CrashUncaughtProcessTest {
    @Test fun independentProcessTerminatesWithOriginalHandlerOnStoredBusyIoAndBlockedFormatting() {
        val classpath = listOf(UncaughtReportProbe::class.java, CrashReportStore::class.java, Gson::class.java, Unit::class.java)
            .map { File(it.protectionDomain.codeSource.location.toURI()).path }.distinct().joinToString(File.pathSeparator)
        for (mode in listOf("stored", "busy", "io", "format_blocked", "format_error", "reentrant")) {
            val root = Files.createTempDirectory("uncaught-report").toFile().canonicalFile
            val child = ProcessBuilder(File(System.getProperty("java.home"), "bin/java").path,
                "-cp", classpath, "com.follow.clash.UncaughtReportProbe", root.path, mode)
                .redirectErrorStream(true).start()
            try {
                assertTrue("child did not terminate: $mode", child.waitFor(8, TimeUnit.SECONDS))
                assertEquals(23, child.exitValue())
                assertEquals("once", File(root, "delegated").readText())
                if (mode == "stored") {
                    val store = CrashReportStore(File(root, "reports"))
                    assertEquals("java_uncaught", store.read(store.ids().single())!!.metadata["source"].asString)
                }
            } finally { if (child.isAlive) child.destroyForcibly().waitFor(); root.deleteRecursively() }
        }
    }
}

object UncaughtReportProbe {
    @JvmStatic fun main(args: Array<String>) {
        val root = File(args[0]); val mode = args[1]
        val worker = CrashReportWorker()
        val path = File(root, "reports")
        if (mode == "io") path.writeText("not a directory")
        val collector = CrashReportCollector({ CrashReportStore(path) }, worker, { mapOf("processEpoch" to "child") }, { System.nanoTime() / 1_000_000 })
        if (mode == "busy") {
            val entered = CountDownLatch(1)
            worker.submit { entered.countDown(); CountDownLatch(1).await(); "stored" }
            check(entered.await(2, TimeUnit.SECONDS))
            repeat(4) { worker.submit { "queued" } }
        }
        Thread.setDefaultUncaughtExceptionHandler(CrashUncaughtHandler({ _, _ ->
            File(root, "delegated").appendText("once")
            Runtime.getRuntime().halt(23)
        }, collector::java))
        if (mode == "format_blocked") throw object : RuntimeException() {
            override val message: String get() { CountDownLatch(1).await(); return "unreachable" }
        }
        if (mode == "format_error") throw object : RuntimeException() {
            override val message: String get() = throw OutOfMemoryError("synthetic formatter failure")
        }
        if (mode == "reentrant") throw object : RuntimeException() {
            override val message: String get() {
                Thread.getDefaultUncaughtExceptionHandler()!!.uncaughtException(Thread.currentThread(), IllegalStateException("synthetic nested"))
                return "unreachable"
            }
        }
        throw IllegalStateException("synthetic child exception")
    }
}
