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
                    .asSequence()
                    .filter { it.isNotBlank() }
                    .distinct()
                    .take(65)
                    .toList()
                if (packages.size > 64) {
                    return UidPackageIdentity("lookupFailed", "unknown")
                }
                val status = when (packages.size) {
                    0 -> "notFound"
                    1 -> "known"
                    else -> "ambiguous"
                }
                UidPackageIdentity(status, "current", packages.sorted())
            }
        } catch (_: Exception) {
            UidPackageIdentity("lookupFailed", "unknown")
        }
    }
}
