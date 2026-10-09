package com.example.gestionale_radio

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import java.security.MessageDigest
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
 private var pending: MethodChannel.Result? = null
 private var pdfBytes: ByteArray? = null
 override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
  super.configureFlutterEngine(flutterEngine)
  MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "radiotech/updates").setMethodCallHandler { call, result ->
   try {
    when (call.method) {
     "installedApp" -> {
      @Suppress("DEPRECATION")
      val info = packageManager.getPackageInfo(packageName, if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES)
      @Suppress("DEPRECATION")
      val signatures = if (Build.VERSION.SDK_INT >= 28) info.signingInfo?.apkContentsSigners else info.signatures
      val fingerprints = signatures?.map { signature -> MessageDigest.getInstance("SHA-256").digest(signature.toByteArray()).joinToString("") { "%02x".format(it) } } ?: emptyList()
      @Suppress("DEPRECATION")
      val version = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()
      result.success(mapOf("versionName" to info.versionName, "versionCode" to version, "signingSha256" to fingerprints))
     }
     "openDownload" -> {
      val url = call.argument<String>("url") ?: throw IllegalArgumentException()
      val uri = Uri.parse(url)
      if (uri.scheme != "https" || uri.host != "github.com" || uri.userInfo != null || uri.query != null || uri.fragment != null || !Regex("^/Kevinni05/gestionale_radio/releases/download/v[0-9A-Za-z.\\-]+/RadioTech-[0-9A-Za-z.\\-]+\\.apk$").matches(uri.path ?: "")) throw IllegalArgumentException()
      startActivity(Intent(Intent.ACTION_VIEW, uri))
      result.success(true)
     }
     else -> result.notImplemented()
    }
   } catch (error: Exception) { result.error("UPDATE_UNAVAILABLE", "Aggiornamento non disponibile", null) }
  }
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
