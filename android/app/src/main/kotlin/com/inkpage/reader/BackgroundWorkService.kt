package com.inkpage.reader

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * 修書源、校驗書源這類使用者按了才開始的長工作（ADR 0058）。工作在 Dart 主
 * isolate 跑；這個前景服務只讓系統別凍結夜讀、關螢幕時 CPU 照跑（部分喚醒
 * 鎖），並在通知欄顯示進度：低重要性的頻道、只提醒一次、靜音，不跳出來。
 *
 * 前景服務在工作開始時（使用者剛按下去、App 看得到）啟動一次，之後只用
 * `notify` 更新：App 在背景時再呼叫 `startForeground` 會被系統拒絕。
 */
class BackgroundWorkService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null
    private var foreground = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        BackgroundWork.service = this
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            // 通知上的「停止」：交給 Dart 停，停好了它會叫 hide。
            BackgroundWork.requestStop()
            return START_NOT_STICKY
        }
        BackgroundWork.starting = false
        // 停下後還沒銷毀就又開始一件時，系統把這次交給同一個服務，onCreate 不會再跑。
        BackgroundWork.service = this
        // 用 startForegroundService 啟動的，一定要先 startForeground，不然
        // 系統過幾秒就讓 App 崩潰；工作在服務起來前就結束了也一樣。
        val content = BackgroundWork.content
        startInForeground(build(content ?: BackgroundWork.Content("夜讀", "", -1)))
        if (content == null) {
            finish()
        } else {
            acquireWakeLock()
        }
        return START_NOT_STICKY
    }

    /** 從最近使用滑掉夜讀等於停止（ADR 0058）：引擎還在，請 Dart 停下。 */
    override fun onTaskRemoved(rootIntent: Intent?) {
        BackgroundWork.requestStop()
        super.onTaskRemoved(rootIntent)
    }

    /** Android 15 起 dataSync 每天最多 6 小時，時間到了照停止處理。 */
    override fun onTimeout(startId: Int, fgsType: Int) {
        BackgroundWork.requestStop()
        finish()
    }

    override fun onDestroy() {
        releaseWakeLock()
        if (BackgroundWork.service === this) BackgroundWork.service = null
        super.onDestroy()
    }

    fun render(content: BackgroundWork.Content) {
        if (!foreground) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        manager.notify(NOTIFICATION_ID, build(content))
    }

    fun finish() {
        // 先放開：停下到銷毀之間又開始的一件要重新啟動前景服務，不能交給這個。
        if (BackgroundWork.service === this) BackgroundWork.service = null
        releaseWakeLock()
        if (foreground) {
            ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
            foreground = false
        }
        stopSelf()
    }

    private fun startInForeground(notification: Notification) {
        ServiceCompat.startForeground(
            this,
            NOTIFICATION_ID,
            notification,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
            } else {
                0
            },
        )
        foreground = true
    }

    private fun build(content: BackgroundWork.Content): Notification {
        createChannel()
        val open = PendingIntent.getActivity(
            this,
            REQUEST_OPEN,
            Intent(this, MainActivity::class.java)
                .setAction(ACTION_OPEN)
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val stop = PendingIntent.getService(
            this,
            REQUEST_STOP,
            Intent(this, BackgroundWorkService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            // 用資源編號引用：發布版不會把它當成沒用到而刪掉（#341）。
            .setSmallIcon(R.drawable.ic_stat_night_reader)
            .setContentTitle(content.title)
            .setContentText(content.text)
            .setContentIntent(open)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setShowWhen(false)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
        if (content.text != STOPPING) builder.addAction(0, "停止", stop)
        if (content.progress >= 0) {
            builder.setProgress(PROGRESS_MAX, content.progress, false)
        }
        return builder.build()
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        // 重要性建立後就改不了；這是新的頻道，從一開始就是低：不跳出、不出聲。
        val channel = NotificationChannel(CHANNEL_ID, "背景工作", NotificationManager.IMPORTANCE_LOW)
        channel.description = "修書源、校驗書源時的進度"
        channel.setShowBadge(false)
        channel.setSound(null, null)
        channel.enableVibration(false)
        manager.createNotificationChannel(channel)
    }

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        val power = getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return
        wakeLock = power.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "NightReader:BackgroundWork").apply {
            setReferenceCounted(false)
            acquire(WAKE_LOCK_TIMEOUT_MS)
        }
    }

    private fun releaseWakeLock() {
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
    }

    companion object {
        const val CHANNEL_ID = "com.night_reader.background_work"
        const val ACTION_OPEN = "com.inkpage.reader.background_work.OPEN"
        private const val ACTION_STOP = "com.inkpage.reader.background_work.STOP"
        private const val NOTIFICATION_ID = 0x4e52
        private const val REQUEST_OPEN = 0x4e52
        private const val REQUEST_STOP = 0x4e53

        /** 和 Dart 端 `BackgroundWork.progressMax` 一致。 */
        private const val PROGRESS_MAX = 1000

        /** 按了停止、停好之前的內文；這時不再放「停止」按鈕。 */
        private const val STOPPING = "正在停下…"

        /** 和 dataSync 每天的上限一樣長；工作結束時就放掉。 */
        private const val WAKE_LOCK_TIMEOUT_MS = 6L * 60 * 60 * 1000
    }
}

/** Dart 端 `BackgroundWork` 的通道（`night_reader/background_work`）與服務的狀態。 */
object BackgroundWork {
    data class Content(val title: String, val text: String, val progress: Int)

    private var channel: MethodChannel? = null

    /** 要顯示的內容；null 是工作結束了。 */
    var content: Content? = null

    /** 已經叫系統啟動服務、服務還沒起來。 */
    var starting = false

    var service: BackgroundWorkService? = null

    fun install(context: Context, messenger: BinaryMessenger) {
        val app = context.applicationContext
        val channel = MethodChannel(messenger, "night_reader/background_work")
        this.channel = channel
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "show" -> {
                    val next = Content(
                        call.argument<String>("title") ?: "",
                        call.argument<String>("text") ?: "",
                        call.argument<Int>("progress") ?: -1,
                    )
                    content = next
                    val running = service
                    if (running != null) {
                        running.render(next)
                        result.success(true)
                    } else if (starting) {
                        result.success(true)
                    } else {
                        try {
                            starting = true
                            ContextCompat.startForegroundService(
                                app,
                                Intent(app, BackgroundWorkService::class.java),
                            )
                            result.success(true)
                        } catch (e: Exception) {
                            // 例如 App 已經在背景（Android 12 起不准啟動前景服務）。
                            starting = false
                            content = null
                            result.success(false)
                        }
                    }
                }
                "hide" -> {
                    content = null
                    service?.finish()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    fun requestStop() {
        channel?.invokeMethod("stop", null)
    }

    fun requestOpen() {
        channel?.invokeMethod("open", null)
    }
}
