---
layout: post
title: Reflections over modules in java 9, part 2
date:   2017-11-27 19:30
categories: [java]
---

In last post we used unsafe to break module system, in this post I will show other ways for doing this: native code, and instrumentation.  
Last post: [**Reflections in java 9**](https://blog.gotofinal.com/java/2017/11/08/reflections-in-java-9.html)  

Native code can execute any method and access any field using JVM API without any access checks, but accessing java from native code is much slower, 
so it is good idea to cache class and method pointers.  
Like last time we will make `setAccessible0` accessible, so we don't need to call native code each time.  

First time we need to prepare our java code: 
```java
public class ReflectiveAccessModulesNative {

    static {
        // we need to load our library, that does not exist yet tho, you don't need to add .dll or .so, java will find valid file on given platform.
        System.loadLibrary("libJniReflectiveAccess");
    }

    public static void main(String[] args) throws Throwable {
        ArrayList<String> list = new ArrayList<>();
        list.add("abc");

        // this time we just need to get field, and use our native method to make it accessible
        Field elementDataField = ArrayList.class.getDeclaredField("elementData");
        Assert.assertFalse(elementDataField.canAccess(list));
        setAccessible(elementDataField, true);

        Assert.assertTrue(elementDataField.isAccessible());
        Assert.assertTrue(elementDataField.canAccess(list));

        Object[] elementData = (Object[]) elementDataField.get(list);
        Assert.assertSame("abc", elementData[0]); // NOTE: we can use ==/same, as "abc" is literal added to constant pool on compile time.
        System.out.println(Arrays.toString(elementData));
    }

    // our native method
    private static native void setAccessible(AccessibleObject accessibleObject, boolean value);
}
```
So far it will not work yet, as we didn't prepare library yet, first we need to prepare header file using `javac -h` method.  
Mine looks like that: [**com_gotofinal_blog_tricks_ReflectiveAccessModulesNative.h**](https://gist.github.com/GotoFinal/2cef981f42fc53c8581882e642a3d7e6)  

And now implementation class: `com_gotofinal_blog_tricks_ReflectiveAccessModulesNative.cpp`:
```cpp
#include "com_gotofinal_blog_tricks_ReflectiveAccessModulesNative.h"
JNIEXPORT void JNICALL Java_com_gotofinal_blog_tricks_ReflectiveAccessModulesNative_setAccessible(JNIEnv *env, jclass clazz, jobject accessibleObject, jboolean value) {
}
```
So, we need to now call that `setAccessible0` method:
```cpp
jclass cls = env->FindClass("java/lang/reflect/AccessibleObject");
```
Note that in native code we use slash (`/`) instead of dot (`.`).  
Now we need to get that method:  
```cpp
jmethodID method = env->GetMethodID(cls, "setAccessible0", "(Z)Z");
```
Note that we use internal signature here `(Z)Z`, where Z means `boolean` type, and last type is return type of method.  
And now we just need to call this method:  
```cpp
env->CallBooleanMethod(accessibleObject, cachedMethod, value);
```
And this is whole code, we like I said before, it is good idea to cache such code, so at the end we will be using this code:
```cpp
#include "com_gotofinal_blog_tricks_ReflectiveAccessModulesNative.h"

static jclass cachedClazz = nullptr;
static jmethodID cachedMethod = nullptr;

JNIEXPORT void JNICALL Java_com_gotofinal_blog_tricks_ReflectiveAccessModulesNative_setAccessible(JNIEnv *env, jclass clazz, jobject accessibleObject, jboolean value) {
    // we can also move preparing of method to separate method called once at load time to improve performance.
    if (cachedMethod == nullptr) {
        jclass cls = env->FindClass("java/lang/reflect/AccessibleObject");
        // we should have method to remove that global ref when library is no longer needed, but we will skip this part here too
        cachedClazz = (jclass) env->NewGlobalRef(cls);
        cachedMethod = env->GetMethodID(cls, "setAccessible0", "(Z)Z");
    }
    // and just call the method (and we are ignoring returned value)
    env->CallBooleanMethod(accessibleObject, cachedMethod, value);
}

```
Now we can prepare our .dll or .so file and place it in some path close to our java code, 
then use `-Djava.library.path=path_to_folder_with_library/` when running our code, and done, it works:
```
[abc, null, null, null, null, null, null, null, null, null]
```

And another method is to use instrumentation API, there are 2 ways to do so, we can redefine module to make it accessible to our code, 
or modify java internal class to skip access check in `.setAccessible`.  
But probably not everyone here know what instrumentation is, so some short description:  
Instrumentation API allows to redefine java classes and more by special agent libraries, it is often used by code profilers, or some advanced libraries that modify our code to provide some features. (note that often proxy classes can be used instead)  

So we need to create our agent library, it will be very simple:
```
package com.gotofinal.blog.tricks;

import java.lang.instrument.Instrumentation;
import java.util.ArrayList;
import java.util.Map;
import java.util.Set;

public class MyAgent {
    // this is special method for instrumentation agent, just like main method in other apps.
    public static void premain(String arg, Instrumentation instrumentation) {
        String packageName = ArrayList.class.getPackageName();
        Module listModule = ArrayList.class.getModule();
        Module ourModule = ReflectiveAccessModulesInstrumentation.class.getModule();
        // and we just export package with ArrayList class to our module by 4th argument: Map.of(packageName, Set.of(ourModule))
        instrumentation.redefineModule(listModule, Set.of(), Map.of(), Map.of(packageName, Set.of(ourModule)), Set.of(), Map.of());
    }
}
```
Note that this time we are only giving access to this one package, and only from our module.  
Also redefineModule can only add new exports/opens etc, it can't be used to remove some access, this is why most of arguments are empty sets/maps.  
For agent we also need special manifest.mf: 
```
Manifest-Version: 1.0
Premain-Class: com.gotofinal.blog.tricks.MyAgent
```
And now we can run our normal code, with normal `setAccessible(true)` call, but using our agent, and it will work.  
All wee need to do is add our agent using `-javaagent:"path_to_our_agent.jar"` jvm argument.  
Then our `premain` method will be called before `main` method, and make our ArrayList accessible to our module via reflections.  

You can find all used code here:  
[**blog-benchmarks/com/gotofinal/blog/tricks**](https://github.com/GotoFinal/blog-benchmarks/tree/master/basic/src/main/java/com/gotofinal/blog/tricks)  
[**blog-benchmarks/cppcode**](https://github.com/GotoFinal/blog-benchmarks/tree/master/basic/src/main/resources/cppcode)  


NOTE: everything shoved here should not be used in production code without some important reason, as in most cases it can be done it much better way!


In next post I will show how to get instrumentation without separate .jar file, in runtime. 