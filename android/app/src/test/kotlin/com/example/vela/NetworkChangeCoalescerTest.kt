package com.example.vela

import org.junit.Assert.assertEquals
import org.junit.Test

class NetworkChangeCoalescerTest {
    @Test
    fun continuousEventsDoNotPostponeNotification() {
        val scheduled = mutableListOf<Pair<Runnable, Long>>()
        var notifications = 0
        val coalescer =
            NetworkChangeCoalescer({ task, delay -> scheduled.add(task to delay) }) {
                notifications++
            }

        repeat(100) { coalescer.changed() }
        assertEquals(1, scheduled.size)
        assertEquals(300L, scheduled.single().second)
        scheduled.removeAt(0).first.run()
        assertEquals(1, notifications)

        coalescer.changed()
        coalescer.changed()
        assertEquals(1, scheduled.size)
        scheduled.removeAt(0).first.run()
        assertEquals(2, notifications)
    }
}
