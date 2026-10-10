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
 private val localDataWorker = java.util.concurrent.Executors.newSingleThreadExecutor()
 private var localData: ProtectedLocalStore? = null
 private var pending: MethodChannel.Result? = null
 private var pdfBytes: ByteArray? = null
 override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
  super.configureFlutterEngine(flutterEngine)
  MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "radiotech/local-data").setMethodCallHandler { call, result ->
   localDataWorker.execute {
    try {
     val store = localData ?: ProtectedLocalStore(applicationContext).also { localData = it }
     val value: Any? = when (call.method) {
      "read" -> store.read(call.argument<String>("key") ?: throw IllegalArgumentException())
      "writeAll" -> { store.writeAll(call.argument<Map<String, String>>("values") ?: throw IllegalArgumentException()); null }
      "removeAll" -> { store.removeAll(call.argument<List<String>>("keys") ?: throw IllegalArgumentException()); null }
      else -> throw IllegalArgumentException()
     }
     runOnUiThread { result.success(value) }
    } catch (error: Exception) {
     runOnUiThread { result.error("LOCAL_DATA_UNAVAILABLE", "Dati locali non disponibili. Non reinstallare l’app: conserva i dati e contatta il supporto.", null) }
    }
   }
  }
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
      result.success(mapOf("applicationId" to packageName, "displayName" to packageManager.getApplicationLabel(applicationInfo).toString(), "versionName" to info.versionName, "versionCode" to version, "signingSha256" to fingerprints))
     }
     "openDownload" -> {
      val url = call.argument<String>("url") ?: throw IllegalArgumentException()
      val uri = Uri.parse(url)
      if (uri.scheme != "https" || uri.host != "github.com" || uri.userInfo != null || uri.query != null || uri.fragment != null || !Regex("^/Kevinni05/gestionale_radio/releases/download/v[0-9A-Za-z.\\-]+/[A-Za-z0-9][0-9A-Za-z._\\-]*-[0-9A-Za-z.\\-]+\\.apk$").matches(uri.path ?: "")) throw IllegalArgumentException()
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
 override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
  MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "radiotech/local-data").setMethodCallHandler(null)
  localDataWorker.execute { localData?.close(); localData = null }
  localDataWorker.shutdown()
  super.cleanUpFlutterEngine(flutterEngine)
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
