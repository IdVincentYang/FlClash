#include <jni.h>
#include <cstdlib>
#include <string>
#include <mutex>
#include <unordered_set>
#include "libclash.h"
#include "jni_helper.h"

static std::mutex counters_mu;
static std::unordered_set<void *> refs, inputs, outputs;
static int duplicates, refs_acquired, refs_released, inputs_acquired, inputs_released, outputs_acquired, outputs_released;

extern "C" jobject r09_new_global(JNIEnv *env, jobject value) {
    auto result = env->NewGlobalRef(value);
    std::lock_guard<std::mutex> lock(counters_mu);
    if (!refs.insert(result).second) duplicates++;
    refs_acquired++;
    return result;
}
extern "C" void r09_delete_global(void *value) {
    std::lock_guard<std::mutex> lock(counters_mu);
    if (refs.erase(value) != 1) duplicates++;
    refs_released++;
}
extern "C" void r09_input(void *value) {
    std::lock_guard<std::mutex> lock(counters_mu);
    if (!inputs.insert(value).second) duplicates++;
    inputs_acquired++;
}
extern "C" void r09_free_input(void *value) {
    std::lock_guard<std::mutex> lock(counters_mu);
    if (inputs.erase(value) != 1) duplicates++;
    inputs_released++;
}
extern "C" void r09_output(void *value) {
    std::lock_guard<std::mutex> lock(counters_mu);
    if (!outputs.insert(value).second) duplicates++;
    outputs_acquired++;
}
extern "C" void r09_free_output(void *value) {
    std::lock_guard<std::mutex> lock(counters_mu);
    if (outputs.erase(value) != 1) duplicates++;
    outputs_released++;
}

extern "C" JNIEXPORT void JNICALL Java_com_follow_clash_core_R09Fixture_setup(JNIEnv *env, jclass, jobject callback, jstring scenario) {
    r09Configure(new_global(callback), get_string(scenario));
}
extern "C" JNIEXPORT jstring JNICALL Java_com_follow_clash_core_R09Fixture_snapshot(JNIEnv *env, jclass) {
    auto data = r09Snapshot(); auto result = new_string(data);free(data);return result;
}
extern "C" JNIEXPORT jboolean JNICALL Java_com_follow_clash_core_R09Fixture_waitPoint(JNIEnv *, jclass) { return r09Wait(); }
extern "C" JNIEXPORT void JNICALL Java_com_follow_clash_core_R09Fixture_arm(JNIEnv *, jclass) { r09Arm(); }
extern "C" JNIEXPORT void JNICALL Java_com_follow_clash_core_R09Fixture_continuePoint(JNIEnv *, jclass) { r09Continue(); }
extern "C" JNIEXPORT jboolean JNICALL Java_com_follow_clash_core_R09Fixture_socket(JNIEnv *, jclass) { return r09Socket(); }
extern "C" JNIEXPORT void JNICALL Java_com_follow_clash_core_R09Fixture_removeHome(JNIEnv *, jclass) { r09RemoveHome(); }
extern "C" JNIEXPORT jstring JNICALL Java_com_follow_clash_core_R09Fixture_stats(JNIEnv *env, jclass) {
    std::lock_guard<std::mutex> lock(counters_mu);
    auto data = std::string("{\"liveRefs\":")+std::to_string(refs.size())+",\"liveInputs\":"+std::to_string(inputs.size())+",\"liveOutputs\":"+std::to_string(outputs.size())+",\"duplicates\":"+std::to_string(duplicates)+",\"refsAcquired\":"+std::to_string(refs_acquired)+",\"refsReleased\":"+std::to_string(refs_released)+",\"inputsAcquired\":"+std::to_string(inputs_acquired)+",\"inputsReleased\":"+std::to_string(inputs_released)+",\"outputsAcquired\":"+std::to_string(outputs_acquired)+",\"outputsReleased\":"+std::to_string(outputs_released)+"}";
    return env->NewStringUTF(data.c_str());
}
