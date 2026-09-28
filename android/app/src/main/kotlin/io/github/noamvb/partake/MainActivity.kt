package io.github.noamvb.partake

import android.app.PictureInPictureParams
import android.os.Build
import android.util.Rational
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    // Set from Dart while a video is playing. Android 8-11 has no auto-enter
    // flag, so leaving the app needs the explicit call below. One UI's
    // quick-switch cannot be covered: it pauses this activity as a
    // background task, and every callback (this one, focus loss, top-resumed
    // loss) arrives only then, when enterPictureInPictureMode returns false.
    // Verified with logging in v0.2.11 on 28 Sep 2026.
    private var pipOnLeave = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "partake/pip")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setPipOnLeave" -> {
                        pipOnLeave = call.arguments as? Boolean ?: false
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (!pipOnLeave || Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        if (isInPictureInPictureMode) return
        try {
            enterPictureInPictureMode(
                PictureInPictureParams.Builder()
                    .setAspectRatio(Rational(16, 9))
                    .build()
            )
        } catch (_: IllegalStateException) {
            // The system refused (e.g. PiP disabled for the app in settings).
        }
    }
}
