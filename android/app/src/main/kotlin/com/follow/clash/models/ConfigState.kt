package com.follow.clash.models

data class ConfigReceipt(
    val token: Long = 0,
    val owner: Long = 0,
    val inputId: String = "",
    val serviceId: String = "",
    val protectGeneration: Long = 0,
    val optionsFingerprint: String = "",
)

data class ServiceCoreParams(
    val mixedPort: Int = 0,
    val bindingId: Long = 0,
    val localReachable: Boolean = false,
    val authenticationRequired: Boolean = false,
)

data class ConfigFact(
    val runtimeEpoch: String = "",
    val version: Long = 0,
    val token: Long = 0,
    val owner: Long = 0,
    val inputId: String = "",
    val yamlSha256: String = "",
    val profileId: Long? = null,
    val profileName: String = "",
    val phase: String = "unknown",
    val businessActive: Boolean = false,
    val replayEligible: Boolean = false,
)

data class ConfigApplyResult(
    val status: String,
    val message: String = "",
    val receipt: ConfigReceipt = ConfigReceipt(),
    val coreParams: ServiceCoreParams? = null,
    val fact: ConfigFact = ConfigFact(),
)

data class ConfigCleanupResult(val status: String, val message: String = "")
