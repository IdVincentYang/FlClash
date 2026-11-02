package com.follow.clash.testclient;

import android.app.Activity;
import android.content.Intent;
import android.net.ConnectivityManager;
import android.net.Network;
import android.net.NetworkCapabilities;
import android.os.Bundle;
import android.widget.TextView;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.net.HttpURLConnection;
import java.net.InetAddress;
import java.net.URL;
import org.json.JSONArray;
import org.json.JSONObject;

public final class ProbeActivity extends Activity {
    private TextView output;

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        output = new TextView(this);
        setContentView(output);
        probe(getIntent());
    }

    @Override public void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        probe(intent);
    }

    private Network network(boolean vpn) {
        ConnectivityManager manager = getSystemService(ConnectivityManager.class);
        for (Network value : manager.getAllNetworks()) {
            NetworkCapabilities caps = manager.getNetworkCapabilities(value);
            if (caps != null && caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == vpn
                    && (vpn || caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN))) return value;
        }
        return null;
    }

    private void probe(Intent intent) {
        final String mode = intent.getStringExtra("mode");
        final String endpoint = intent.getStringExtra("url");
        final String caseName = intent.getStringExtra("case");
        new Thread(() -> {
            JSONObject result = new JSONObject();
            try {
                result.put("case", caseName);
                result.put("mode", mode);
                result.put("vpnVisible", network(true) != null);
                if ("dns".equals(mode)) {
                    Network vpn = network(true);
                    if (vpn == null) throw new IllegalStateException("No VPN network visible");
                    JSONArray addresses = new JSONArray();
                    for (InetAddress address : vpn.getAllByName("avd.service.test")) {
                        addresses.put(address.getHostAddress());
                    }
                    result.put("addresses", addresses);
                } else {
                    URL url = new URL(endpoint);
                    if (!"http".equals(url.getProtocol()) || !"10.0.2.2".equals(url.getHost())
                            || url.getUserInfo() != null || url.getPort() < 1024) {
                        throw new IllegalArgumentException("Local emulator endpoint required");
                    }
                    HttpURLConnection connection;
                    if ("bypass".equals(mode)) {
                        Network physical = network(false);
                        if (physical == null) throw new IllegalStateException("No physical network visible");
                        connection = (HttpURLConnection) physical.openConnection(url);
                    } else if ("proxy".equals(mode)) {
                        connection = (HttpURLConnection) url.openConnection(new java.net.Proxy(
                                java.net.Proxy.Type.HTTP, new java.net.InetSocketAddress("127.0.0.1", 7890)));
                    } else {
                        connection = (HttpURLConnection) url.openConnection(java.net.Proxy.NO_PROXY);
                    }
                    connection.setInstanceFollowRedirects(false);
                    connection.setUseCaches(false);
                    connection.setConnectTimeout(3000);
                    connection.setReadTimeout(3000);
                    try {
                        result.put("status", connection.getResponseCode());
                        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
                        byte[] buffer = new byte[256];
                        int count;
                        try (java.io.InputStream stream = connection.getInputStream()) {
                            while ((count = stream.read(buffer)) >= 0) {
                                if (bytes.size() + count > 1024) throw new IllegalStateException("Response budget exceeded");
                                bytes.write(buffer, 0, count);
                            }
                        }
                        result.put("body", bytes.toString("UTF-8"));
                    } finally {
                        connection.disconnect();
                    }
                }
                result.put("ok", true);
            } catch (Exception error) {
                try { result.put("ok", false); result.put("error", error.getClass().getSimpleName()); }
                catch (Exception ignored) { throw new IllegalStateException(ignored); }
            }
            try {
                try (java.io.FileOutputStream stream = new java.io.FileOutputStream(new File(getFilesDir(), "result.json"))) {
                    stream.write(result.toString().getBytes(java.nio.charset.StandardCharsets.UTF_8));
                }
            } catch (Exception error) { throw new IllegalStateException(error); }
            runOnUiThread(() -> output.setText(result.toString()));
        }, "local-probe").start();
    }
}
