package my.cukup.cukup

import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/** Receives a screenshot from the Android share sheet and hands its path to Flutter. */
class MainActivity : FlutterFragmentActivity() {
    private var channel: MethodChannel? = null
    private var pending: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "cukup/share")
        ch.setMethodCallHandler { call, result ->
            if (call.method == "take") {
                result.success(pending)
                pending = null
            } else if (call.method == "install") {
                result.success(installApk(call.arguments as String))
            } else {
                result.notImplemented()
            }
        }
        channel = ch
        pending = copyShared(intent)
    }

    /** Opens the system installer for a downloaded update. Returns "ok", "needs_permission" or "error". */
    private fun installApk(path: String): String {
        return try {
            if (!packageManager.canRequestPackageInstalls()) {
                // First time only: Android asks the user to allow installs from Cukup.
                startActivity(Intent(android.provider.Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName")))
                return "needs_permission"
            }
            val uri = androidx.core.content.FileProvider.getUriForFile(this, "$packageName.updates", File(path))
            val i = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(i)
            "ok"
        } catch (e: Exception) {
            "error"
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val path = copyShared(intent)
        if (path != null) {
            pending = path
            channel?.invokeMethod("shared", null)
        }
    }

    @Suppress("DEPRECATION")
    private fun copyShared(i: Intent?): String? {
        if (i == null || i.action != Intent.ACTION_SEND) return null
        val uri = i.getParcelableExtra<Uri>(Intent.EXTRA_STREAM) ?: return null
        return try {
            val out = File(cacheDir, "shared-${System.currentTimeMillis()}.img")
            contentResolver.openInputStream(uri)?.use { input -> out.outputStream().use { input.copyTo(it) } } ?: return null
            i.action = Intent.ACTION_MAIN // so a rotation or restart does not import it twice
            out.absolutePath
        } catch (e: Exception) {
            null
        }
    }
}
