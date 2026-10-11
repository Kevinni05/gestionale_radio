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
 private var operationalStore: OperationalStore? = null
 private var pending: MethodChannel.Result? = null
 private var pdfBytes: ByteArray? = null
 override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
  super.configureFlutterEngine(flutterEngine)
  operationalStore = OperationalStore(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
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
     "installVerifiedUpdate" -> {
      val url = call.argument<String>("url") ?: throw IllegalArgumentException()
      val digest = call.argument<String>("sha256") ?: throw IllegalArgumentException()
      val certificate = call.argument<String>("signingSha256") ?: throw IllegalArgumentException()
      val code = call.argument<Number>("versionCode")?.toLong() ?: throw IllegalArgumentException()
      if (!VerifiedApkDownload.busy.compareAndSet(false, true)) throw IllegalStateException()
      Thread({
       var file: java.io.File? = null
       try {
        val downloaded = VerifiedApkDownload.download(url, digest, java.io.File(cacheDir, "verified_updates"))
        file = downloaded
        @Suppress("DEPRECATION")
        val flags = if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES
        @Suppress("DEPRECATION")
        val archive = packageManager.getPackageArchiveInfo(downloaded.path, flags) ?: throw IllegalArgumentException()
        @Suppress("DEPRECATION")
        val installed = packageManager.getPackageInfo(packageName, flags)
        @Suppress("DEPRECATION")
        val archiveCode = if (Build.VERSION.SDK_INT >= 28) archive.longVersionCode else archive.versionCode.toLong()
        @Suppress("DEPRECATION")
        val installedCode = if (Build.VERSION.SDK_INT >= 28) installed.longVersionCode else installed.versionCode.toLong()
        @Suppress("DEPRECATION")
        val archiveSigners = if (Build.VERSION.SDK_INT >= 28) archive.signingInfo?.apkContentsSigners else archive.signatures
        @Suppress("DEPRECATION")
        val installedSigners = if (Build.VERSION.SDK_INT >= 28) installed.signingInfo?.apkContentsSigners else installed.signatures
        fun fingerprints(signers: Array<android.content.pm.Signature>?): Set<String> = signers?.map { signature -> MessageDigest.getInstance("SHA-256").digest(signature.toByteArray()).joinToString("") { "%02x".format(it) } }?.toSet() ?: emptySet()
        val actualSigners = fingerprints(archiveSigners)
        require(archive.packageName == packageName && archiveCode == code && code > installedCode)
        require(actualSigners.isNotEmpty() && actualSigners == fingerprints(installedSigners) && actualSigners.contains(certificate))
        val verifiedFile = downloaded
        runOnUiThread {
         try {
          check(!isFinishing && !isDestroyed)
          val uri = androidx.core.content.FileProvider.getUriForFile(this, "$packageName.verified-updates", verifiedFile)
          startActivity(Intent(Intent.ACTION_VIEW).apply {
           setDataAndType(uri, "application/vnd.android.package-archive")
           addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
          })
          result.success(true)
         } catch (error: Exception) { verifiedFile.delete(); result.error("UPDATE_UNAVAILABLE", "Impossibile avviare l’installazione verificata", null) }
         finally { VerifiedApkDownload.busy.set(false) }
        }
       } catch (error: Exception) {
        file?.delete()
        runOnUiThread { VerifiedApkDownload.busy.set(false); result.error("UPDATE_UNAVAILABLE", "Aggiornamento non verificato. Nessun pacchetto installato.", null) }
       }
      }, "radiotech-verified-update").start()
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
  operationalStore?.close()
  operationalStore = null
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

