package com.shiguang.diary_app

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import android.os.Build
import androidx.core.app.NotificationCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "vector_diary/countdown"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "schedule" -> {
                        val id = call.argument<Int>("id") ?: 0
                        val emoji = call.argument<String>("emoji") ?: "🎂"
                        val title = call.argument<String>("title") ?: "重要的日子"
                        val triggerAt = call.argument<Long>("at") ?: 0L
                        try {
                            CountdownAlarm.schedule(context, id, emoji, title, triggerAt)
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    "cancelAll" -> {
                        CountdownAlarm.cancelAll(context)
                        result.success(true)
                    }
                    "cancel" -> {
                        val id = call.argument<Int>("id") ?: 0
                        CountdownAlarm.cancelOne(context, id)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}

/** 倒数日提醒：精确闹钟 + 通知（图标用 emoji 实时绘制）。 */
object CountdownAlarm {
    const val CHANNEL_ID = "countdown_reminders"
    private const val REQ_BASE = 42000

    private fun flags(): Int =
        if (Build.VERSION.SDK_INT >= 23)
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        else PendingIntent.FLAG_UPDATE_CURRENT

    fun schedule(context: Context, id: Int, emoji: String, title: String, at: Long) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(context, CountdownReceiver::class.java).apply {
            putExtra("emoji", emoji)
            putExtra("title", title)
            putExtra("id", id)
            // data 固定为 eventId（不带时间戳），这样取消同一事件时能精确命中
            data = android.net.Uri.parse("countdown://event/$id")
        }
        val pi = PendingIntent.getBroadcast(context, REQ_BASE + id, intent, flags())

        if (Build.VERSION.SDK_INT >= 31 && !am.canScheduleExactAlarms()) {
            // 无精确闹钟权限 → 退化为非精确闹钟，仍能提醒（可能延迟数分钟）
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
        } else if (Build.VERSION.SDK_INT >= 23) {
            am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
        } else {
            am.setExact(AlarmManager.RTC_WAKEUP, at, pi)
        }
    }

    fun cancelAll(context: Context) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(context, CountdownReceiver::class.java)
        for (id in 0..2000) {
            am.cancel(PendingIntent.getBroadcast(context, REQ_BASE + id, intent, flags()))
        }
    }

    /** 取消单个事件的闹钟（删除事件时用）。data 与 schedule 保持一致才能命中同一 PendingIntent。 */
    fun cancelOne(context: Context, id: Int) {
        try {
            val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val intent = Intent(context, CountdownReceiver::class.java).apply {
                data = android.net.Uri.parse("countdown://event/$id")
            }
            val pi = PendingIntent.getBroadcast(context, REQ_BASE + id, intent,
                flags() or PendingIntent.FLAG_NO_CREATE)
            if (pi != null) {
                am.cancel(pi)
                pi.cancel()
            }
        } catch (_: Exception) {
        }
    }

    /** 把 emoji 绘制成通知图标（免图片资源依赖）。 */
    fun emojiBitmap(emoji: String, size: Int = 96): Bitmap {
        val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
        canvas.drawARGB(0, 0, 0, 0)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        paint.color = Color.WHITE
        paint.textAlign = Paint.Align.CENTER
        paint.textSize = size * 0.8f
        paint.typeface = Typeface.DEFAULT
        val metrics = paint.fontMetrics
        val baseline = size / 2f - (metrics.ascent + metrics.descent) / 2f
        canvas.drawText(emoji, size / 2f, baseline, paint)
        return bmp
    }

    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= 26) {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE)
                as NotificationManager
            if (nm.getNotificationChannel(CHANNEL_ID) == null) {
                val ch = NotificationChannel(
                    CHANNEL_ID,
                    "倒数日提醒",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "倒数日到期提醒"
                    enableVibration(true)
                }
                nm.createNotificationChannel(ch)
            }
        }
    }
}

class CountdownReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val emoji = intent.getStringExtra("emoji") ?: "🎂"
        val title = intent.getStringExtra("title") ?: "重要的日子"
        val id = intent.getIntExtra("id", 0)

        CountdownAlarm.ensureChannel(context)

        val launch = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("countdown_id", id.toString())
        }
        val piFlags = if (Build.VERSION.SDK_INT >= 23)
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        else PendingIntent.FLAG_UPDATE_CURRENT
        val contentPi = PendingIntent.getActivity(context, 9000 + id, launch, piFlags)

        val smallIcon = context.applicationInfo.icon
        val builder = NotificationCompat.Builder(context, CountdownAlarm.CHANNEL_ID)
            .setSmallIcon(if (smallIcon != 0) smallIcon else android.R.drawable.ic_dialog_info)
            .setLargeIcon(CountdownAlarm.emojiBitmap(emoji, 96))
            .setContentTitle(title)
            .setContentText("不要忘记重要的日子哦～")
            .setStyle(
                NotificationCompat.BigTextStyle().bigText("不要忘记重要的日子哦～")
            )
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(contentPi)

        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE)
            as NotificationManager
        nm.notify(9100 + id, builder.build())
    }
}
