package com.follow.clash.observationtest;

import android.app.Activity;
import android.app.Instrumentation;
import android.os.Bundle;
import android.util.Base64;
import java.io.File;
import java.io.FileOutputStream;
import java.lang.reflect.Method;
import java.lang.reflect.Proxy;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.security.MessageDigest;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.TimeUnit;
import org.json.JSONArray;
import org.json.JSONObject;

public final class ObservationInstrumentation extends Instrumentation {
    private Bundle arguments;
    private File directory;
    private ClassLoader loader;
    private Class<?> function;
    private Object unit;
    private JSONObject ticket;
    private int sequence;
    private JSONObject sharedSettings;

    @Override public void onCreate(Bundle args) {
        arguments = args;
        start();
    }

    private Object singleton(String name) throws Exception {
        return loader.loadClass(name).getField("INSTANCE").get(null);
    }

    private Object call(String type, String name, Class<?>[] parameters, Object... args) throws Exception {
        Object target = singleton(type);
        for (Method method : target.getClass().getMethods()) {
            if ((method.getName().equals(name) || method.getName().startsWith(name + "-"))
                    && java.util.Arrays.equals(method.getParameterTypes(), parameters)) return method.invoke(target, args);
        }
        throw new NoSuchMethodException(type + "." + name);
    }

    private Object callback(java.util.function.Consumer<Object> consumer) {
        return Proxy.newProxyInstance(loader, new Class<?>[]{function}, (proxy, method, values) -> {
            if ("invoke".equals(method.getName())) { consumer.accept(values[0]); return unit; }
            if ("hashCode".equals(method.getName())) return System.identityHashCode(proxy);
            if ("equals".equals(method.getName())) return proxy == values[0];
            return "observation-fixture-callback";
        });
    }

    private synchronized void appendEvent(Object data) {
        if (data == null) return;
        try {
            if (!"com.follow.clash.dev".equals(getTargetContext().getPackageName())) throw new IllegalStateException("Development APK required");
            JSONObject envelope = new JSONObject((String) data);
            JSONArray events = envelope.optJSONArray("arguments");
            if (events == null) return;
            try (FileOutputStream stream = new FileOutputStream(new File(directory, "events.jsonl"), true)) {
                for (int i = 0; i < events.length(); i++) {
                    JSONObject event = events.getJSONObject(i);
                    if ("request".equals(event.optString("type"))) {
                        stream.write((event.getJSONObject("data").toString() + "\n").getBytes(StandardCharsets.UTF_8));
                    }
                }
            }
        } catch (Exception error) { throw new IllegalStateException(error); }
    }

    private JSONObject control(JSONObject request) throws Exception {
        JSONObject result = new JSONObject((String) call("com.follow.clash.core.Core", "requestControl", new Class<?>[]{String.class}, request.toString()));
        if (result.has("error")) throw new IllegalStateException(result.toString());
        return result;
    }

    private Object rpc(String method, Object data) throws Exception {
        ArrayBlockingQueue<byte[]> response = new ArrayBlockingQueue<>(1);
        JSONObject request = new JSONObject().put("id", "observation-" + (++sequence)).put("method", method).put("arguments", data);
        call("com.follow.clash.core.Core", "invokeMethod", new Class<?>[]{String.class, function}, request.toString(), callback(value -> response.add((byte[]) value)));
        byte[] bytes = response.poll(45, TimeUnit.SECONDS);
        if (bytes == null) throw new IllegalStateException("Timed out: " + method);
        JSONObject result = new JSONObject(new String(bytes, StandardCharsets.UTF_8));
        if (result.has("error")) throw new IllegalStateException(method + ": " + result);
        return result.get("result");
    }

    private void write(String name, Object data) throws Exception {
        File temporary = new File(directory, name + ".tmp");
        String encoded = data instanceof String ? JSONObject.quote((String) data) : data.toString();
        Files.write(temporary.toPath(), encoded.getBytes(StandardCharsets.UTF_8));
        if (!temporary.renameTo(new File(directory, name))) throw new IllegalStateException("Cannot publish " + name);
    }

    private String hash(byte[] bytes) throws Exception {
        StringBuilder value = new StringBuilder();
        for (byte item : MessageDigest.getInstance("SHA-256").digest(bytes)) value.append(String.format(java.util.Locale.ROOT, "%02x", item));
        return value.toString();
    }

    private Object gsonModel(JSONObject json, String type) throws Exception {
        Class<?> gson = loader.loadClass("com.google.gson.Gson");
        return gson.getMethod("fromJson", String.class, Class.class).invoke(gson.getConstructor().newInstance(), json.toString(), loader.loadClass(type));
    }

    private JSONObject gsonObject(Object value) throws Exception {
        Class<?> gson = loader.loadClass("com.google.gson.Gson");
        return new JSONObject((String) gson.getMethod("toJson", Object.class).invoke(gson.getConstructor().newInstance(), value));
    }

    private Object await(Object deferred) throws Exception {
        Class<?> job = loader.loadClass("kotlinx.coroutines.Job");
        Method completed = job.getMethod("isCompleted");
        long deadline = android.os.SystemClock.elapsedRealtime() + 60000;
        while (!(Boolean) completed.invoke(deferred)) {
            if (android.os.SystemClock.elapsedRealtime() >= deadline) throw new IllegalStateException("Native apply did not finish");
            Thread.sleep(25);
        }
        return loader.loadClass("kotlinx.coroutines.Deferred").getMethod("getCompleted").invoke(deferred);
    }

    private JSONObject accept(String key, String kind, String yaml, JSONArray uses) throws Exception {
        String origin = "config".equals(kind) ? "application-config" : key;
        JSONObject source = new JSONObject(ticket.toString()).put("sources", new JSONObject().put(origin, 0));
        JSONObject request = new JSONObject().put("action", "review").put("key", key).put("kind", kind)
            .put("identity", hash(key.getBytes(StandardCharsets.UTF_8))).put("settings", hash(new byte[0]))
            .put("body", yaml).put("routing", "source").put("source", source).put("uses", uses);
        JSONObject result = (JSONObject) rpc("sourceAcceptance", request);
        if (!"accepted".equals(result.getString("status"))) {
            request.put("action", "accept").put("candidate", result.getString("candidate"));
            result = (JSONObject) rpc("sourceAcceptance", request);
        }
        if (!"accepted".equals(result.getString("status"))) throw new IllegalStateException(result.toString());
        return result.getJSONObject("use");
    }

    private void prepare() throws Exception {
        Object state = call("com.follow.clash.ServiceState", "getRequestState", new Class<?>[]{});
        call("com.follow.clash.ServiceState", "initializeRequestState", new Class<?>[]{long.class, boolean.class}, gsonObject(state).getLong("revision"), false);
        rpc("initClash", new JSONObject().put("home-dir", getTargetContext().getFilesDir().getPath()).put("version", android.os.Build.VERSION.SDK_INT));
        String client = control(new JSONObject().put("action", "attach")).getString("client");
        control(new JSONObject().put("action", "ready").put("client", client));
        long dataset = control(new JSONObject().put("action", "inspect").put("client", client)).getLong("dataset");
        ticket = new JSONObject().put("client", client).put("dataset", dataset)
            .put("sources", new JSONObject().put("profile:1", 0).put("application-config", 0));
        String yaml = new String(Base64.decode(arguments.getString("profile"), Base64.DEFAULT), StandardCharsets.UTF_8);
        JSONArray uses = new JSONArray().put(accept("profile:1", "profile", yaml, new JSONArray()));
        uses.put(accept("config:1", "config", yaml, uses));
        byte[] bytes = yaml.getBytes(StandardCharsets.UTF_8);
        String yamlHash = hash(bytes);
        File inputs = new File(getTargetContext().getFilesDir(), "config-inputs");
        if (!inputs.isDirectory() && !inputs.mkdirs()) throw new IllegalStateException("No input directory");
        Files.write(new File(inputs, yamlHash + ".yaml").toPath(), bytes);
        JSONObject manifest = new JSONObject().put("version", 2).put("yamlSha256", yamlHash).put("profileId", 1).put("profileName", "Observation fixture")
            .put("dependencies", new JSONArray().put("profile:1").put("application-config"))
            .put("selectedMap", new JSONObject().put("GLOBAL", "fixture.group")).put("testUrl", "http://127.0.0.1/").put("sourceUses", uses);
        byte[] manifestBytes = manifest.toString().getBytes(StandardCharsets.UTF_8);
        String input = hash(manifestBytes);
        Files.write(new File(inputs, input + ".json").toPath(), manifestBytes);
        JSONObject vpn = new JSONObject().put("enable", true).put("port", 0).put("ipv6", false).put("dnsHijacking", false)
            .put("allowBypass", false).put("systemProxy", false).put("bypassDomain", new JSONArray()).put("stack", "gvisor")
            .put("routeAddress", new JSONArray().put("0.0.0.0/0"))
            .put("accessControlProps", new JSONObject().put("enable", true).put("mode", "ACCEPT_SELECTED")
                .put("acceptList", new JSONArray().put("com.follow.clash.observationclient.a").put("com.follow.clash.observationclient.b")
                    .put("com.follow.clash.observationclient.shareda").put("com.follow.clash.observationclient.sharedb"))
                .put("rejectList", new JSONArray()));
        Class<?> sharedClass = loader.loadClass("com.follow.clash.models.SharedState");
        Object defaults = sharedClass.getConstructor().newInstance();
        JSONObject shared = gsonObject(defaults).put("vpnOptions", vpn);
        sharedSettings = shared;
        call("com.follow.clash.ServiceState", "syncSharedState", new Class<?>[]{sharedClass}, gsonModel(shared, sharedClass.getName()));
        long request = (Long) call("com.follow.clash.ServiceState", "prepareRunIntent", new Class<?>[]{boolean.class, String.class, boolean.class}, true, "ui", false);
        JSONObject apply = new JSONObject().put("inputId", input).put("active", true).put("requestId", request).put("source", ticket);
        Class<?> jsonClass = loader.loadClass("com.google.gson.JsonObject");
        Object deferred = call("com.follow.clash.ServiceState", "applyConfig", new Class<?>[]{jsonClass}, gsonModel(apply, jsonClass.getName()));
        JSONObject result = gsonObject(await(deferred));
        write("apply.json", result);
        if (!"activated".equals(result.optString("status"))) throw new IllegalStateException(result.toString());
        write("ready.json", new JSONObject().put("inputId", input).put("pid", android.os.Process.myPid()));
    }

    private JSONObject benchmarkIdentity(JSONObject metadata) throws Exception {
        Object protection = call("com.follow.clash.ServiceState", "getProtection", new Class<?>[]{});
        Object service = protection.getClass().getMethod("getFirst").invoke(protection);
        Method resolveUid = service.getClass().getDeclaredMethod("resolveUid", int.class, java.net.InetSocketAddress.class, java.net.InetSocketAddress.class);
        Method resolvePackage = service.getClass().getDeclaredMethod("resolvePackage", int.class);
        resolveUid.setAccessible(true);
        resolvePackage.setAccessible(true);
        java.net.InetSocketAddress source = new java.net.InetSocketAddress(metadata.getString("sourceIP"), metadata.getInt("sourcePort"));
        java.net.InetSocketAddress target = new java.net.InetSocketAddress(metadata.getString("destinationIP"), metadata.getInt("destinationPort"));
        JSONArray uidTimes = new JSONArray(), packageTimes = new JSONArray();
        for (int i = 0; i < 100; i++) {
            long start = android.os.SystemClock.elapsedRealtimeNanos();
            int uid = (Integer) resolveUid.invoke(service, 6, source, target);
            long middle = android.os.SystemClock.elapsedRealtimeNanos();
            JSONObject identity = new JSONObject((String) resolvePackage.invoke(service, uid));
            long end = android.os.SystemClock.elapsedRealtimeNanos();
            if (uid != metadata.getInt("uid") || !"known".equals(identity.getString("status"))) throw new IllegalStateException("Benchmark socket ownership changed");
            uidTimes.put(middle - start);
            packageTimes.put(end - middle);
        }
        return new JSONObject().put("uidNanos", uidTimes).put("packageNanos", packageTimes);
    }

    @Override public void onStart() {
        Bundle result = new Bundle();
        int code = Activity.RESULT_CANCELED;
        try {
            directory = new File(getTargetContext().getFilesDir(), "observation-fixture");
            if (!directory.isDirectory() && !directory.mkdirs()) throw new IllegalStateException("No output directory");
            for (File file : directory.listFiles()) if (!file.delete()) throw new IllegalStateException("Cannot clear previous fixture");
            loader = getTargetContext().getClassLoader();
            function = loader.loadClass("kotlin.jvm.functions.Function1");
            unit = loader.loadClass("kotlin.Unit").getField("INSTANCE").get(null);
            call("com.follow.clash.ServiceController", "setEventListener", new Class<?>[]{function}, callback(this::appendEvent));
            prepare();
            long deadline = android.os.SystemClock.elapsedRealtime() + 240000;
            while (android.os.SystemClock.elapsedRealtime() < deadline) {
                File commandFile = new File(directory, "command.json");
                if (!commandFile.isFile()) { Thread.sleep(50); continue; }
                JSONObject command = new JSONObject(new String(Files.readAllBytes(commandFile.toPath()), StandardCharsets.UTF_8));
                if (!commandFile.delete()) throw new IllegalStateException("Command is still owned");
                String action = command.getString("action");
                if ("stop".equals(action)) break;
                Object data;
                if ("snapshot".equals(action)) data = rpc("getConnections", JSONObject.NULL);
                else if ("fact".equals(action)) data = rpc("getConfigState", JSONObject.NULL);
                else if ("benchmark".equals(action)) data = benchmarkIdentity(command.getJSONObject("metadata"));
                else if ("cpu".equals(action)) data = new JSONObject().put("cpuMillis", android.os.Process.getElapsedCpuTime())
                    .put("wallMillis", android.os.SystemClock.elapsedRealtime());
                else if ("patch".equals(action)) data = rpc("updateConfig", command.getJSONObject("patch"));
                else if ("capture".equals(action)) {
                    sharedSettings.getJSONObject("vpnOptions").getJSONObject("accessControlProps").put("acceptList", command.getJSONArray("packages"));
                    Class<?> sharedClass = loader.loadClass("com.follow.clash.models.SharedState");
                    call("com.follow.clash.ServiceState", "syncSharedState", new Class<?>[]{sharedClass}, gsonModel(sharedSettings, sharedClass.getName()));
                    long request = (Long) call("com.follow.clash.ServiceState", "prepareRunIntent", new Class<?>[]{boolean.class, String.class, boolean.class}, true, "ui", false);
                    JSONObject fact = (JSONObject) rpc("getConfigState", JSONObject.NULL);
                    JSONObject apply = new JSONObject().put("inputId", fact.getString("inputId")).put("active",true).put("requestId",request).put("source",ticket);
                    Class<?> jsonClass = loader.loadClass("com.google.gson.JsonObject");
                    data = gsonObject(await(call("com.follow.clash.ServiceState", "applyConfig", new Class<?>[]{jsonClass}, gsonModel(apply,jsonClass.getName()))));
                }
                else throw new IllegalArgumentException("Unsupported fixture command");
                write(command.getString("result") + ".json", data);
            }
            result.putString("result", "completed");
            code = Activity.RESULT_OK;
        } catch (Throwable error) {
            result.putString("error", error.toString());
            try { write("failure.json", new JSONObject().put("error", android.util.Log.getStackTraceString(error))); }
            catch (Exception ignored) { result.putString("writeError", ignored.toString()); }
        } finally {
            try {
                await(call("com.follow.clash.ServiceState", "requestStop", new Class<?>[]{Long.class}, new Object[]{null}));
            } catch (Exception error) { result.putString("cleanupError", error.toString()); }
            finish(code, result);
        }
    }
}
