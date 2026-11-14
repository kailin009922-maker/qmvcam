//
//  substrate.h — 最小化 CydiaSubstrate 声明（构建机无 Theos 时用）
//
#ifndef VCAM_SUBSTRATE_H
#define VCAM_SUBSTRATE_H

#include <objc/runtime.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*MSHookFunction_t)(void);

void MSHookMessageEx(Class _class, SEL sel, IMP imp, IMP *result);
void MSHookFunction(void *symbol, void *replace, void **result);
Class MSGetClass(const char *name);
void MSHookClassPair(Class a, Class b, Class meta);

#ifdef __cplusplus
}
#endif

#endif
