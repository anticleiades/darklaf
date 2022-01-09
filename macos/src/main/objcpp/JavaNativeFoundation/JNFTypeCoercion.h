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
 *
 * --
 *
 * Type Coercion system that translates between Java VM objects and Objective-C Foundation objects.
 *
 * Darklaf_JNFTypeCoercions are registered into Darklaf_JNFTypeCoercers, which can be chained to other
 * Darklaf_JNFTypeCoercers using -deriveCoercer or -initWithParent. If the set of Coercions
 * in a Coercer aren't capable of converting an object, the Coercer will delegate up to
 * it's parent.
 *
 * Coercions are registered by Objective-C class and Java class name. If an object is an
 * instance of the registered class name, the coercion will be invoked. Default
 * implementations for several basic types are provided by Darklaf_JNFDefaultCoercions, and can
 * be installed in any order. More specific coercions should be placed farther down
 * a coercer chain, and more generic coercions should be placed higher. A Coercer can be
 * initialized with a basic Coercion that may want to handle "all cases", like calling
 * Object.toString() and -describe on all objects passed to it.
 *
 * Coercions are passed the Coercion-object that was originally invoked on the
 * target object. This permits the lowest level Coercion to be used for subsequent
 * object translations for composite objects. The provided List, Map, and Set Coercions
 * only handle object hierarchies, and will infinitely recurse if confronted with a
 * cycle in the object graph.
 *
 * Null and nil are both perfectly valid return types for Coercions, and do not indicate
 * a failure to coerce an object. Coercers are not thread safe.
 */

#import <Foundation/Foundation.h>
#import "JNFJNI.h"

__BEGIN_DECLS

@class Darklaf_JNFTypeCoercion;

Darklaf_JNF_EXPORT
@protocol Darklaf_JNFTypeCoercion

- (jobject) coerceNSObject:(id)obj withEnv:(JNIEnv *)env usingCoercer:(Darklaf_JNFTypeCoercion *)coercer;
- (id) coerceJavaObject:(jobject)obj withEnv:(JNIEnv *)env usingCoercer:(Darklaf_JNFTypeCoercion *)coercer;

@end


Darklaf_JNF_EXPORT
@interface Darklaf_JNFTypeCoercer : NSObject <Darklaf_JNFTypeCoercion>

- (id) init;
- (id) initWithParent:(NSObject <Darklaf_JNFTypeCoercion> *)parentIn;
- (Darklaf_JNFTypeCoercer *) deriveCoercer;
- (void) addCoercion:(NSObject <Darklaf_JNFTypeCoercion> *)coercion forNSClass:(Class)nsClass javaClass:(NSString *)javaClassName;

- (jobject) coerceNSObject:(id)obj withEnv:(JNIEnv *)env;
- (id) coerceJavaObject:(jobject)obj withEnv:(JNIEnv *)env;

@end


Darklaf_JNF_EXPORT
@interface Darklaf_JNFDefaultCoercions : NSObject { }

+ (void) addStringCoercionTo:(Darklaf_JNFTypeCoercer *)coercer;
+ (void) addNumberCoercionTo:(Darklaf_JNFTypeCoercer *)coercer;
+ (void) addDateCoercionTo:(Darklaf_JNFTypeCoercer *)coercer;
+ (void) addListCoercionTo:(Darklaf_JNFTypeCoercer *)coercer;
+ (void) addMapCoercionTo:(Darklaf_JNFTypeCoercer *)coercer;
+ (void) addSetCoercionTo:(Darklaf_JNFTypeCoercer *)coercer;

+ (Darklaf_JNFTypeCoercer *) defaultCoercer; // returns autoreleased copy, not shared, not thread safe

@end

__END_DECLS
