#include <dlfcn.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <android/log.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <string>

#include "dobby.h"

#define LOG_TAG "cocos2djs_hook"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

static char xxtea_key[64] = {0};
static int xxtea_key_len = 0;
static int dump_count = 0;
static int is_hooked = 0;

void *(*orig_evalString)(void *ctx, const char *script, int script_len, const char *filename);
void *(*orig_xxtea_decrypt)(const unsigned char *data, int data_len, const unsigned char *key, int key_len, int *out_len);

static void (*orig_jsb_set_xxtea_key_std)(const std::string &key);

static void ensure_dump_dir() {
    mkdir("/sdcard/cocos2djs_dump", 0777);
}

static void dump_to_file(const char *filename, const char *data, int len) {
    ensure_dump_dir();
    char path[256];
    if (filename && strlen(filename) > 0) {
        const char *fname = strrchr(filename, '/');
        fname = fname ? fname + 1 : filename;
        snprintf(path, sizeof(path), "/sdcard/cocos2js_dump/%s", fname);
    } else {
        snprintf(path, sizeof(path), "/sdcard/cocos2js_dump/script_%d.js", dump_count++);
    }
    FILE *f = fopen(path, "wb");
    if (f) {
        fwrite(data, 1, len, f);
        fclose(f);
        LOGI("Dumped: %s (%d bytes)", path, len);
    } else {
        LOGE("Failed to write: %s", path);
    }
}

void *fake_evalString(void *ctx, const char *script, int script_len, const char *filename) {
    LOGI("evalString - file: %s, len: %d", filename ? filename : "null", script_len);
    if (script && script_len > 0) {
        dump_to_file(filename, script, script_len);
    }
    return orig_evalString(ctx, script, script_len, filename);
}

void fake_jsb_set_xxtea_key_std(const std::string &key) {
    xxtea_key_len = key.length();
    if (xxtea_key_len > 0 && xxtea_key_len < (int)sizeof(xxtea_key)) {
        memcpy(xxtea_key, key.data(), xxtea_key_len);
        LOGI("Captured XXTEA key (%d bytes)", xxtea_key_len);

        char hex[512] = {0};
        for (int i = 0; i < xxtea_key_len && i < 64; i++) {
            sprintf(hex + i * 2, "%02x", (unsigned char)xxtea_key[i]);
        }
        LOGI("Key hex: %s", hex);

        FILE *f = fopen("/sdcard/cocos2js_dump/xxtea_key.txt", "wb");
        if (f) {
            fwrite(xxtea_key, 1, xxtea_key_len, f);
            fclose(f);
        }
        LOGI("Key saved as text: %.*s", xxtea_key_len, xxtea_key);
    }
    orig_jsb_set_xxtea_key_std(key);
}

static void *xxtea_decrypt_addr = NULL;
static char *xxtea_key_ptr = NULL;
static int *xxtea_key_len_ptr = NULL;

void *fake_xxtea_decrypt(const unsigned char *data, int data_len, const unsigned char *key, int key_len, int *out_len) {
    void *result = orig_xxtea_decrypt(data, data_len, key, key_len, out_len);
    if (result && out_len && *out_len > 0 && *out_len < 1024 * 1024) {
        LOGI("xxtea_decrypt: %d -> %d bytes (key: %.*s)", data_len, *out_len, key_len, key);
        dump_to_file("xxtea_decrypted.bin", (const char *)result, *out_len);
    }
    return result;
}

static void *try_dlsym(void *handle, const char **names, int count) {
    for (int i = 0; i < count; i++) {
        void *addr = dlsym(handle, names[i]);
        if (addr) {
            LOGI("Found symbol: %s at %p", names[i], addr);
            return addr;
        }
    }
    return NULL;
}

static void hook_functions() {
    if (is_hooked) return;
    is_hooked = 1;

    void *handle = dlopen("libcocos2djs.so", RTLD_LAZY | RTLD_LOCAL);
    if (!handle) {
        LOGE("Failed to dlopen libcocos2djs.so: %s", dlerror());
        return;
    }

    const char *eval_names[] = {
        "evalString",
        "_Z10evalStringP7JSScriptPKciS2_",
    };
    void *eval_addr = try_dlsym(handle, eval_names, 2);
    if (eval_addr) {
        DobbyHook(eval_addr, (void *)fake_evalString, (void **)&orig_evalString);
        LOGI("Hooked evalString");
    } else {
        LOGE("evalString not found");
    }

    const char *key_names[] = {
        "_Z17jsb_set_xxtea_keyRKNSt6__ndk112basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEEE",
        "jsb_set_xxtea_key",
    };
    void *key_addr = try_dlsym(handle, key_names, 2);
    if (key_addr) {
        DobbyHook(key_addr, (void *)fake_jsb_set_xxtea_key_std, (void **)&orig_jsb_set_xxtea_key_std);
        LOGI("Hooked jsb_set_xxtea_key");
    } else {
        LOGE("jsb_set_xxtea_key not found");
    }

    const char *xxtea_names[] = {
        "xxtea_decrypt",
        "_Z13xxtea_decryptPKhiS0_iPi",
    };
    void *xxtea_addr = try_dlsym(handle, xxtea_names, 2);
    if (xxtea_addr) {
        DobbyHook(xxtea_addr, (void *)fake_xxtea_decrypt, (void **)&orig_xxtea_decrypt);
        LOGI("Hooked xxtea_decrypt");
    } else {
        LOGE("xxtea_decrypt not found");
    }

    dlclose(handle);
}

__attribute__((constructor))
void init() {
    LOGI("cocos2djs Dobby hook loaded");
    ensure_dump_dir();

    for (int i = 0; i < 120; i++) {
        void *handle = dlopen("libcocos2djs.so", RTLD_NOLOAD);
        if (handle) {
            dlclose(handle);
            LOGI("libcocos2djs.so loaded, hooking...");
            hook_functions();
            return;
        }
        usleep(500000);
    }
    LOGE("Timed out waiting for libcocos2djs.so");
}
