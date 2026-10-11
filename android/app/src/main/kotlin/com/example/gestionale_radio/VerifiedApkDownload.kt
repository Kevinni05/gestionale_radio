package com.example.gestionale_radio

import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.net.URI
import java.net.HttpURLConnection
import java.security.MessageDigest

/** No APK is exposed to the installer until its complete byte digest is verified. */
internal object VerifiedApkDownload {
    val busy = java.util.concurrent.atomic.AtomicBoolean(false)
    const val MAX_BYTES = 150L * 1024 * 1024
    private val digestPattern = Regex("^[a-f0-9]{64}$")
    private val releasePath = Regex("^/Kevinni05/gestionale_radio/releases/download/v[0-9A-Za-z.\\-]+/[A-Za-z0-9][0-9A-Za-z._\\-]*-[0-9A-Za-z.\\-]+\\.apk$")

    fun initialUrl(uri: URI): Boolean = secureUrl(uri) && uri.host == "github.com" && uri.rawQuery == null && releasePath.matches(uri.path ?: "")
    fun redirectUrl(uri: URI): Boolean = secureUrl(uri) && uri.host in setOf("github.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com")
    private fun secureUrl(uri: URI): Boolean = uri.scheme == "https" && uri.userInfo == null && uri.fragment == null && (uri.port == -1 || uri.port == 443)

    fun download(url: String, digest: String, directory: File): File {
        var uri = URI(url)
        require(initialUrl(uri) && digestPattern.matches(digest))
        directory.mkdirs()
        // Retain only the most recent verified APK; a new click cannot consume unbounded disk.
        directory.listFiles()?.forEach { it.delete() }
        val deadline = System.nanoTime() + 180_000_000_000L
        repeat(6) { hop ->
            check(System.nanoTime() < deadline)
            val connection = uri.toURL().openConnection() as HttpURLConnection
            connection.instanceFollowRedirects = false
            connection.connectTimeout = 15_000
            connection.readTimeout = 15_000
            try {
                val status = connection.responseCode
                if (status in listOf(301, 302, 303, 307, 308)) {
                    require(hop < 5)
                    uri = uri.resolve(connection.getHeaderField("Location") ?: throw IllegalStateException())
                    require(redirectUrl(uri))
                } else {
                    require(status == 200)
                    require(connection.contentLengthLong <= MAX_BYTES)
                    val file = File(directory, "verified-update.apk")
                    connection.inputStream.use { copyAndVerify(it, file, digest, deadline) }
                    return file
                }
            } finally { connection.disconnect() }
        }
        throw IllegalStateException()
    }

    internal fun copyAndVerify(input: InputStream, file: File, expected: String, deadline: Long = Long.MAX_VALUE) {
        require(digestPattern.matches(expected))
        val temporary = File(file.parentFile, file.name + ".partial")
        val digest = MessageDigest.getInstance("SHA-256")
        try {
            var size = 0L
            FileOutputStream(temporary).use { output ->
                val buffer = ByteArray(64 * 1024)
                while (true) {
                    check(System.nanoTime() < deadline)
                    val read = input.read(buffer)
                    if (read == -1) break
                    if (read == 0) continue
                    size += read
                    require(size <= MAX_BYTES)
                    output.write(buffer, 0, read)
                    digest.update(buffer, 0, read)
                }
                require(size > 0)
                output.fd.sync()
            }
            val actual = digest.digest().joinToString("") { "%02x".format(it) }
            require(MessageDigest.isEqual(actual.toByteArray(), expected.toByteArray()))
            check(temporary.renameTo(file))
        } catch (error: Exception) { file.delete(); throw error }
        finally { temporary.delete() }
    }
}
