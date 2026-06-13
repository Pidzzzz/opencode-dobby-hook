#!/bin/bash

set -e

echo "=== Building cocos2djs Dobby Hook ==="

ANDROID_NDK=${ANDROID_NDK_HOME:-$NDK}
if [ -z "$ANDROID_NDK" ]; then
    echo "Error: ANDROID_NDK_HOME or NDK not set"
    echo "Usage: export ANDROID_NDK_HOME=/path/to/android-ndk"
    exit 1
fi

DOBBY_DIR="$(pwd)/dobby"
if [ ! -d "$DOBBY_DIR" ]; then
    echo "Cloning Dobby..."
    git clone https://github.com/jmpews/Dobby.git --depth=1
fi

echo "Building for arm64-v8a..."
mkdir -p build/arm64-v8a
cd build/arm64-v8a
cmake -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK/build/cmake/android.toolchain.cmake \
      -DANDROID_ABI=arm64-v8a \
      -DANDROID_PLATFORM=android-21 \
      -DDOBBY_SOURCE_DIR=$DOBBY_DIR \
      ../..
make -j$(nproc)
cd ../..

echo "Building for armeabi-v7a..."
mkdir -p build/armeabi-v7a
cd build/armeabi-v7a
cmake -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK/build/cmake/android.toolchain.cmake \
      -DANDROID_ABI=armeabi-v7a \
      -DANDROID_PLATFORM=android-21 \
      -DDOBBY_SOURCE_DIR=$DOBBY_DIR \
      ../..
make -j$(nproc)
cd ../..

echo "=== Build complete ==="
echo "Output:"
echo "  build/arm64-v8a/libcocos2djs_hook.so"
echo "  build/armeabi-v7a/libcocos2djs_hook.so"
