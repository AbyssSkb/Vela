package com.example.vela

import org.junit.Assert.assertThrows
import org.junit.Test

class UpdateBridgeTest {
    private val installed = UpdateIdentity("io.github.abyssskb.vela", 5, setOf("release-key"))

    @Test
    fun acceptsNewerVersionWithTheSameSigner() {
        validateUpdateIdentity(installed, installed.copy(version = 6))
    }

    @Test
    fun rejectsOtherAppsOldVersionsAndDifferentSigningKeys() {
        listOf(
            installed.copy(packageName = "another.app", version = 6),
            installed.copy(version = 4),
            installed,
            installed.copy(version = 6, signers = setOf("another-key")),
            installed.copy(version = 6, signers = emptySet()),
        ).forEach { candidate ->
            assertThrows(IllegalArgumentException::class.java) {
                validateUpdateIdentity(installed, candidate)
            }
        }
    }

    @Test
    fun rejectsAnInstalledPackageWithoutVerifiableSigners() {
        assertThrows(IllegalArgumentException::class.java) {
            validateUpdateIdentity(installed.copy(signers = emptySet()), installed.copy(version = 6, signers = emptySet()))
        }
    }
}
