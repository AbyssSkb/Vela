package com.example.vela

internal class NetworkChangeCoalescer(
    private val schedule: (Runnable, Long) -> Unit,
    private val notify: () -> Unit,
) {
    private var scheduled = false

    fun changed() {
        if (scheduled) return
        scheduled = true
        schedule(
            Runnable {
                scheduled = false
                notify()
            },
            300,
        )
    }
}
