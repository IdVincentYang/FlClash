package com.follow.clash.core;

import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

public final class R09Fixture {
    private static native void setup(TunInterface callback, String scenario);
    private static native void arm();
    private static native String snapshot();
    private static native String stats();
    private static native boolean waitPoint();
    private static native void continuePoint();
    private static native boolean socket();
    private static native void removeHome();

    private static void check(boolean value, String detail) {
        if (!value) throw new AssertionError(detail);
    }

    private static void joined(Thread thread) throws Exception {
        thread.join(5000);
        check(!thread.isAlive(), "native boundary retained a lock");
    }

    public static void main(String[] args) throws Exception {
        Core core = Core.INSTANCE;
        String scenario = args[0];
        setup(new TunInterface() {
            public boolean protect(int fd) { return true; }
            public int resolveUid(int protocol, String source, String target) { return 1; }
            public String resolvePackage(int uid) { return "{}"; }
        }, scenario);
        RequestSocketInterface callback = (state, fd) -> true;
        try {
            core.setRequestSocketListener(callback);
            arm();
            if (scenario.equals("healthy")) {
                check(!core.requestControl("{\"action\":\"inspect\",\"client\":\"client\",\"key\":\"source\"}").contains("error"), "healthy requestControl");
                core.setTunRequestIdentity("service", 2);
                boolean stale = false;
                try { core.setTunRequestIdentity("service",1); } catch (IllegalStateException expected) { stale = expected.getMessage().equals("request_unavailable"); }
                check(stale, "stale identity was adopted");
                check(!core.stopTunRequest("service", 1), "old identity stopped new TUN");
                check(core.stopTunRequest("service", 2), "new identity failed to stop");
            } else if (scenario.equals("foreign")) {
                boolean rejected = false;
                try { core.setTunRequestIdentity("other",2); } catch (IllegalStateException expected) { rejected = expected.getMessage().equals("request_unavailable"); }
                check(rejected && snapshot().contains("\"fault\":false"), "foreign service was adopted or poisoned healthy owner");
                check(core.stopTunRequest("service",1), "foreign adoption changed owner");
            } else if (scenario.equals("reader")) {
                CountDownLatch entered = new CountDownLatch(1), release = new CountDownLatch(1);
                core.setRequestSocketListener((state, fd) -> {
                    entered.countDown();
                    try { return release.await(5, TimeUnit.SECONDS); } catch (InterruptedException error) { throw new AssertionError(error); }
                });
                AtomicReference<Throwable> error = new AtomicReference<>();
                Thread reader = new Thread(() -> { try { check(socket(), "reader callback refused"); } catch(Throwable failure) {error.set(failure);} });
                reader.start(); check(entered.await(5, TimeUnit.SECONDS), "reader never entered");
                CountDownLatch replacementStarted = new CountDownLatch(1);
                Thread replacement = new Thread(() -> { replacementStarted.countDown();try {core.setRequestSocketListener(callback);} catch(Throwable failure) {error.set(failure);} });
                replacement.start();replacementStarted.await();
                Thread.sleep(50); check(replacement.isAlive(), "replaced a borrowed GlobalRef");
                release.countDown(); joined(reader);joined(replacement);
                check(error.get() == null, String.valueOf(error.get()));
                check(core.stopTunRequest("service",1), "reader cleanup");
            } else {
                if (scenario.contains("callback-")) {
                    boolean failed = false;
                    try { core.setRequestSocketListener((state, fd) -> false); }
                    catch (IllegalStateException expected) { failed = expected.getMessage().equals("request_restart_required"); }
                    check(failed, "setter reported success");
                } else if (scenario.contains("identity-")) {
                    boolean failed = false;
                    try { core.setTunRequestIdentity("service",2); }
                    catch (IllegalStateException expected) { failed = expected.getMessage().equals("request_restart_required"); }
                    check(failed, "identity reported success");
                    String state = snapshot();
                    check(state.contains("\"service\":\"service\"") && state.contains("\"generation\":1"), "identity pair not restored: "+state);
                } else if (scenario.startsWith("stop-")) {
                    boolean failed = false;
                    try { core.stopTunRequest("service",1); }
                    catch (IllegalStateException expected) { failed = expected.getMessage().equals("request_restart_required"); }
                    check(failed, "stop failure looked like a normal mismatch");
                    check(snapshot().contains("\"handler\":true"), "uncertain close dropped owner");
                } else if (scenario.endsWith("control-locked")) {
                    AtomicReference<String> result = new AtomicReference<>(), queued = new AtomicReference<>(), registration = new AtomicReference<>();
                    Thread failing = new Thread(() -> result.set(core.requestControl("{\"action\":\"inspect\",\"client\":\"client\",\"key\":\"source\"}")));
                    failing.start();check(waitPoint(), "fault did not reach locked region");
                    Thread other = new Thread(() -> queued.set(core.requestControl("{\"action\":\"ready\",\"client\":\"client\"}")));
                    Thread registering = new Thread(() -> registration.set(core.requestControl("{\"action\":\"registerConfigInput\",\"configInput\":{\"inputId\":\""+"a".repeat(64)+"\"}}")));
                    other.start();Thread.sleep(50);check(other.isAlive(), "ready did not wait for owned lock");
                    registering.start();Thread.sleep(50);check(registering.isAlive(), "registration did not wait for owned lock");
                    continuePoint();joined(failing);joined(other);joined(registering);
                    check(result.get().contains("request_restart_required") && queued.get().contains("request_restart_required"), "queued qualification escaped veto");
                    check(registration.get().contains("request_restart_required"), "queued registration reported success after fault");
                } else {
                    check(core.requestControl("{\"action\":\"inspect\",\"client\":\"client\",\"key\":\"source\"}").contains("request_restart_required"), "control reported success");
                }
                check(core.requestControl("{\"action\":\"attach\"}").contains("request_restart_required"), "fault reset by attach");
                if (scenario.startsWith("writer-")) {
                    check(snapshot().contains("\"writers\":1"), "abandoned real writer");
                    check(core.requestControl("{\"action\":\"complete\",\"client\":\"client\",\"id\":\"writer\"}").contains("request_partial_commit"), "completion failed to report damaged state");
                    check(snapshot().contains("\"writers\":0"), "completion was blocked");
                    check(snapshot().contains("\"recoveryMarker\":true"), "completion erased durable recovery barrier");
                    check(core.requestControl("{\"action\":\"ready\"}").contains("request_restart_required"), "complete cleared fault");
                }
                check(!core.stopTunRequest("other",2), "old cleanup touched unrelated owner");
                check(core.stopTunRequest("service",1), "identity-owned cleanup blocked");
            }
            core.setRequestSocketListener(null);
            String state = snapshot();
            for (String name : new String[]{"registry","selection","checkpoint","socket","tun","handlerLock"}) {
                check(state.contains("\""+name+"\":true"), "retained "+name+": "+state);
            }
            check(state.contains("\"handler\":false"), "cleanup retained TUN");
            String counts = stats();
            check(counts.contains("\"liveRefs\":1") && counts.contains("\"liveInputs\":0") && counts.contains("\"liveOutputs\":0") && counts.contains("\"duplicates\":0"), "ownership: "+counts);
            System.out.println("PASS "+scenario+" "+state+" "+counts);
        } finally { removeHome(); }
    }
}
