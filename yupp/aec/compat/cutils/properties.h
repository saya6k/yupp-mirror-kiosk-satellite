/* What the shim uses of libcutils' properties.h, for an NDK build. The
 * functions come from the platform's libcutils.so (VNDK) at run time. */
#pragma once
#include <stdbool.h>
#include <stdint.h>
#define PROPERTY_VALUE_MAX 92
#ifdef __cplusplus
extern "C" {
#endif
int property_get(const char* key, char* value, const char* default_value);
bool property_get_bool(const char* key, bool default_value);
int32_t property_get_int32(const char* key, int32_t default_value);
#ifdef __cplusplus
}
#endif
