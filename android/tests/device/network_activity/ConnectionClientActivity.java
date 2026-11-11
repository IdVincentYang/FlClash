package com.follow.clash.observationclient;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;
import java.io.File;
import java.net.DatagramPacket;
import java.net.DatagramSocket;
import java.net.InetAddress;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.ArrayList;
import java.util.List;
import org.json.JSONArray;
import org.json.JSONObject;

public final class ConnectionClientActivity extends Activity {
    private static final java.util.concurrent.atomic.AtomicInteger jobs = new java.util.concurrent.atomic.AtomicInteger();

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        startConnections(getIntent());
    }

    @Override public void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        startConnections(intent);
    }

    private void startConnections(Intent intent) {
        Intent service = new Intent(this, ConnectionClientService.class);
        if (android.os.Build.VERSION.SDK_INT >= 26) startForegroundService(service);
        else startService(service);
        jobs.incrementAndGet();
        new Thread(() -> runConnections(intent), "controlled-connections").start();
    }

    private void runConnections(Intent intent) {
        JSONArray facts = new JSONArray();
        List<AutoCloseable> sockets = new ArrayList<>();
        try {
            String host = "10.0.2.2";
            String testCase = intent.getStringExtra("case");
            int count = intent.getIntExtra("count", 2);
            int direct = intent.getIntExtra("directPort", 0);
            int proxy = intent.getIntExtra("proxyPort", 0);
            if (count < 1 || count > 200 || direct < 1024 || proxy < 1024) throw new IllegalArgumentException("Invalid local fixture ports or budget");
            for (int i = 0; i < count; i++) {
                for (String protocol : new String[]{"tcp", "udp", "udp-unconnected"}) {
                    int port = i % 2 == 0 ? direct : proxy;
                    JSONObject fact = new JSONObject().put("case", testCase).put("index", i).put("protocol", protocol)
                        .put("package", getPackageName()).put("uid", android.os.Process.myUid()).put("destinationIP", host).put("destinationPort", port);
                    long start = android.os.SystemClock.elapsedRealtimeNanos();
                    try {
                        InetAddress address = InetAddress.getByName(host);
                        byte[] buffer = new byte[2048];
                        if ("tcp".equals(protocol)) {
                            Socket socket = new Socket();
                            sockets.add(socket);
                            socket.connect(new java.net.InetSocketAddress(address, port), 5000);
                            socket.setSoTimeout(5000);
                            fact.put("sourcePort", socket.getLocalPort()).put("sourceIP", socket.getLocalAddress().getHostAddress());
                            int bulk = intent.getIntExtra("bulkBytes", 0);
                            if (bulk < 0 || bulk > 1048576) throw new IllegalArgumentException("Bulk budget exceeded");
                            if (bulk > 0) fact.put("bulkBytes", bulk);
                            byte[] payload = (fact.toString() + "\n").getBytes(StandardCharsets.UTF_8);
                            socket.getOutputStream().write(payload);
                            int total = 0;
                            while (total < payload.length) {
                                int read = socket.getInputStream().read(buffer, total, payload.length - total);
                                if (read < 0) throw new IllegalStateException("Closed before echo");
                                total += read;
                            }
                            if (!java.util.Arrays.equals(payload, java.util.Arrays.copyOf(buffer, total))) throw new IllegalStateException("Wrong TCP echo");
                            if (bulk > 0) {
                                byte[] chunk = new byte[32768];
                                long bulkStart = android.os.SystemClock.elapsedRealtimeNanos();
                                for (int offset = 0; offset < bulk; offset += chunk.length) {
                                    int length = Math.min(chunk.length, bulk - offset);
                                    socket.getOutputStream().write(chunk, 0, length);
                                    int read = 0;
                                    while (read < length) {
                                        int countRead = socket.getInputStream().read(chunk, read, length - read);
                                        if (countRead < 0) throw new IllegalStateException("Closed during bulk echo");
                                        read += countRead;
                                    }
                                }
                                fact.put("bulkBytes", bulk).put("bulkElapsedNanos", android.os.SystemClock.elapsedRealtimeNanos() - bulkStart);
                            }
                        } else {
                            DatagramSocket socket = new DatagramSocket();
                            sockets.add(socket);
                            socket.setSoTimeout(5000);
                            if ("udp".equals(protocol)) socket.connect(address, port);
                            fact.put("sourcePort", socket.getLocalPort()).put("sourceIP", socket.getLocalAddress().getHostAddress());
                            byte[] payload = fact.toString().getBytes(StandardCharsets.UTF_8);
                            socket.send(new DatagramPacket(payload, payload.length, address, port));
                            DatagramPacket response = new DatagramPacket(buffer, buffer.length);
                            socket.receive(response);
                            if (!java.util.Arrays.equals(payload, java.util.Arrays.copyOf(buffer, response.getLength()))) throw new IllegalStateException("Wrong UDP echo");
                        }
                        fact.put("ok", true);
                    } catch (Exception error) {
                        fact.put("ok", false).put("error", error.toString());
                    }
                    fact.put("elapsedNanos", android.os.SystemClock.elapsedRealtimeNanos() - start);
                    if (intent.getBooleanExtra("short", false) && !sockets.isEmpty()) {
                        sockets.remove(sockets.size() - 1).close();
                    }
                    facts.put(fact);
                    Files.write(new File(getFilesDir(), "socket-facts.json").toPath(), facts.toString().getBytes(StandardCharsets.UTF_8));
                }
            }
            Thread.sleep(intent.getIntExtra("holdMillis", 20000));
        } catch (Exception error) {
            android.util.Log.e("ObservationClient", "Controlled fixture failed", error);
        } finally {
            for (AutoCloseable socket : sockets) { try { socket.close(); } catch (Exception ignored) { } }
            if (jobs.decrementAndGet() == 0) stopService(new Intent(this, ConnectionClientService.class));
            finish();
        }
    }
}
