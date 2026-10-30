package com.follow.clash

import android.system.ErrnoException
import android.system.Os
import android.system.OsConstants
import android.system.StructStat
import java.io.FileDescriptor
import java.io.FileInputStream
import java.nio.file.Files
import java.nio.file.LinkOption.NOFOLLOW_LINKS
import java.nio.file.Paths
import java.nio.file.attribute.FileTime
import java.util.concurrent.TimeUnit
import org.robolectric.annotation.Implementation
import org.robolectric.annotation.Implements
import org.robolectric.annotation.Resetter

// Robolectric Posix lacks open on API24; its Linux lstat follows symlinks.
// This fixture uses host no-follow stat/open, never a production fallback.
@Implements(Os::class)
class ReportOsShadow {
    companion object {
        private val streams = mutableListOf<FileInputStream>()
        @JvmStatic @Implementation fun lstat(path: String): StructStat {
            try {
                val attrs = Files.readAttributes(Paths.get(path), "unix:*", NOFOLLOW_LINKS)
                fun number(name: String) = (attrs[name] as Number).toLong()
                fun time(name: String) = (attrs[name] as FileTime).to(TimeUnit.SECONDS)
                return StructStat(number("dev"), number("ino"), number("mode").toInt(), number("nlink"),
                    number("uid").toInt(), number("gid").toInt(), number("rdev"), number("size"),
                    time("lastAccessTime"), time("lastModifiedTime"), time("ctime"), 4096, 0)
            } catch (_: Exception) { throw ErrnoException("lstat", OsConstants.ENOENT) }
        }
        @JvmStatic @Implementation fun open(path: String, flags: Int, mode: Int): FileDescriptor {
            if (flags and OsConstants.O_NOFOLLOW != 0 && Files.isSymbolicLink(Paths.get(path))) {
                throw ErrnoException("open", OsConstants.ELOOP)
            }
            return FileInputStream(path).also { synchronized(streams) { streams.add(it) } }.fd
        }
        @JvmStatic @Resetter fun reset() {
            synchronized(streams) {
                streams.forEach { runCatching { it.close() } }
                streams.clear()
            }
        }
    }
}
