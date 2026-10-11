package com.example.gestionale_radio

import org.junit.Assert.*
import org.junit.Test
import java.net.URI
import java.nio.file.Files
import java.security.MessageDigest

class VerifiedApkDownloadTest {
    @Test fun verifiedBytesArePublishedOnlyAfterACompleteMatchingDigest() {
        val directory = Files.createTempDirectory("verified-apk-test").toFile()
        try {
            val file = java.io.File(directory, "verified-update.apk")
            val bytes = "a complete update file".toByteArray()
            val digest = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
            VerifiedApkDownload.copyAndVerify(bytes.inputStream(), file, digest)
            assertArrayEquals(bytes, file.readBytes())
            assertThrows(IllegalArgumentException::class.java) { VerifiedApkDownload.copyAndVerify(bytes.copyOf(4).inputStream(), file, digest) }
            assertFalse(file.exists())
            assertFalse(java.io.File(directory, "verified-update.apk.partial").exists())
            assertThrows(IllegalStateException::class.java) { VerifiedApkDownload.copyAndVerify(bytes.inputStream(), file, digest, 0) }
            assertFalse(file.exists())
        } finally { directory.deleteRecursively() }
    }

    @Test fun urlsRejectUntrustedRedirectsAndCredentialOrPortSubstitution() {
        val url = "https://github.com/Kevinni05/gestionale_radio/releases/download/v1.5.2/RadioTech-1.5.2.apk"
        assertTrue(VerifiedApkDownload.initialUrl(URI(url)))
        assertFalse(VerifiedApkDownload.initialUrl(URI(url.replace("https:", "http:"))))
        assertFalse(VerifiedApkDownload.initialUrl(URI(url.replace("github.com", "github.com:8443"))))
        assertFalse(VerifiedApkDownload.initialUrl(URI(url + "?token=test")))
        assertTrue(VerifiedApkDownload.redirectUrl(URI("https://release-assets.githubusercontent.com/path?signature=test")))
        assertFalse(VerifiedApkDownload.redirectUrl(URI("https://attacker.example/file.apk")))
        assertFalse(VerifiedApkDownload.redirectUrl(URI("https://user@github.com/file.apk")))
    }
    @Test fun privateSiteDoesNotPermitForeignRedirectsOrCredentialUrls() {
        val origin = "https://updates.example.com"
        assertTrue(VerifiedApkDownload.privateSiteUrl(URI("$origin/latest.apk"), origin))
        assertFalse(VerifiedApkDownload.privateSiteUrl(URI("https://evil.example/latest.apk"), origin))
        assertFalse(VerifiedApkDownload.privateSiteUrl(URI("http://updates.example.com/latest.apk"), origin))
        assertFalse(VerifiedApkDownload.privateSiteUrl(URI("https://user@updates.example.com/latest.apk"), origin))
        assertFalse(VerifiedApkDownload.privateSiteUrl(URI("$origin/latest.apk?token=test"), origin))
        assertFalse(VerifiedApkDownload.privateSiteUrl(URI("$origin/latest.apk"), ""))
    }
}
