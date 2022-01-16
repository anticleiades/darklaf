/*
 * MIT License
 *
 * Copyright (c) 2020 Jannis Weis
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
 * associated documentation files (the "Software"), to deal in the Software without restriction,
 * including without limitation the rights to use, copy, modify, merge, publish, distribute,
 * sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all copies or
 * substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT
 * NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 * NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
 * DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */
#import "com_github_weisj_darklaf_platform_macos_JNIThemeInfoMacOS.h"
#import "JavaNativeFoundation/JavaNativeFoundation.h"
#import <AppKit/AppKit.h>

#define OBJC(jl) ((id)jlong_to_ptr(jl))

#define NSRequiresAquaSystemAppearance CFSTR("NSRequiresAquaSystemAppearance")

#define KEY_APPLE_INTERFACE_STYLE @"AppleInterfaceStyle"
#define KEY_SWITCHES_AUTOMATICALLY @"AppleInterfaceStyleSwitchesAutomatically"
#define KEY_ACCENT_COLOR @"AppleAccentColor"
#define KEY_SELECTION_COLOR @"selectedTextBackgroundColor"
#define KEY_SYSTEM_COLOR_LIST @"System"

#define EVENT_ACCENT_COLOR @"AppleColorPreferencesChangedNotification"
#define EVENT_AQUA_CHANGE @"AppleAquaColorVariantChanged"
#define EVENT_THEME_CHANGE @"AppleInterfaceThemeChangedNotification"
#define EVENT_HIGH_CONTRAST @"AXInterfaceIncreaseContrastStatusDidChange"
#define EVENT_COLOR_CHANGE NSSystemColorsDidChangeNotification

#define VALUE_DARK @"Dark"
#define VALUE_DEFAULT_ACCENT_COLOR (-2)
#define VALUE_NO_ACCENT_COLOR (-100)
#define VALUE_NO_SELECTION_COLOR (-1)

BOOL isPatched = NO;
BOOL manuallyPatched = NO;

@interface PreferenceChangeListener:NSObject {
    @public JavaVM *jvm;
    @public jobject callback;
}
@end

@implementation PreferenceChangeListener
- (id)initWithJVM:(JavaVM *)jvm_ andCallBack:(jobject)callback_ {
    self = [super init];
    self->jvm = jvm_;
    self->callback = callback_;

    NSDistributedNotificationCenter *center = [NSDistributedNotificationCenter defaultCenter];
    [self listenToKey:EVENT_ACCENT_COLOR onCenter:center];
    [self listenToKey:EVENT_AQUA_CHANGE onCenter:center];
    [self listenToKey:EVENT_THEME_CHANGE onCenter:center];
    [self listenToKey:EVENT_HIGH_CONTRAST onCenter:center];
    [self listenToKey:EVENT_COLOR_CHANGE onCenter:center];

    if(@available(macOS 10.15, *)) {
        [NSApp addObserver:self
                forKeyPath:NSStringFromSelector(@selector(effectiveAppearance))
                   options:0
                   context:nil];
    }
    return self;
}

- (void)dealloc {
    NSDistributedNotificationCenter *center = [NSDistributedNotificationCenter defaultCenter];
    [center removeObserver:self]; // Removes all registered notifications.
    if(@available(macOS 10.15, *)) {
        [NSApp removeObserver:self
                   forKeyPath:NSStringFromSelector(@selector(effectiveAppearance))];
    }
    [super dealloc];
}

- (void)listenToKey:(NSString *)key onCenter:(NSDistributedNotificationCenter *)center {
     [center addObserver:self
                selector:@selector(notificationEvent:)
                    name:key
                  object:nil];
}

- (void)runCallback {
    if (!jvm) return;
    JNIEnv *env;
    BOOL detach = NO;
    int getEnvStat = jvm->GetEnv((void **)&env, JNI_VERSION_1_6);
    if (getEnvStat == JNI_EDETACHED) {
        detach = YES;
        if (jvm->AttachCurrentThread((void **) &env, NULL) != 0) return;
    } else if (getEnvStat == JNI_EVERSION) {
        return;
    }
    jclass runnableClass = env->GetObjectClass(callback);
    jmethodID runMethodId = env->GetMethodID(runnableClass, "run", "()V");
    if (runMethodId) {
        env->CallVoidMethod(callback, runMethodId);
    }
    if (env->ExceptionCheck()) {
        env->ExceptionDescribe();
    }
    if (detach) jvm->DetachCurrentThread();
}

- (void)dispatchCallback {
    [Darklaf_JNFRunLoop performOnMainThreadWaiting:NO withBlock:^{
        [self runCallback];
    }];
}

- (void)notificationEvent:(NSNotification *)notification {
    [self dispatchCallback];
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {
    [self dispatchCallback];
}

@end

BOOL isDarkModeCatalina() {
    NSAppearance *appearance = NSApp.effectiveAppearance;
    NSAppearanceName appearanceName = [appearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua,
                                                                                      NSAppearanceNameDarkAqua]];
    return [appearanceName isEqualToString:NSAppearanceNameDarkAqua];
}

BOOL isDarkModeMojave() {
    NSString *interfaceStyle = [[NSUserDefaults standardUserDefaults] stringForKey:KEY_APPLE_INTERFACE_STYLE];
    return [VALUE_DARK caseInsensitiveCompare:interfaceStyle] == NSOrderedSame;
}

BOOL isAutoMode() {
    return [[NSUserDefaults standardUserDefaults] boolForKey:KEY_SWITCHES_AUTOMATICALLY];
}

JNIEXPORT jboolean JNICALL
Java_com_github_weisj_darklaf_platform_macos_JNIThemeInfoMacOS_isDarkThemeEnabled(JNIEnv *env, jclass obj) {
Darklaf_JNF_COCOA_ENTER(env);
    if(@available(macOS 10.15, *)) {
        if (isPatched && isAutoMode()) {
            /*
             * The newer method is more unsafe with regards to the JDK version nad the apps info.plist
             * We only use it if necessary i.e. 'Auto' mode is selected and the app bundle is correctly patched.
             * i.e. a specific value has been set in the app bundle or we have patched it manually (only jdk <=11).
             */
            return (jboolean) isDarkModeCatalina();
        }
    }
    if (@available(macOS 10.14, *)) {
        return (jboolean) isDarkModeMojave();
    } else {
        return (jboolean) NO;
    }
Darklaf_JNF_COCOA_EXIT(env);
    return NO;
}

JNIEXPORT jboolean JNICALL
Java_com_github_weisj_darklaf_platform_macos_JNIThemeInfoMacOS_isHighContrastEnabled(JNIEnv *env, jclass obj) {
Darklaf_JNF_COCOA_ENTER(env);
    return (jboolean) NSWorkspace.sharedWorkspace.accessibilityDisplayShouldIncreaseContrast;
Darklaf_JNF_COCOA_EXIT(env);
    return (jboolean) NO;
}

JNIEXPORT jint JNICALL
Java_com_github_weisj_darklaf_platform_macos_JNIThemeInfoMacOS_nativeGetAccentColor(JNIEnv *env, jclass obj) {
Darklaf_JNF_COCOA_ENTER(env);
    if (@available(macOS 10.14, *)) {
        BOOL hasAccentSet = ([[NSUserDefaults standardUserDefaults] objectForKey:KEY_ACCENT_COLOR] != nil);
        if (hasAccentSet) {
            return (jint) ([[NSUserDefaults standardUserDefaults] integerForKey:KEY_ACCENT_COLOR]);
        }
    }
    return (jint) VALUE_DEFAULT_ACCENT_COLOR;
Darklaf_JNF_COCOA_EXIT(env);
    return (jint) VALUE_NO_ACCENT_COLOR;
}

JNIEXPORT jint JNICALL
Java_com_github_weisj_darklaf_platform_macos_JNIThemeInfoMacOS_nativeGetSelectionColor(JNIEnv *env, jclass obj) {
Darklaf_JNF_COCOA_ENTER(env);
    NSColorSpace *rgbSpace = [NSColorSpace sRGBColorSpace];
    NSColor *accentColor = [[[NSColorList colorListNamed: KEY_SYSTEM_COLOR_LIST] colorWithKey:KEY_SELECTION_COLOR] colorUsingColorSpace:rgbSpace];
    // This is the same conversion as in MacOSColors for consistency.
    NSInteger r = (NSInteger) (255 * [accentColor redComponent] + 0.5);
    NSInteger g = (NSInteger) (255 * [accentColor greenComponent] + 0.5);
    NSInteger b = (NSInteger) (255 * [accentColor blueComponent] + 0.5);
    return (jint) ((255 & 0xFF) << 24) |
                    ((r & 0xFF) << 16) |
                    ((g & 0xFF) << 8)  |
                    ((b & 0xFF) << 0);
Darklaf_JNF_COCOA_EXIT(env);
    return (jint) VALUE_NO_SELECTION_COLOR;
}

JNIEXPORT jlong JNICALL
Java_com_github_weisj_darklaf_platform_macos_JNIThemeInfoMacOS_createPreferenceChangeListener(JNIEnv *env, jclass obj, jobject callback) {
Darklaf_JNF_COCOA_DURING(env); // We dont want an auto release pool.
    JavaVM *jvm;
    if (env->GetJavaVM(&jvm) == JNI_OK) {
        jobject callbackRef = env->NewGlobalRef(callback);
        PreferenceChangeListener *listener = [[PreferenceChangeListener alloc] initWithJVM:jvm andCallBack: callbackRef];
        [listener retain];
        return reinterpret_cast<jlong>(listener);
    }
    return (jlong) 0;
Darklaf_JNF_COCOA_HANDLE(env);
    return (jlong) 0;
}

JNIEXPORT void JNICALL
Java_com_github_weisj_darklaf_platform_macos_JNIThemeInfoMacOS_deletePreferenceChangeListener(JNIEnv *env, jclass obj, jlong listenerPtr) {
Darklaf_JNF_COCOA_ENTER(env);
    PreferenceChangeListener *listener = OBJC(listenerPtr);
    if (listener) {
        env->DeleteGlobalRef(listener->callback);
        [listener release];
        [listener dealloc];
    }
Darklaf_JNF_COCOA_EXIT(env);
}

JNIEXPORT void JNICALL
Java_com_github_weisj_darklaf_platform_macos_JNIThemeInfoMacOS_patchAppBundle(JNIEnv *env, jclass obj, jboolean preJava11) {
Darklaf_JNF_COCOA_ENTER(env);
    if (@available(macOS 10.15, *)) {
        NSString *name = [[NSBundle mainBundle] bundleIdentifier];

        CFStringRef bundleName = (__bridge CFStringRef)name;

        Boolean exists = false;
        Boolean value = CFPreferencesGetAppBooleanValue(NSRequiresAquaSystemAppearance, bundleName, &exists);
        isPatched = preJava11 || (value ? YES : NO);

        if (!exists) {
            // Only patch if value hasn't been explicitly set
            CFPreferencesSetAppValue(NSRequiresAquaSystemAppearance, kCFBooleanFalse, bundleName);
            CFPreferencesAppSynchronize(bundleName);
            manuallyPatched = YES;
        }
    } else {
        isPatched = NO;
    }
Darklaf_JNF_COCOA_EXIT(env);
}

JNIEXPORT void JNICALL
Java_com_github_weisj_darklaf_platform_macos_JNIThemeInfoMacOS_unpatchAppBundle(JNIEnv *env, jclass obj) {
Darklaf_JNF_COCOA_ENTER(env);
    if (!manuallyPatched) return;
    if (@available(macOS 10.15, *)) {
        NSString *name = [[NSBundle mainBundle] bundleIdentifier];
        CFStringRef bundleName = (__bridge CFStringRef)name;
        CFPreferencesSetAppValue(NSRequiresAquaSystemAppearance, nil, bundleName);
        CFPreferencesAppSynchronize(bundleName);
    }
Darklaf_JNF_COCOA_EXIT(env);
}
