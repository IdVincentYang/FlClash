package com.follow.clash

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.os.SystemClock
import com.follow.clash.common.GlobalState
import java.util.concurrent.Executors

internal object BootRecords {
    private val main = Handler(Looper.getMainLooper())
    val store = BootRecordStore(
        persistence = object : BootRecordPersistence {
            private val preferences by lazy {
                GlobalState.application.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            }
            override fun read(): Any? = preferences.all["flutter.boot_record"]
            override fun commit(record: String): Boolean = preferences.edit().putString("flutter.boot_record", record).commit()
        },
        context = mapOf(
            "pid" to Process.myPid(),
            "processName" to GlobalState.application.packageName,
            "processEpoch" to ServiceState.getRequestState().processEpoch,
            "processStartedAt" to System.currentTimeMillis() - (SystemClock.elapsedRealtime() - Process.getStartElapsedRealtime()),
        ),
        clock = SystemClock::elapsedRealtime,
        worker = Executors.newSingleThreadExecutor { task -> Thread(task, "FlClashBootRecord").apply { isDaemon = true } },
        deliver = { task -> main.post { task() } },
    )
}
