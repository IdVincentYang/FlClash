"""Run R09 against production JNI/Go exports on macOS; no Android device or network."""

import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument("output", type=Path)
parser.add_argument("--baseline", help="Git revision for the unprotected before comparison")
args = parser.parse_args()
out = args.output.resolve()
out.mkdir(parents=True, exist_ok=False)
env = os.environ.copy()
jdk = Path(subprocess.check_output(["/usr/libexec/java_home", "-v", "17"], text=True).strip())
env["JAVA_HOME"] = str(jdk)
env["CGO_ENABLED"] = "1"
env["GOPROXY"] = "off"
env["GOSUMDB"] = "off"
overlay = {}
sources = {}
commands = []
build_root = ROOT
baseline_files = {}

if args.baseline:
    args.baseline = subprocess.check_output(
        ["git", "rev-parse", "--verify", "--end-of-options", args.baseline+"^{commit}"], cwd=ROOT, text=True).strip()
    build_root = out / "baseline"
    build_root.mkdir()
    archive = subprocess.check_output(["git", "archive", "--format=tar", args.baseline, "core"], cwd=ROOT)
    with tarfile.open(fileobj=io.BytesIO(archive)) as tree:
        for member in tree:
            name = Path(member.name)
            assert not name.is_absolute() and ".." not in name.parts
            if not member.isfile():
                continue
            target = build_root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(tree.extractfile(member).read())
            baseline_files[str(name)] = hashlib.sha256(target.read_bytes()).hexdigest()
    link = subprocess.check_output(["git", "ls-tree", args.baseline, "core/Clash.Meta"], cwd=ROOT, text=True).split()
    assert link[0] == "160000"
    carrier = ROOT / "core/Clash.Meta"
    assert subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=carrier, text=True).strip() == link[2], "Baseline requires its matching Core checkout"
    assert not subprocess.check_output(["git", "status", "--porcelain"], cwd=carrier, text=True).strip(), "Core checkout must be clean"
    (build_root / "core/Clash.Meta").symlink_to(carrier, target_is_directory=True)
    (out / "baseline-source.json").write_text(json.dumps({"revision":args.baseline,"coreGitlink":link[2],"files":baseline_files},indent=2)+"\n")


def read(name):
    if args.baseline:
        if name.startswith("core/"):
            return (build_root / name).read_text()
        return subprocess.check_output(["git", "show", f"{args.baseline}:{name}"], cwd=ROOT).decode()
    return (ROOT / name).read_text()


def save(name, text):
    target = out / "overlay" / name
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(text)
    overlay[str(build_root / name)] = str(target)
    return target


def replace_once(text, old, new):
    assert text.count(old) == 1, (old, text.count(old))
    return text.replace(old, new, 1)


def in_function(text, marker, change):
    start = text.index(marker)
    end = text.find("\nfunc ", start + len(marker))
    if end < 0:
        end = len(text)
    return text[:start] + change(text[start:end]) + text[end:]


def run(name, command, cwd=ROOT):
    with (out / f"{name}.log").open("w") as log:
        result = subprocess.run(command, cwd=cwd, env=env, stdout=log, stderr=subprocess.STDOUT)
    commands.append({"name":name,"command":command,"cwd":str(cwd),"exitCode":result.returncode})
    (out / "commands.json").write_text(json.dumps(commands, indent=2)+"\n")
    print(f"{name}: {result.returncode}", flush=True)
    if result.returncode:
        print((out / f"{name}.log").read_text()[-8000:])
        raise SystemExit(result.returncode)


for name in ["core/lib.go", "core/bride.go", "core/bride.c", "core/tun/tun.go"]:
    save(name, replace_once(read(name), "//go:build android && cgo", "//go:build r09_jni_fixture && cgo"))
for name in ["core/main.go", "core/server.go"]:
    save(name, replace_once(read(name), "//go:build !(android && cgo)", "//go:build !cgo"))
save("core/platform/r09_fixture.go", """//go:build r09_jni_fixture
package platform
import "net"
func ShouldBlockConnection() bool { return false }
func QuerySocketUidFromProcFs(net.Addr, net.Addr) int { return -1 }
""")

native = Path(overlay[str(build_root / "core/lib.go")]).read_text()
native = replace_once(native, '"github.com/metacubex/mihomo/dns"', '_ "github.com/metacubex/mihomo/dns"')
native = replace_once(native, "dns.UpdateSystemDNS(addr)", "r09UpdateSystemDNS(addr)")
native = replace_once(native, "dns.FlushCacheWithDefaultResolver()", "r09FlushDefaultResolver()")
native = in_function(native, "func requestControl(", lambda s: replace_once(s, "\treturn C.CString(handleRequestControl(", '\tr09Point("control-entry")\n\treturn C.CString(handleRequestControl('))
native = in_function(native, "func setRequestSocketListener(", lambda s: replace_once(s,
    "\tlock := requestLockScope" if not args.baseline else "\trequestSocketMu.Lock()",
    '\tr09Point("callback-entry")\n' + ("\tlock := requestLockScope" if not args.baseline else "\trequestSocketMu.Lock()")))
if args.baseline:
    native = in_function(native, "func setRequestSocketListener(", lambda s: replace_once(s, "\trequestSocketMu.Lock()", '\trequestSocketMu.Lock()\n\tr09Point("callback-locked")'))
    native = in_function(native, "func setRequestSocketListener(", lambda s: replace_once(s, "\trequestSocketCallback = callback", '\trequestSocketCallback = callback\n\tr09Point("callback-published")'))
    native = in_function(native, "func setRequestSocketListener(", lambda s: replace_once(s, "\t\treleaseObject(previous)", '\t\treleaseObject(previous)\n\t\tr09Point("callback-released")'))
else:
    native = in_function(native, "func setRequestSocketListener(", lambda s: replace_once(s, "\t}()\n\tif previous != nil", '\t}()\n\tr09Point("callback-locked")\n\tif previous != nil'))
    native = in_function(native, "func setRequestSocketListener(", lambda s: replace_once(s, "\t\tprevious = nil", '\t\tprevious = nil\n\t\tr09Point("callback-released")'))
    native = in_function(native, "func setRequestSocketListener(", lambda s: replace_once(s, "\tpublished = true", '\tpublished = true\n\tr09Point("callback-published")'))
identity = "tunHandler" if args.baseline else "handler"
native = in_function(native, "func setTunRequestIdentity(", lambda s: replace_once(s, f"\t{identity}.serviceID = identity", f'\tr09Point("identity-locked")\n\t{identity}.serviceID = identity\n\tr09Point("identity-partial")'))
native = in_function(native, "func setTunRequestIdentity(", lambda s: replace_once(s, f"\t{identity}.protectGeneration = uint64(generation)", f'\t{identity}.protectGeneration = uint64(generation)\n\tr09Point("identity-full")'))
close_marker = "func (th *TunHandler) clear()" if args.baseline else "func (th *TunHandler) closeRequest()"
native = in_function(native, close_marker, lambda s: replace_once(s, "th.listener.Close()" if args.baseline else "listener.Close()", "r09Close(th.listener)" if args.baseline else "r09Close(listener)"))
if args.baseline:
    native = in_function(native, "func (th *TunHandler) close()", lambda s: replace_once(s, "\tdefer th.mu.Unlock()", '\tdefer th.mu.Unlock()\n\tr09Point("stop-locked")'))
else:
    native = in_function(native, close_marker, lambda s: replace_once(s, "\tlock.Lock()\n\tth.removeHook()", '\tlock.Lock()\n\tr09Point("stop-locked")\n\tth.removeHook()'))
save("core/lib.go", native)
request = read("core/app_requests.go")
request = in_function(request, "func (r *appRequestRegistry) inspect(", lambda s: replace_once(s, "\t\tcommits := len(r.commits)", '\t\tr09Point("control-locked")\n\t\tcommits := len(r.commits)'))
save("core/app_requests.go", request)
save("core/request_versions.go", replace_once(read("core/request_versions.go"), "\tv.highWater += 2", '\tv.highWater += 2\n\tr09Point("control-mutated")'))
fixture = (HERE / "fixture.go").read_text()
if args.baseline:
    fixture += "\nvar requestNativeFault atomic.Bool\n"
save("core/r09_fixture.go", fixture)
(out / "go-overlay.json").write_text(json.dumps({"Replace": overlay}, indent=2))
production = list((build_root / "core").glob("*.go")) + list((build_root / "core/platform").glob("*.go")) + list((build_root / "core/tun").glob("*.go"))
production += [build_root / "core/go.mod", build_root / "core/go.sum", build_root / "core/bride.c", build_root / "core/bride.h"]
binding = {"baseline":args.baseline,"coreGitlink":subprocess.check_output(["git","ls-tree",args.baseline or "HEAD","core/Clash.Meta"],cwd=ROOT,text=True).strip(),"effectiveFiles":{str(p.relative_to(build_root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in production if p.is_file() and not p.name.endswith("_test.go")},"jniFiles":{name:hashlib.sha256(read(name).encode()).hexdigest() for name in ["android/core/src/main/cpp/core.cpp","android/core/src/main/cpp/jni_helper.cpp","android/core/src/main/cpp/jni_helper.h"]}}
(out / "production-source.json").write_text(json.dumps(binding,indent=2)+"\n")
run("go-build", ["go", "build", "-overlay", str(out / "go-overlay.json"), "-tags=r09_jni_fixture,no_zerotier", "-buildmode=c-shared", "-o", str(out / "libclash.dylib"), "."], build_root / "core")

cpp_dir = out / "cpp"
cpp_dir.mkdir()
header = read("android/core/src/main/cpp/jni_helper.h")
header = replace_once(header, "#define new_global(obj) env->NewGlobalRef(obj)", """extern "C" jobject r09_new_global(JNIEnv *, jobject);
extern "C" void r09_delete_global(void *);
extern "C" void r09_input(void *);
extern "C" void r09_free_input(void *);
extern "C" void r09_output(void *);
extern "C" void r09_free_output(void *);
#define new_global(obj) r09_new_global(env, obj)""")
(cpp_dir / "jni_helper.h").write_text(header)
helper = read("android/core/src/main/cpp/jni_helper.cpp")
helper = replace_once(helper, "AttachCurrentThreadAsDaemon(&jni->env, nullptr)", "AttachCurrentThreadAsDaemon(reinterpret_cast<void **>(&jni->env), nullptr)")
helper = replace_once(helper, "    content[length] = 0;", "    r09_input(content);\n    content[length] = 0;")
helper = replace_once(helper, "    free(*value);", "    r09_free_output(*value);\n    free(*value);")
(cpp_dir / "jni_helper.cpp").write_text(helper)
cpp = read("android/core/src/main/cpp/core.cpp")
cpp = replace_once(cpp, "    del_global(static_cast<jobject>(obj));", "    r09_delete_global(obj);\n    del_global(static_cast<jobject>(obj));")
cpp = replace_once(cpp, "static void free_string_impl(char *str) {\n    free(str);", "static void free_string_impl(char *str) {\n    r09_free_input(str);\n    free(str);")
cpp = replace_once(cpp, "    scoped_string response = requestControl(get_string(data));", "    scoped_string response = requestControl(get_string(data));\n    r09_output(response);")
(cpp_dir / "core.cpp").write_text(cpp)
run("jni-build", ["clang++", "-std=c++17", "-fno-exceptions", "-fno-rtti", "-dynamiclib", "-I"+str(jdk / "include"), "-I"+str(jdk / "include/darwin"), "-I"+str(cpp_dir), "-I"+str(out), "-I"+str(build_root / "core"), str(cpp_dir / "core.cpp"), str(cpp_dir / "jni_helper.cpp"), str(HERE / "fixture.cpp"), "-L"+str(out), "-lclash", "-Wl,-rpath,@loader_path", "-o", str(out / "libcore.dylib")])
classes = out / "classes"
classes.mkdir()
production_classes = ROOT / "build/core/tmp/kotlin-classes/debug/com/follow/clash/core"
for name in ["Core", "Core$startTun$1", "Core$invokeMethod$1", "Core$updateEventListener$1", "TunInterface", "InvokeInterface", "RequestSocketInterface"]:
    source = production_classes / (name+".class")
    if source.exists():
        target = classes / "com/follow/clash/core" / source.name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
run("java-build", [str(jdk / "bin/javac"), "-cp", str(classes), "-d", str(classes), str(HERE / "R09Fixture.java")])
cases = ["healthy", "foreign", "reader", "control-entry", "control-nil-map", "control-locked", "writer-control-locked", "control-mutated", "callback-entry", "callback-locked", "callback-released", "callback-published", "identity-locked", "identity-partial", "identity-full", "stop-locked", "stop-beforeclose", "stop-afterclose", "stop-error"]
if args.baseline:
    cases = ["control-nil-map", "callback-locked", "identity-partial", "stop-beforeclose"]
results = []
for case in cases:
    command = [str(jdk / "bin/java"), "-Xcheck:jni", "-Djava.library.path="+str(out), "-cp", str(classes), "com.follow.clash.core.R09Fixture", case]
    case_env = env.copy()
    case_home = out / (case+"-home")
    case_env["FLCLASH_R09_HOME"] = str(case_home)
    with (out / (case+".log")).open("w") as log:
        result = subprocess.run(command, cwd=out, env=case_env, stdout=log, stderr=subprocess.STDOUT, timeout=20)
    shutil.rmtree(case_home, ignore_errors=True)
    text = (out / (case+".log")).read_text()
    ok = (result.returncode != 0 and "panic:" in text) if args.baseline else result.returncode == 0 and "PASS "+case in text
    results.append({"case":case,"exitCode":result.returncode,"expected":ok})
    print(case, result.returncode, ok, flush=True)
    if not ok:
        print(text[-8000:])
        break
for folder in [out / "overlay", cpp_dir, classes]:
    for path in sorted(folder.rglob("*")):
        if path.is_file(): sources[str(path.relative_to(out))] = hashlib.sha256(path.read_bytes()).hexdigest()
for path in HERE.iterdir():
    if path.is_file(): sources[str(path.relative_to(ROOT))] = hashlib.sha256(path.read_bytes()).hexdigest()
(out / "results.json").write_text(json.dumps({"baseline":args.baseline,"results":results,"files":sources,"limits":["host JVM, not ART", "Android selectors replaced", "TUN Close and UID/fd-pressure/DNS-update system leaves replaced", "JDK AttachCurrentThreadAsDaemon signature cast", "Core classes compiled from actual Kotlin declarations; no copied JNI boundary"]}, indent=2)+"\n")
sys.exit(0 if all(x["expected"] for x in results) and len(results)==len(cases) else 1)
