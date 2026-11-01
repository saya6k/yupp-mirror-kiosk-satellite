/* The ALOG macros the shim uses, on the NDK's liblog. */
#pragma once
#include <android/log.h>
#ifndef LOG_TAG
#define LOG_TAG NULL
#endif
#define ALOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define ALOGW(...) __android_log_print(ANDROID_LOG_WARN, LOG_TAG, __VA_ARGS__)
#define ALOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#define LOG_ALWAYS_FATAL(...) __android_log_assert(NULL, LOG_TAG, __VA_ARGS__)
