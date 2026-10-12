package app.vaultify.vaultify

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.os.Bundle
import android.os.PersistableBundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Biometric unlock: local_auth needs a FragmentActivity for its prompt.
class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // Screen privacy: FLAG_SECURE blocks screenshots and screen
        // recording, and hides the app-switcher preview. Set before the
        // first frame so nothing is ever captured.
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE,
        )
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Sensitive clipboard flag: copies a password marked as sensitive so
        // Android 13+ hides it in the clipboard preview (see
        // lib/platform/sensitive_clipboard.dart).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.vaultify/clipboard")
            .setMethodCallHandler { call, result ->
                if (call.method == "copySensitive") {
                    val text = call.argument<String>("text") ?: ""
                    val clip = ClipData.newPlainText("", text)
                    clip.description.extras = PersistableBundle().apply {
                        // ClipDescription.EXTRA_IS_SENSITIVE (API 33); older
                        // versions ignore it.
                        putBoolean("android.content.extra.IS_SENSITIVE", true)
                    }
                    val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                    clipboard.setPrimaryClip(clip)
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
    }
}
