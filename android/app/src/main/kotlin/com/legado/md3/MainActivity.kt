package com.legado.md3

import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {

    private val channelName = "legado/file_intent"
    private var pending: String? = null
    private var channel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pending = resolveIntent(intent)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel?.setMethodCallHandler { call, result ->
            if (call.method == "getInitialFile") {
                val p = pending
                pending = null
                result.success(p)
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val p = resolveIntent(intent)
        if (p != null) {
            pending = p
            channel?.invokeMethod("onFileOpened", p)
        }
    }

    /**
     * 统一解析「打开文件 / 深度链接 / 分享文本」三类入口：
     *  - file/content   -> 复制到缓存目录，返回本地路径
     *  - legado / http  -> 返回原始 URI 字符串（Dart 侧按 scheme 路由）
     *  - 分享文本(URL)  -> 返回文本（Dart 侧作为源导入地址）
     */
    private fun resolveIntent(intent: Intent?): String? {
        val uri: Uri? = intent?.data
        if (uri != null) {
            return try {
                when (uri.scheme) {
                    "file" -> uri.path
                    "content" -> {
                        val name = uri.lastPathSegment ?: "opened_${System.currentTimeMillis()}"
                        val out = File(cacheDir, sanitize(name))
                        contentResolver.openInputStream(uri)?.use { input ->
                            out.outputStream().use { o -> input.copyTo(o) }
                        }
                        out.absolutePath
                    }
                    "legado" -> uri.toString()
                    "http", "https" -> uri.toString()
                    else -> null
                }
            } catch (e: Exception) {
                null
            }
        }
        // ACTION_SEND：从浏览器「分享」的文本链接
        if (intent?.type != null && intent?.type!!.startsWith("text/")) {
            val text = intent?.getStringExtra(Intent.EXTRA_TEXT)
            if (!text.isNullOrBlank()) return text.trim()
        }
        return null
    }

    private fun sanitize(name: String): String {
        val base = name.substringAfterLast('/')
        return if (base.contains('.')) base else "$base.txt"
    }
}
