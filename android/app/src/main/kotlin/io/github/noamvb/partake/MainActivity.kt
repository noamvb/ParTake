package io.github.noamvb.partake

import android.app.PictureInPictureParams
import android.os.Build
import android.util.Rational
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    // Set from Dart while a video is playing. Android 12's auto-enter flag
    // only fires on the home gesture; quick-switching to the previous app
    // (and every leave on Android 8-11) needs the explicit calls below.
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
        enterPipIfPlaying()
    }

    // One UI's quick-switch hands the top spot to the launcher first and then
    // pauses this activity as a background task, where Android refuses PiP
    // (auto-enter and explicit alike). Losing the top spot while still
    // resumed is the last moment PiP is allowed, so enter it then.
    override fun onTopResumedActivityChanged(isTopResumedActivity: Boolean) {
        super.onTopResumedActivityChanged(isTopResumedActivity)
        if (isTopResumedActivity || isInMultiWindowMode || isFinishing) return
        enterPipIfPlaying()
    }

    private fun enterPipIfPlaying() {
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
