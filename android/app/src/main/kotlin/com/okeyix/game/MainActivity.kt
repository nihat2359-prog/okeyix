package com.okeyix.game

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import androidx.core.content.FileProvider
import android.content.Intent
import android.content.ClipData
import java.io.File

class ComparisonFileProvider : FileProvider()

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.okeyix.game/comparison_share")
            .setMethodCallHandler { call, result ->
                if (call.method == "shareInviteWhatsApp") {
                    val text = call.argument<String>("text")
                    if (text == null || text.length !in 1..4000) {
                        result.error("INVALID_INVITE", "Invalid invitation text", null)
                        return@setMethodCallHandler
                    }
                    val intent = Intent(Intent.ACTION_SEND).apply {
                        type = "text/plain"
                        putExtra(Intent.EXTRA_TEXT, text)
                    }
                    var opened = false
                    for (target in listOf("com.whatsapp", "com.whatsapp.w4b")) {
                        try {
                            intent.setPackage(target)
                            startActivity(intent)
                            opened = true
                            break
                        } catch (_: android.content.ActivityNotFoundException) {
                            // Try WhatsApp Business, then return a localized UI error.
                        } catch (_: SecurityException) { }
                    }
                    if (opened) result.success(null)
                    else result.error("WHATSAPP_UNAVAILABLE", "WhatsApp unavailable", null)
                    return@setMethodCallHandler
                }
                if (call.method != "shareComparison") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                try {
                    val path = call.argument<String>("path") ?: throw IllegalArgumentException("Path required")
                    val file = File(path).canonicalFile
                    val allowed = File(cacheDir, "okeyix_comparisons").canonicalFile
                    require(file.parentFile == allowed && file.extension == "png" && file.isFile)
                    require(file.length() in 8..20_000_000)
                    val uri = FileProvider.getUriForFile(this, "$packageName.comparison_share", file)
                    val intent = Intent(Intent.ACTION_SEND).apply {
                        type = "image/png"
                        putExtra(Intent.EXTRA_STREAM, uri)
                        clipData = ClipData.newRawUri("Okeyix", uri)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    }
                    startActivity(Intent.createChooser(intent, "Okeyix"))
                    result.success(null)
                } catch (e: Exception) {
                    result.error("SHARE_UNAVAILABLE", "Unable to open image sharing", null)
                }
            }
    }
}
