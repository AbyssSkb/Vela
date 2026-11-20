package com.example.vela

import java.io.File
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class SharedFileNameTest {
    @get:Rule val directory = TemporaryFolder()

    @Test
    fun restoresAnExtensionWithoutChangingTheSharedBytes() {
        val contents = byteArrayOf(1, 2, 3)
        val original = directory.newFile("shared-image").apply { writeBytes(contents) }
        val named = addMissingExtension(original) { "png" }
        assertEquals("shared-image.png", named.name)
        assertArrayEquals(contents, named.readBytes())
        assertFalse(original.exists())
    }

    @Test
    fun preservesAnExistingExtensionAndAnUnknownType() {
        val named = directory.newFile("shared.jpeg")
        assertEquals(named, addMissingExtension(named) { error("Already named") })
        val unknown: File = directory.newFile("document")
        assertEquals(unknown, addMissingExtension(unknown) { null })
    }
}
