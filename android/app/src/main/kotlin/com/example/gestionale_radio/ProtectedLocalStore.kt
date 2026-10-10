package com.example.gestionale_radio

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.security.KeyStore
import java.security.MessageDigest
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

internal class LocalDataCipher(private val key: SecretKey = keystoreKey()) {
    fun encrypt(recordKey: String, value: String): Pair<ByteArray, ByteArray> {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key)
        cipher.updateAAD(recordKey.toByteArray(Charsets.UTF_8))
        return Pair(cipher.iv, cipher.doFinal(value.toByteArray(Charsets.UTF_8)))
    }

    fun decrypt(recordKey: String, nonce: ByteArray, encrypted: ByteArray): String {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, nonce))
        cipher.updateAAD(recordKey.toByteArray(Charsets.UTF_8))
        return String(cipher.doFinal(encrypted), Charsets.UTF_8)
    }

    companion object {
        @Synchronized private fun keystoreKey(): SecretKey {
            val alias = "radiotech.operational-data.v1"
            val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
            if (store.containsAlias(alias)) return store.getKey(alias, null) as SecretKey
            val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
            generator.init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setKeySize(256).setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setRandomizedEncryptionRequired(true).build())
            return generator.generateKey()
        }
    }
}

internal class ProtectedLocalStore(context: Context, private val cipher: LocalDataCipher = LocalDataCipher()) :
    SQLiteOpenHelper(context, "operational-data.db", null, 1) {
    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL("CREATE TABLE records (record_id TEXT PRIMARY KEY, nonce BLOB NOT NULL, ciphertext BLOB NOT NULL)")
        val proof = cipher.encrypt("__key_check", "radiotech-local-key-v1")
        val record = ContentValues().apply {
            put("record_id", id("__key_check")); put("nonce", proof.first); put("ciphertext", proof.second)
        }
        check(db.insertOrThrow("records", null, record) != -1L)
    }
    override fun onOpen(db: SQLiteDatabase) {
        super.onOpen(db)
        // A lost/replaced key must block even writes to a new record, preserving the existing database.
        db.query("records", arrayOf("nonce", "ciphertext"), "record_id=?", arrayOf(id("__key_check")), null, null, null).use {
            check(it.moveToFirst()) { "Local key proof unavailable" }
            check(cipher.decrypt("__key_check", it.getBlob(0), it.getBlob(1)) == "radiotech-local-key-v1")
        }
    }
    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        throw IllegalStateException("Unsupported local data schema; preserve existing data")
    }
    override fun onConfigure(db: SQLiteDatabase) {
        db.execSQL("PRAGMA secure_delete=ON")
    }

    private fun validate(key: String) {
        require(key.length <= 2048 && (key.startsWith("report_draft_") || key.startsWith("offline_idempotency_") ||
            key == "offline_sync_queue" || key == "offline_sync_queue_backup"))
    }
    private fun id(key: String): String = MessageDigest.getInstance("SHA-256")
        .digest(key.toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it) }

    fun read(key: String): String? {
        validate(key)
        readableDatabase.query("records", arrayOf("nonce", "ciphertext"), "record_id=?", arrayOf(id(key)), null, null, null).use {
            if (!it.moveToFirst()) return null
            // Authentication failure is surfaced; never reset or overwrite data.
            return cipher.decrypt(key, it.getBlob(0), it.getBlob(1))
        }
    }

    fun writeAll(values: Map<String, String>) {
        require(values.isNotEmpty() && values.size <= 256)
        val db = writableDatabase
        db.beginTransaction()
        try {
            values.forEach { (key, value) ->
                validate(key)
                read(key) // Refuse to overwrite a record whose authentication has failed.
                require(value.toByteArray(Charsets.UTF_8).size <= 8_000_000)
                val encrypted = cipher.encrypt(key, value)
                val record = ContentValues().apply {
                    put("record_id", id(key)); put("nonce", encrypted.first); put("ciphertext", encrypted.second)
                }
                check(db.insertWithOnConflict("records", null, record, SQLiteDatabase.CONFLICT_REPLACE) != -1L)
            }
            db.setTransactionSuccessful()
        } finally { db.endTransaction() }
    }

    fun removeAll(keys: List<String>) {
        require(keys.size <= 256)
        val db = writableDatabase
        db.beginTransaction()
        try {
            keys.forEach { key -> validate(key); db.delete("records", "record_id=?", arrayOf(id(key))) }
            db.setTransactionSuccessful()
        } finally { db.endTransaction() }
    }
}
