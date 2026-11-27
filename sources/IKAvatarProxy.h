#import <Foundation/Foundation.h>
#import <objc/message.h>
#include <string.h>

// The selector and owner are visible in the iOS 16 device log. Reject incompatible OS signatures.
static inline BOOL IKCanResolveProxy(id proxy, SEL selector) {
    NSMethodSignature *sig = [proxy methodSignatureForSelector:selector];
    if (!sig || sig.numberOfArguments != 3 || sig.methodReturnType[0] != '@') return NO;
    const char *type = [sig getArgumentTypeAtIndex:2];
    while (*type && strchr("rnNoORV", *type)) type++;
    return strncmp(type, "^@", 2) == 0;
}

static inline id IKReadProxyImage(id proxy, SEL selector, NSError *__autoreleasing *error) {
    if (!IKCanResolveProxy(proxy, selector)) return nil;
    @try { return ((id (*)(id, SEL, NSError *__autoreleasing *))objc_msgSend)(proxy, selector, error); }
    @catch (__unused NSException *exception) {
        if (error) *error = [NSError errorWithDomain:@"IslandKitAvatar" code:1 userInfo:nil];
        return nil;
    }
}
