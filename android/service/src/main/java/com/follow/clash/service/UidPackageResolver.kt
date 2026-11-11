package com.follow.clash.service

import com.google.gson.JsonArray
import com.google.gson.JsonObject

data class UidPackageIdentity(
    val status: String,
    val userScope: String,
    val packages: List<String> = emptyList(),
) {
    fun toJson(): String = JsonObject().apply {
        addProperty("status", status)
        addProperty("userScope", userScope)
        add("packages", JsonArray().apply { packages.forEach { add(it) } })
    }.toString()
}

class UidPackageResolver(
    private val isCurrentUser: (Int) -> Boolean,
    private val packagesForUid: (Int) -> Array<String>?,
) {
    fun resolve(uid: Int): UidPackageIdentity {
        if (uid < 0) return UidPackageIdentity("unknown", "unknown")
        return try {
            if (!isCurrentUser(uid)) {
                UidPackageIdentity("otherUser", "other")
            } else {
                val packages = packagesForUid(uid).orEmpty()
                    .filter { it.isNotBlank() }
                    .distinct()
                    .sorted()
                val status = when (packages.size) {
                    0 -> "notFound"
                    1 -> "known"
                    else -> "ambiguous"
                }
                UidPackageIdentity(status, "current", packages.take(64))
            }
        } catch (_: Exception) {
            UidPackageIdentity("lookupFailed", "unknown")
        }
    }
}
