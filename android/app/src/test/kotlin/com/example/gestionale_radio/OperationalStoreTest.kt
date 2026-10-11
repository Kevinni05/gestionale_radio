package com.example.gestionale_radio

import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.annotation.SQLiteMode
import javax.crypto.KeyGenerator
import java.io.File

@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, sdk = [28])
@SQLiteMode(SQLiteMode.Mode.NATIVE)
class OperationalStoreTest {
    private fun key() = KeyGenerator.getInstance("AES").apply { init(256) }.generateKey()

    @Test fun encryptedTransactionsSurviveReopenAndRefuseWrongKeyOrPartialUpdates() {
        val context = RuntimeEnvironment.getApplication()
        context.deleteDatabase("radiotech-operational-v1.db")
        val key = key()
        var store = OperationalStore(context, testKey = key)
        store.write(mapOf("offline_sync_queue" to "private queue", "offline_sync_queue_backup" to "private queue"))
        assertThrows(IllegalArgumentException::class.java) {
            store.write(linkedMapOf("offline_sync_queue" to "replacement", "invalid_record" to "invalid"))
        }
        assertEquals("private queue", store.read("offline_sync_queue")["value"])
        assertEquals("private queue", store.read("offline_sync_queue_backup")["value"])
        store.close().get()
        val wrong = OperationalStore(context, testKey = key())
        assertThrows(Exception::class.java) { wrong.write(mapOf("report_draft_new" to "must not overwrite")) }
        wrong.close().get()
        store = OperationalStore(context, testKey = key)
        assertEquals("private queue", store.read("offline_sync_queue")["value"])
        assertEquals(false, store.read("report_draft_new")["found"])
        context.openOrCreateDatabase("radiotech-operational-v1.db", 0, null).use { db ->
            db.rawQuery("SELECT payload FROM records", null).use { cursor ->
                while (cursor.moveToNext()) assertFalse(String(cursor.getBlob(0), Charsets.UTF_8).contains("private queue"))
            }
        }
        store.write(mapOf("offline_sync_queue" to null, "offline_sync_queue_backup" to null))
        assertEquals(true, store.read("offline_sync_queue")["found"])
        assertNull(store.read("offline_sync_queue")["value"])
        store.close().get()
        context.deleteDatabase("radiotech-operational-v1.db")
    }

    @Test fun stagedAttachmentsRejectTamperingAndOperationSubstitution() {
        val context = RuntimeEnvironment.getApplication()
        context.deleteDatabase("radiotech-operational-v1.db")
        val store = OperationalStore(context, testKey = key())
        val root = File(context.filesDir, "radiotech_pending_reports").apply { mkdirs() }
        val a = File(root, "operation-a").apply { mkdirs() }
        val b = File(root, "operation-b").apply { mkdirs() }
        val file = File(a, "0_photo.jpg").apply { writeBytes(byteArrayOf(1, 2, 3, 4)) }
        store.protectAttachment(file)
        assertFalse(file.readBytes().contentEquals(byteArrayOf(1, 2, 3, 4)))
        assertArrayEquals(byteArrayOf(1, 2, 3, 4), store.readAttachment(file))
        val swapped = File(b, file.name).apply { writeBytes(file.readBytes()) }
        assertThrows(Exception::class.java) { store.readAttachment(swapped) }
        file.writeBytes(file.readBytes().apply { this[lastIndex] = (this[lastIndex].toInt() xor 1).toByte() })
        assertThrows(Exception::class.java) { store.readAttachment(file) }
        store.close().get()
        val replacement = OperationalStore(context, testKey = key())
        assertThrows(Exception::class.java) { replacement.protectAttachment(File(a, "new.jpg").apply { writeBytes(byteArrayOf(5)) }) }
        replacement.close().get()
        root.deleteRecursively()
        context.deleteDatabase("radiotech-operational-v1.db")
    }

    @Test fun changingTheDeletionFlagCannotHideAnAuthenticatedRecord() {
        val context = RuntimeEnvironment.getApplication()
        context.deleteDatabase("radiotech-operational-v1.db")
        val secret = key()
        var store = OperationalStore(context, testKey = secret)
        store.write(mapOf("offline_sync_queue" to "pending operation"))
        store.close().get()
        context.openOrCreateDatabase("radiotech-operational-v1.db", 0, null).use { db ->
            db.execSQL("UPDATE records SET deleted=1 WHERE deleted=0 AND length(payload) != ?", arrayOf("radiotech-local-key-v1".toByteArray().size + 16))
        }
        store = OperationalStore(context, testKey = secret)
        assertThrows(Exception::class.java) { store.read("offline_sync_queue") }
        store.close().get()
        context.deleteDatabase("radiotech-operational-v1.db")
    }
}
