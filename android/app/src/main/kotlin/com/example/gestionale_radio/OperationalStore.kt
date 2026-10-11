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

/** SQLite transactions hold only hashed keys and AES-GCM ciphertext. */
class OperationalStore(context: Context, messenger: BinaryMessenger) {
    private val app = context.applicationContext
    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val channel = MethodChannel(messenger, "radiotech/operational-store")
    private val alias = "radiotech.operational.v1"
    private val databaseName = "radiotech-operational-v1.db"
    private val key: SecretKey by lazy {
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
    private val helper = object : SQLiteOpenHelper(app, databaseName, null, 1) {
        override fun onCreate(db: SQLiteDatabase) {
            db.execSQL("CREATE TABLE records (record_key TEXT PRIMARY KEY, iv BLOB NOT NULL, payload BLOB NOT NULL, deleted INTEGER NOT NULL DEFAULT 0)")
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
        channel.setMethodCallHandler { call, result ->
            executor.execute {
                try {
                    key // Establish/validate the key before creating any database.
                    val response: Any = when (call.method) {
                        "read" -> read(call.argument<String>("key") ?: throw IllegalArgumentException())
                        "write" -> {
                            val values = call.argument<Map<String, String?>>("values") ?: throw IllegalArgumentException()
                            write(values); true
                        }
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

    private fun read(value: String): Map<String, Any?> {
        val id = recordKey(value)
        helper.readableDatabase.query("records", arrayOf("iv", "payload", "deleted"), "record_key=?", arrayOf(id), null, null, null).use { cursor ->
            if (!cursor.moveToFirst()) return mapOf("found" to false, "value" to null)
            if (cursor.getInt(2) == 1) return mapOf("found" to true, "value" to null)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, cursor.getBlob(0)))
            cipher.updateAAD(id.toByteArray(StandardCharsets.UTF_8))
            return mapOf("found" to true, "value" to String(cipher.doFinal(cursor.getBlob(1)), StandardCharsets.UTF_8))
        }
    }

    private fun write(values: Map<String, String?>) {
        if (values.size > 256) throw IllegalArgumentException()
        val database = helper.writableDatabase
        database.beginTransaction()
        try {
            for ((name, value) in values) {
                val id = recordKey(name)
                val row = ContentValues().apply { put("record_key", id); put("deleted", if (value == null) 1 else 0) }
                if (value == null) { row.put("iv", byteArrayOf()); row.put("payload", byteArrayOf()) }
                else {
                    val bytes = value.toByteArray(StandardCharsets.UTF_8)
                    if (bytes.size > 8 * 1024 * 1024) throw IllegalArgumentException()
                    val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                    cipher.init(Cipher.ENCRYPT_MODE, key)
                    cipher.updateAAD(id.toByteArray(StandardCharsets.UTF_8))
                    row.put("payload", cipher.doFinal(bytes)); row.put("iv", cipher.iv)
                }
                if (database.insertWithOnConflict("records", null, row, SQLiteDatabase.CONFLICT_REPLACE) == -1L) throw IllegalStateException()
            }
            database.setTransactionSuccessful()
        } finally { database.endTransaction() }
    }
}
