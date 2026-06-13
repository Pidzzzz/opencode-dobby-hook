# cocos2djs Dobby Hook

A Dobby-based native hook for Android Cocos2d-JS games. Hooks into `libcocos2djs.so` to capture:

- **XXTEA encryption key** via `jsb_set_xxtea_key`
- **JavaScript files** via `evalString`
- **Decrypted game scripts** via `xxtea_decrypt`

## Build

### GitHub Actions (automatic)

Push to `main` branch - the CI workflow builds both `arm64-v8a` and `armeabi-v7a` and uploads artifacts.

### Local build

Requires Android NDK r21+.

```bash
git clone --recursive https://github.com/YOUR_USER/opencode-dobby-hook.git
cd opencode-dobby-hook
export ANDROID_NDK_HOME=/path/to/android-ndk
./build.sh
```

## Usage

1. Push `libcocos2djs_hook.so` to device:
```
adb push build/arm64-v8a/libcocos2djs_hook.so /data/local/tmp/
```

2. Inject with `LD_PRELOAD`:
```
adb shell
su
export LD_PRELOAD=/data/local/tmp/libcocos2djs_hook.so
am start -n com.gomugame.x7sy/your.main.activity
```

3. Check logs:
```
adb logcat -s cocos2djs_hook
```

4. Retrieve dumps:
```
adb pull /sdcard/cocos2js_dump/
```
