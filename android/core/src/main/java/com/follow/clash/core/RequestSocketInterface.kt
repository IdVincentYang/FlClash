package com.follow.clash.core

import androidx.annotation.Keep

@Keep
interface RequestSocketInterface {
    fun prepareSocket(state: String, fd: Int): Boolean
}
