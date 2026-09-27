#include <jni.h>
#include <cwctype>

extern "C" {

JNIEXPORT jstring JNICALL
Java_com_hsin_HsinNative_nativeLastJsonLine(JNIEnv *env, jclass /*cls*/, jstring output) {
    if (!output) return nullptr;
    const jchar *chs = env->GetStringChars(output, nullptr);
    if (!chs) return nullptr;
    jsize n = env->GetStringLength(output);

    jsize idx = n - 1;
    while (idx >= 0) {
        // Trim trailing whitespace from the segment ending at idx
        while (idx >= 0 && (chs[idx] == ' ' || chs[idx] == '\t' || chs[idx] == '\r' || chs[idx] == '\n')) {
            --idx;
        }
        if (idx < 0) break;
        jsize line_end = idx;
        // Find start of line (before \r or \n)
        while (idx >= 0 && chs[idx] != '\n' && chs[idx] != '\r') {
            --idx;
        }
        jsize line_start = idx + 1;
        // Trim leading whitespace of this line
        jsize s = line_start;
        while (s <= line_end && (chs[s] == ' ' || chs[s] == '\t' || chs[s] == '\r' || chs[s] == '\n')) {
            ++s;
        }
        jsize e = line_end;
        while (e >= s && (chs[e] == ' ' || chs[e] == '\t' || chs[e] == '\r' || chs[e] == '\n')) {
            --e;
        }
        if (e >= s && chs[s] == '{') {
            jstring res = env->NewString(chs + s, (jsize)(e - s + 1));
            env->ReleaseStringChars(output, chs);
            return res;
        }
        // Move to previous line
        idx = idx - 1; // skip newline char(s) already passed; loop will trim again
    }

    env->ReleaseStringChars(output, chs);
    return nullptr;
}

JNIEXPORT jstring JNICALL
Java_com_hsin_HsinNative_nativeSanitizeNode(JNIEnv *env, jclass /*cls*/, jstring node) {
    if (!node) {
        return env->NewStringUTF("");
    }
    const jchar *chs = env->GetStringChars(node, nullptr);
    if (!chs) return env->NewStringUTF("");
    jsize n = env->GetStringLength(node);

    jchar out[40];
    jsize out_len = 0;
    for (jsize i = 0; i < n && out_len < 40; ++i) {
        jchar c = chs[i];
        if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9')) {
            out[out_len++] = c;
        } else {
            out[out_len++] = '_';
        }
    }
    env->ReleaseStringChars(node, chs);
    return env->NewString(out, out_len);
}

} // extern "C"
