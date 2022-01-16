/*
 * Copyright (c) 2008-2020 Apple Inc. All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 *   1. Redistributions of source code must retain the above copyright notice,
 *      this list of conditions and the following disclaimer.
 *
 *   2. Redistributions in binary form must reproduce the above copyright
 *      notice, this list of conditions and the following disclaimer in the
 *      documentation and/or other materials provided with the distribution.
 *
 *   3. Neither the name of the copyright holder nor the names of its
 *      contributors may be used to endorse or promote products derived from
 *      this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 */

#import "JNFException.h"

#import <stdlib.h>
#import <Foundation/NSString.h>

#import "JNFObject.h"
#import "JNFString.h"
#import "JNFAssert.h"
#import "JNFThread.h"
#import "debug.h"


#define JAVA_LANG "java/lang/"
const char* kOutOfMemoryError           = JAVA_LANG "OutOfMemoryError";
const char* kClassNotFoundException     = JAVA_LANG "ClassNotFoundException";
const char* kNullPointerException       = JAVA_LANG "NullPointerException";
const char* kIllegalAccessException     = JAVA_LANG "IllegalAccessException";
const char* kIllegalArgumentException   = JAVA_LANG "IllegalArgumentException";
const char* kNoSuchFieldException       = JAVA_LANG "NoSuchFieldException";
const char* kNoSuchMethodException      = JAVA_LANG "NoSuchMethodException";
const char* kRuntimeException           = JAVA_LANG "RuntimeException";

@interface Darklaf_JNFException ()
@property (readwrite, nonatomic, assign) jthrowable javaException;
@end

@interface Darklaf_JNFException(_Darklaf_JNFPrivateExceptionLifecycle)

- (void) _setThrowable:(jthrowable)throwable withEnv:(JNIEnv *)env;
- (void) _clearThrowableWithEnv:(JNIEnv *)env;
- (void) _setThrowable:(jthrowable)throwable withNonNullEnv:(JNIEnv *)env;
- (void) _clearThrowableWithNonNullEnv:(JNIEnv *)env;

@end


@implementation Darklaf_JNFException

- initUnnamed:(JNIEnv *)env {
    Darklaf_JNF_ASSERT_COND(env);
    jthrowable throwable = env->ExceptionOccurred();
    if (throwable) return [self init:env throwable:throwable];

    return [self initWithName:@"JavaNativeException" reason:@"See Java exception" userInfo:nil];
}

+ (void)raiseUnnamedException:(JNIEnv *)env {
    Darklaf_JNF_ASSERT_COND(env);
    [[[[Darklaf_JNFException alloc] initUnnamed:env] autorelease] raise];
}

+ (void)raise:(JNIEnv *)env throwable:(jthrowable)throwable {
    Darklaf_JNF_ASSERT_COND(env);
    [[[[Darklaf_JNFException alloc] init:env throwable:throwable] autorelease] raise];
}

+ (void)raise:(JNIEnv *)env as:(const char *)javaExceptionType reason:(const char *)reasonMsg {
    Darklaf_JNF_ASSERT_COND(env);
    [[[[Darklaf_JNFException alloc] init:env as:javaExceptionType reason:reasonMsg] autorelease] raise];
}

- init:(JNIEnv *)env throwable:(jthrowable)throwable {
    [self _setThrowable:throwable withEnv:env];
    env->ExceptionClear(env);	// The exception will be rethrown in -raiseToJava

    static jclass jc_Throwable = NULL;
    if (jc_Throwable == NULL) {
        jc_Throwable = env->FindClass("java/lang/Throwable");
        jthrowable unexpected = env->ExceptionOccurred();
        if (unexpected) {
            env->ExceptionClear(env);
            return [self initWithName:@"JavaNativeException" reason:@"Internal Darklaf_JNF Error: could not find Throwable class" userInfo:nil];
        }
    }

    static jmethodID jm_Throwable_getMessage = NULL;
    if (jm_Throwable_getMessage == NULL && jc_Throwable != NULL) {
        jm_Throwable_getMessage = env->GetMethodID(jc_Throwable, "toString", "()Ljava/lang/String;");
        jthrowable unexpected = env->ExceptionOccurred();
        if (unexpected) {
            env->ExceptionClear(env);
            return [self initWithName:@"JavaNativeException" reason:@"Internal Darklaf_JNF Error: could not find Throwable.toString() method" userInfo:nil];
        }
    }

    if (jm_Throwable_getMessage == NULL) {
        return [self initWithName:@"JavaNativeException" reason:@"Internal Darklaf_JNF Error: exception occurred, unable to determine cause" userInfo:nil];
    }

    jobject msg = env->CallObjectMethod(throwable, jm_Throwable_getMessage);
    jthrowable unexpected = env->ExceptionOccurred();
    if (unexpected) {
        env->ExceptionClear(env);
        return [self initWithName:@"JavaNativeException" reason:@"Internal Darklaf_JNF Error: failed calling Throwable.toString()" userInfo:nil];
    }

    NSString *reason = Darklaf_JNFJavaToNSString(env, msg);
    env->DeleteLocalRef(msg);
    return [self initWithName:@"JavaNativeException" reason:reason userInfo:nil];
}

- init:(JNIEnv *)env as:(const char *)javaExceptionType reason:(const char *)reasonMsg {
    jclass exceptionClass = NULL;
    char *buf = NULL;

    Darklaf_JNF_ASSERT_COND(env);
    if (javaExceptionType != NULL) {
        exceptionClass = env->FindClass(javaExceptionType);
    }

    if (exceptionClass == NULL) {
        // Try to throw an AWTError exception
        static jthrowable  panicExceptionClass = NULL;
        const char*        panicExceptionName = kRuntimeException;
        if (panicExceptionClass == NULL) {
            jclass cls = env->FindClass(panicExceptionName);
            if (cls != NULL) {
                panicExceptionClass = env->NewGlobalRef(cls);
            }
        }

        exceptionClass = panicExceptionClass;
        if (javaExceptionType == NULL) {
            reasonMsg = "Missing Java exception class name while trying to throw a new Java exception";
        } else {
            // Quick and dirty thread-safe message buffer.
            buf = calloc(1, 512);
            if (buf != NULL) {
                sprintf(buf, "Unknown throwable class: %s.80", javaExceptionType);
                reasonMsg = buf;
            } else {
                reasonMsg = "Unknown throwable class, out of memory!";
            }
        }
        javaExceptionType = panicExceptionName;
    }

    // Can't throw squat if there's no class to throw
    if (exceptionClass != NULL) {
        env->ThrowNew(exceptionClass, reasonMsg);
        jthrowable ex = env->ExceptionOccurred();
        if (ex) {
            env->ExceptionClear(env);    // Exception will be rethrown in -raiseToJava
        }
        [self _setThrowable:ex withEnv:env];
    }

    if (reasonMsg == NULL) reasonMsg = "unknown";

    @try {
        return [self initWithName:[NSString stringWithUTF8String:javaExceptionType]
                           reason:[NSString stringWithUTF8String:reasonMsg]
                         userInfo:nil];
    } @finally {
        if (buf != NULL) free(buf);
    }

    return self;
}

+ (void)throwToJava:(JNIEnv *)env exception:(NSException *)exception {
    [self throwToJava:env exception:exception as:kRuntimeException];
}

+ (void)throwToJava:(JNIEnv *)env exception:(NSException *)exception as:(const char *)javaExceptionType{
    if (![exception isKindOfClass:[Darklaf_JNFException class]]) {
        exception = [[Darklaf_JNFException alloc] init:env as:javaExceptionType reason:[[NSString stringWithFormat:@"Non-Java exception raised, not handled! (Original problem: %@)", [exception reason]] UTF8String]];
        [exception autorelease];
        Darklaf_JNF_WARN("NSException not handled by native method.  Passing to Java.");
    }

    [(Darklaf_JNFException *)exception raiseToJava:env];
}

- (void)raiseToJava:(JNIEnv *)env {
    jthrowable const javaException = self.javaException;

    Darklaf_JNF_ASSERT_COND(env);
    Darklaf_JNF_ASSERT_COND(javaException != NULL);
    env->Throw(javaException);
}

- (NSString *)description {
    jthrowable const javaException = self.javaException;
    NSString *desc = [super description];
    if (!javaException) return desc;

    @try {
        Darklaf_JNFThreadContext ctx = Darklaf_JNFThreadDetachImmediately;
        JNIEnv *env = Darklaf_JNFObtainEnv(&ctx);
        if (!env) {
            NSLog(@"JavaNativeFoundation: NULL JNIEnv error occurred obtaining Java exception description");
            return desc;
        }
        env->ExceptionClear(env);
        NSString *stackTrace = Darklaf_JNFGetStackTraceAsNSString(env, javaException);
        Darklaf_JNFReleaseEnv(env, &ctx);

        return stackTrace;
    } @catch (NSException *e) {
        // we clearly blew up trying to print our own exception, so we should
        // not try to do that again, even if it looks helpful - its a trap!
        NSLog(@"JavaNativeFoundation error occurred obtaining Java exception description");
    }
    return desc;
}

- (void) _setThrowable:(jthrowable)throwable withEnv:(JNIEnv *)env {
    if (env) {
        [self _clearThrowableWithNonNullEnv:env];
        [self _setThrowable:throwable withNonNullEnv:env];
        return;
    }

    Darklaf_JNFThreadContext threadContext = Darklaf_JNFThreadDetachImmediately;
    env = Darklaf_JNFObtainEnv(&threadContext);
    if (env == NULL) return;

    [self _clearThrowableWithNonNullEnv:env];
    [self _setThrowable:throwable withEnv:env];

    Darklaf_JNFReleaseEnv(env, &threadContext);
}

- (void) _clearThrowableWithEnv:(JNIEnv *)env {
    if (env) {
        [self _clearThrowableWithNonNullEnv:env];
        return;
    }

    Darklaf_JNFThreadContext threadContext = Darklaf_JNFThreadDetachImmediately;
    env = Darklaf_JNFObtainEnv(&threadContext);
    if (env == NULL) return; // leak?

    [self _clearThrowableWithNonNullEnv:env];

    Darklaf_JNFReleaseEnv(env, &threadContext);
}

- (void) _setThrowable:(jthrowable)throwable withNonNullEnv:(JNIEnv *)env {
    if (!throwable) return;
    self.javaException = env->NewGlobalRef(throwable);
}

// delete and clear
- (void) _clearThrowableWithNonNullEnv:(JNIEnv *)env {
    jthrowable const javaException = self.javaException;
    if (!javaException) return;
    self.javaException = NULL;
    env->DeleteGlobalRef(javaException);
}

- (void) dealloc {
    [self _clearThrowableWithEnv:NULL];
    [super dealloc];
}

@end
