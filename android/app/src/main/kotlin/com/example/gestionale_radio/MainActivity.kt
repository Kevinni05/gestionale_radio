package com.example.gestionale_radio

import android.app.Activity
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
 private var pending: MethodChannel.Result? = null
 private var pdfBytes: ByteArray? = null
 override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
  super.configureFlutterEngine(flutterEngine)
  MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "radiotech/documents").setMethodCallHandler { call, result ->
   if (call.method != "savePdf") { result.notImplemented(); return@setMethodCallHandler }
   if (pending != null) { result.error("BUSY", "Salvataggio già in corso", null); return@setMethodCallHandler }
   val bytes = call.argument<ByteArray>("bytes")
   val name = call.argument<String>("filename")
   if (bytes == null || bytes.size < 5 || bytes.size > 10000000 || String(bytes.copyOfRange(0,5)) != "%PDF-" || name == null) {
    result.error("INVALID_PDF", "Documento PDF non valido", null); return@setMethodCallHandler
   }
   pending = result; pdfBytes = bytes
   try {
    val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply { addCategory(Intent.CATEGORY_OPENABLE); type = "application/pdf"; putExtra(Intent.EXTRA_TITLE, name) }
    startActivityForResult(intent, 7412)
   } catch (error: Exception) { pending = null; pdfBytes = null; result.error("SAVE_FAILED", "Impossibile aprire il salvataggio", null) }
  }
 }
 @Deprecated("Android result callback used by FlutterActivity")
 override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
  super.onActivityResult(requestCode, resultCode, data)
  if (requestCode != 7412) return
  val result = pending; val bytes = pdfBytes
  pending = null; pdfBytes = null
  if (result == null) return
  if (resultCode != Activity.RESULT_OK || data?.data == null || bytes == null) { result.success(false); return }
  try { contentResolver.openOutputStream(data.data!!)?.use { it.write(bytes) } ?: throw IllegalStateException(); result.success(true) }
  catch (error: Exception) { result.error("SAVE_FAILED", "Impossibile salvare il PDF", null) }
 }
}
