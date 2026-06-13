LOCAL_PATH := $(call my-dir)

include $(CLEAR_VARS)

LOCAL_MODULE := cocos2djs_hook
LOCAL_SRC_FILES := hook.cpp

LOCAL_C_INCLUDES := $(LOCAL_PATH)/../dobby/include

LOCAL_LDLIBS := -llog -ldl

LOCAL_CPPFLAGS := -std=c++11 -fvisibility=hidden -Wall

include $(BUILD_SHARED_LIBRARY)

$(call import-module, dobby)
