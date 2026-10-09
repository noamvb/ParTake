package io.github.noamvb.partake

import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.res.Configuration
import android.graphics.drawable.Icon
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
    private var pipChannel: MethodChannel? = null
    private var audioOnlyReceiver: BroadcastReceiver? = null

    companion object {
        private const val ACTION_AUDIO_ONLY = "io.github.noamvb.partake.PIP_AUDIO_ONLY"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pipChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "partake/pip")
        pipChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "setPipOnLeave" -> {
                    pipOnLeave = call.arguments as? Boolean ?: false
                    if (pipOnLeave && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        setPictureInPictureParams(pipParams())
                    }
                    result.success(null)
                }
                "closePipWindow" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                        isInPictureInPictureMode
                    ) {
                        moveTaskToBack(false)
                    }
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
            enterPictureInPictureMode(pipParams())
        } catch (_: IllegalStateException) {
            // The system refused (e.g. PiP disabled for the app in settings).
        }
    }

    private fun pipParams(): PictureInPictureParams {
        val intent = PendingIntent.getBroadcast(
            this,
            0,
            Intent(ACTION_AUDIO_ONLY).setPackage(packageName),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val action = RemoteAction(
            Icon.createWithResource(this, R.drawable.ic_pip_headphones),
            "Background audio",
            "Close the video and keep listening",
            intent
        )
        return PictureInPictureParams.Builder()
            .setAspectRatio(Rational(16, 9))
            .setActions(listOf(action))
            .build()
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        if (isInPictureInPictureMode) {
            setPictureInPictureParams(pipParams())
            if (audioOnlyReceiver == null) {
                val receiver = object : BroadcastReceiver() {
                    override fun onReceive(context: Context?, intent: Intent?) {
                        if (intent?.action == ACTION_AUDIO_ONLY) {
                            pipChannel?.invokeMethod("audioOnlyRequested", null)
                        }
                    }
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    registerReceiver(
                        receiver,
                        IntentFilter(ACTION_AUDIO_ONLY),
                        Context.RECEIVER_NOT_EXPORTED
                    )
                } else {
                    registerReceiver(receiver, IntentFilter(ACTION_AUDIO_ONLY))
                }
                audioOnlyReceiver = receiver
            }
        } else {
            unregisterAudioOnlyReceiver()
        }
    }

    private fun unregisterAudioOnlyReceiver() {
        audioOnlyReceiver?.let { unregisterReceiver(it) }
        audioOnlyReceiver = null
    }

    override fun onDestroy() {
        unregisterAudioOnlyReceiver()
        super.onDestroy()
    }
}
