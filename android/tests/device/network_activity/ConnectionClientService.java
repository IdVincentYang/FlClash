package com.follow.clash.observationclient;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Intent;
import android.os.Build;
import android.os.IBinder;

public final class ConnectionClientService extends Service {
    @Override public void onCreate() {
        super.onCreate();
        Notification.Builder builder;
        if (Build.VERSION.SDK_INT >= 26) {
            getSystemService(NotificationManager.class).createNotificationChannel(
                new NotificationChannel("controlled-traffic", "Controlled network test", NotificationManager.IMPORTANCE_LOW));
            builder = new Notification.Builder(this, "controlled-traffic");
        } else {
            builder = new Notification.Builder(this);
        }
        startForeground(1, builder.setContentTitle("Controlled network test")
            .setSmallIcon(android.R.drawable.stat_sys_upload).build());
    }

    @Override public IBinder onBind(Intent intent) { return null; }
}
