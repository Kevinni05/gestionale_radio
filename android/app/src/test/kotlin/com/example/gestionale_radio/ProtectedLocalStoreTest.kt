package com.example.gestionale_radio

import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.annotation.SQLiteMode
import javax.crypto.KeyGenerator

@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, sdk = [28])
@SQLiteMode(SQLiteMode.Mode.NATIVE)
class ProtectedLocalStoreTest {
    private fun cipher() = LocalDataCipher(KeyGenerator.getInstance("AES").apply { init(256) }.generateKey())

    @Test fun payloadIsEncryptedRandomlyAndBoundToItsRecord() {
        val cipher = cipher()
        val first = cipher.encrypt("report_draft_a", "private report")
        val second = cipher.encrypt("report_draft_a", "private report")
        assertFalse(first.first.contentEquals(second.first))
        assertFalse(String(first.second, Charsets.UTF_8).contains("private report"))
        assertEquals("private report", cipher.decrypt("report_draft_a", first.first, first.second))
        assertThrows(Exception::class.java) { cipher.decrypt("report_draft_b", first.first, first.second) }
        val changed = first.second.copyOf().apply { this[lastIndex] = (this[lastIndex].toInt() xor 1).toByte() }
        assertThrows(Exception::class.java) { cipher.decrypt("report_draft_a", first.first, changed) }
    }

    @Test fun transactionRollsBackBothQueueSlotsAndSurvivesReopen() {
        val context = RuntimeEnvironment.getApplication()
        context.deleteDatabase("operational-data.db")
        val cipher = cipher()
        var store = ProtectedLocalStore(context, cipher)
        store.writeAll(mapOf("offline_sync_queue" to "before", "offline_sync_queue_backup" to "before"))
        assertThrows(IllegalArgumentException::class.java) {
            store.writeAll(linkedMapOf("offline_sync_queue" to "after", "unexpected_key" to "invalid"))
        }
        assertEquals("before", store.read("offline_sync_queue"))
        assertEquals("before", store.read("offline_sync_queue_backup"))
        store.close()
        store = ProtectedLocalStore(context, cipher)
        assertEquals("before", store.read("offline_sync_queue"))
        store.readableDatabase.rawQuery("SELECT ciphertext FROM records", null).use {
            assertTrue(it.moveToFirst())
            assertFalse(String(it.getBlob(0), Charsets.UTF_8).contains("before"))
        }
        store.removeAll(listOf("offline_sync_queue", "offline_sync_queue_backup"))
        assertNull(store.read("offline_sync_queue"))
        store.close()
        context.deleteDatabase("operational-data.db")
    }
}
