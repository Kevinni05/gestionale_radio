package com.example.gestionale_radio

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import android.os.Handler
import android.os.Looper
import java.nio.charset.StandardCharsets
import java.security.KeyStore
import java.security.MessageDigest
import java.util.concurrent.Executors
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import java.io.File
import java.io.FileOutputStream

/** SQLite transactions hold only hashed keys and AES-GCM ciphertext. */
class OperationalStore(context: Context, messenger: BinaryMessenger? = null, private val testKey: SecretKey? = null) {
    private val app = context.applicationContext
    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val channel = messenger?.let { MethodChannel(it, "radiotech/operational-store") }
    private val alias = "radiotech.operational.v1"
    private val databaseName = "radiotech-operational-v1.db"
    private val key: SecretKey by lazy {
        testKey ?: run {
        val keystore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val existing = keystore.getKey(alias, null)
        if (existing is SecretKey) existing else {
            // Never silently replace an encryption key for an existing archive.
            if (app.getDatabasePath(databaseName).exists()) throw IllegalStateException("KEY_UNAVAILABLE")
            KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
                init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .setKeySize(256).build())
            }.generateKey()
        }
        }
    }
    private val helper = object : SQLiteOpenHelper(app, databaseName, null, 1) {
        override fun onCreate(db: SQLiteDatabase) {
            db.execSQL("CREATE TABLE records (record_key TEXT PRIMARY KEY, iv BLOB NOT NULL, payload BLOB NOT NULL, deleted INTEGER NOT NULL DEFAULT 0)")
            val id = recordKey("__key_check")
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE, key)
            cipher.updateAAD(id.toByteArray(StandardCharsets.UTF_8))
            val proof = ContentValues().apply {
                put("record_key", id); put("payload", cipher.doFinal("radiotech-local-key-v1".toByteArray(StandardCharsets.UTF_8)))
                put("iv", cipher.iv); put("deleted", 0)
            }
            db.insertOrThrow("records", null, proof)
        }
        override fun onOpen(db: SQLiteDatabase) {
            super.onOpen(db)
            val id = recordKey("__key_check")
            db.query("records", arrayOf("iv", "payload"), "record_key=?", arrayOf(id), null, null, null).use { cursor ->
                if (!cursor.moveToFirst()) throw IllegalStateException("KEY_PROOF_UNAVAILABLE")
                val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, cursor.getBlob(0)))
                cipher.updateAAD(id.toByteArray(StandardCharsets.UTF_8))
                if (String(cipher.doFinal(cursor.getBlob(1)), StandardCharsets.UTF_8) != "radiotech-local-key-v1") throw IllegalStateException("KEY_PROOF_INVALID")
            }
        }
        override fun onConfigure(db: SQLiteDatabase) {
            super.onConfigure(db)
            db.execSQL("PRAGMA synchronous=FULL")
            db.execSQL("PRAGMA secure_delete=ON")
        }
        override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
            throw IllegalStateException("UNSUPPORTED_SCHEMA")
        }
    }

    init {
        channel?.setMethodCallHandler { call, result ->
            executor.execute {
                try {
                    key // Establish/validate the key before creating any database.
                    val response: Any = when (call.method) {
                        "read" -> {
                            val name = call.argument<String>("key") ?: throw IllegalArgumentException()
                            validateOperationalKey(name); read(name)
                        }
                        "write" -> {
                            val values = call.argument<Map<String, String?>>("values") ?: throw IllegalArgumentException()
                            write(values); true
                        }
                        "protectAttachment" -> { protectAttachment(attachment(call.argument<String>("path"))); true }
                        "readAttachment" -> readAttachment(attachment(call.argument<String>("path")))
                        else -> throw IllegalArgumentException()
                    }
                    main.post { result.success(response) }
                } catch (error: Exception) {
                    // No record contents, identifiers, key material or dependency messages.
                    main.post { result.error("LOCAL_ARCHIVE_UNAVAILABLE", "Archivio locale non disponibile. Conservare i dati e riprovare.", null) }
                }
            }
        }
    }

    private fun recordKey(value: String): String {
        if (value.isEmpty() || value.length > 4096) throw IllegalArgumentException()
        return MessageDigest.getInstance("SHA-256").digest(value.toByteArray(StandardCharsets.UTF_8))
            .joinToString("") { "%02x".format(it) }
    }

    private fun validateOperationalKey(value: String) {
        if (!(value.startsWith("report_draft_") || value.startsWith("report_receipt_") ||
                value.startsWith("offline_idempotency_") || value == "offline_sync_queue" || value == "offline_sync_queue_backup")) throw IllegalArgumentException()
    }

    fun close(): java.util.concurrent.Future<*> {
        channel?.setMethodCallHandler(null)
        val closed = executor.submit { helper.close() }
        executor.shutdown()
        return closed
    }

    internal fun read(value: String): Map<String, Any?> {
        key
        val id = recordKey(value)
        helper.readableDatabase.query("records", arrayOf("iv", "payload", "deleted"), "record_key=?", arrayOf(id), null, null, null).use { cursor ->
            if (!cursor.moveToFirst()) return mapOf("found" to false, "value" to null)
            val deleted = cursor.getInt(2)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, cursor.getBlob(0)))
            cipher.updateAAD((id + "|" + deleted).toByteArray(StandardCharsets.UTF_8))
            val decoded = cipher.doFinal(cursor.getBlob(1))
            return mapOf("found" to true, "value" to if (deleted == 1) null else String(decoded, StandardCharsets.UTF_8))
        }
    }

    internal fun write(values: Map<String, String?>) {
        key
        if (values.size > 256) throw IllegalArgumentException()
        val database = helper.writableDatabase
        database.beginTransaction()
        try {
            for ((name, value) in values) {
                validateOperationalKey(name)
                read(name) // An unreadable old record must not be overwritten or silently deleted.
                val id = recordKey(name)
                val row = ContentValues().apply { put("record_key", id); put("deleted", if (value == null) 1 else 0) }
                run {
                    val bytes = (value ?: "").toByteArray(StandardCharsets.UTF_8)
                    if (bytes.size > 8 * 1024 * 1024) throw IllegalArgumentException()
                    val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                    cipher.init(Cipher.ENCRYPT_MODE, key)
                    cipher.updateAAD((id + "|" + if (value == null) 1 else 0).toByteArray(StandardCharsets.UTF_8))
                    row.put("payload", cipher.doFinal(bytes)); row.put("iv", cipher.iv)
                }
                if (database.insertWithOnConflict("records", null, row, SQLiteDatabase.CONFLICT_REPLACE) == -1L) throw IllegalStateException()
            }
            database.setTransactionSuccessful()
        } finally { database.endTransaction() }
    }

    private val attachmentMagic = "RTENC001".toByteArray(StandardCharsets.US_ASCII)
    private fun attachment(path: String?): File {
        val root = File(app.filesDir, "radiotech_pending_reports").canonicalFile
        val file = File(path ?: throw IllegalArgumentException()).canonicalFile
        if (!file.path.startsWith(root.path + File.separator) || !file.isFile || file.length() > 10000036L) throw IllegalArgumentException()
        return file
    }
    internal fun readAttachment(file: File): ByteArray {
        key
        helper.readableDatabase // Persist and verify key continuity before touching staged photos.
        val bytes = file.readBytes()
        if (bytes.size < 8 || !bytes.copyOfRange(0, 8).contentEquals(attachmentMagic)) {
            // Upgrade old staged files before handing their bytes to the sender.
            if (bytes.isEmpty() || bytes.size > 10000000) throw IllegalArgumentException()
            protectAttachment(file)
            return bytes
        }
        if (bytes.size < 37) throw IllegalStateException()
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, bytes.copyOfRange(8, 20)))
        cipher.updateAAD((file.parentFile!!.name + "/" + file.name).toByteArray(StandardCharsets.UTF_8))
        return cipher.doFinal(bytes.copyOfRange(20, bytes.size))
    }
    internal fun protectAttachment(file: File) {
        key
        helper.writableDatabase
        val bytes = file.readBytes()
        if (bytes.size >= 8 && bytes.copyOfRange(0, 8).contentEquals(attachmentMagic)) {
            // Existing encryption must be authenticated before accepting a retry.
            readAttachment(file); return
        }
        if (bytes.isEmpty() || bytes.size > 10000000) throw IllegalArgumentException()
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key)
        cipher.updateAAD((file.parentFile!!.name + "/" + file.name).toByteArray(StandardCharsets.UTF_8))
        val temporary = File.createTempFile("protected-", ".partial", file.parentFile)
        try {
            FileOutputStream(temporary).use { output ->
                output.write(attachmentMagic); output.write(cipher.iv); output.write(cipher.doFinal(bytes)); output.fd.sync()
            }
            if (!temporary.renameTo(file)) throw IllegalStateException()
        } finally { temporary.delete() }
    }
}
