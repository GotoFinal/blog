---
layout: post
title: Reflections over modules in java 9
date:   2017-11-08 13:00
categories: [java]
---

In Java 9 we have a new module system, I will not write much about it, as there is already a 10000000 better blog posts about it,
but with addition of modules oracle decided to give much more control over reflections to the module creators, 
now people can just block reflections to/for/from given module, and even the `setAccessible(true)` method will not help you to get here.  
By default in Java 9 there is a flag that still allows for illegal access, but it will change in next release, so here we will simulate that next release with a `--illegal-access=deny` flag.  

This might be seen by many people as a good change, as it allows for better encapsulation etc, 
but this is why reflections exist in the first place - so you can skip that limits when needed.  
In most cases you can just open own module to libraries like spring, gson and others to allow for reflective access.  
But what if you need to access something that you are not allowed to - due to performance, needed feature, or whatever, we don't judge ( ͡° ͜ʖ ͡°)?  
Then you can just add special flags like `--add-opens` or `--add-exports`, but sometimes we want to be sure that our library will try to fail-safe and try something stronger even if there no such flag.  

(note: many very popular libraries and framework that are used by near all of us were using reflections over Java code to improve performance, have better control over memory and other features)  

So, let's do something simple - we will just access ArrayList backing array, in Java 8 or with allowed illegal access we would just do:  
```java
ArrayList<String> list = new ArrayList<>();
list.add("abc");
Field elementDataField = ArrayList.class.getDeclaredField("elementData");
elementDataField.setAccessible(true);
Object[] elementData = (Object[]) elementDataField.get(list);
Assert.assertSame("abc", elementData[0]); // NOTE: we can use ==/same, as "abc" is literal added to constant pool on compile time.
System.out.println(Arrays.toString(elementData));
```
And now on the Java 9 we will get additional warnings:  
```
WARNING: An illegal reflective access operation has occurred
WARNING: Illegal reflective access by com.gotofinal.blog.tricks.ReflectiveAccessModules (file:/B:/Java/blog-benchmarks/basic/target/classes/) to field java.util.ArrayList.elementData
WARNING: Please consider reporting this to the maintainers of com.gotofinal.blog.tricks.ReflectiveAccessModules
WARNING: Use --illegal-access=warn to enable warnings of further illegal reflective access operations
WARNING: All illegal access operations will be denied in a future release
[abc, null, null, null, null, null, null, null, null, null]
```
but everything still works, now let's run this with `--illegal-access=deny`:
```
Exception in thread "main" java.lang.reflect.InaccessibleObjectException: Unable to make field transient java.lang.Object[] java.util.ArrayList.elementData accessible: module java.base does not "opens java.util" to unnamed module @c39f790
	at java.base/java.lang.reflect.AccessibleObject.checkCanSetAccessible(AccessibleObject.java:337)
	at java.base/java.lang.reflect.AccessibleObject.checkCanSetAccessible(AccessibleObject.java:281)
	at java.base/java.lang.reflect.Field.checkCanSetAccessible(Field.java:176)
	at java.base/java.lang.reflect.Field.setAccessible(Field.java:170)
	at com.gotofinal.blog.tricks.ReflectiveAccessModules.main(ReflectiveAccessModules.java:12)
```
We can just add a flag as given, but what if we want to be sure that our library will work without any changes to starting script etc?  
**(ofc you should try first to remove any needed reflections like this, and use this only when really needed, don't use it just because it is possible!)**  

There is at least few possible ways to do this, first one is to use good old Unsafe class, but how? In my opinion the best way to do this is to invoke special native setAccessible method - as then we can use it to make any field/method/constructor accessible, and we only need to use unsafe once - but you can also edit modifiers of each field/method you want to access.  
```java
public void setAccessible(boolean flag) {
    AccessibleObject.checkPermission();
    if (flag) checkCanSetAccessible(Reflection.getCallerClass()); // we don't want that!
    setAccessible0(flag); // <--- this one!
}
```
So let's make this method public using unsafe:  
```java
public static Consumer<AccessibleObject> doUnsafeMagic() throws Throwable {
    // first we just need to get instance of unsafe, you can get shared static instance or just create own one:
    Constructor<Unsafe> unsafeConstructor = Unsafe.class.getDeclaredConstructor();
    unsafeConstructor.setAccessible(true);
    Unsafe unsafe = unsafeConstructor.newInstance();

    // now we need to get our method that we want to edit:
    Method setAccessible = AccessibleObject.class.getDeclaredMethod("setAccessible0", boolean.class);

    // now we need to get field where modifiers of method are stored, and use unsafe to find offset from object header to this field:
    Field methodModifiers = Method.class.getDeclaredField("modifiers");
    long methodModifiersOffset = unsafe.objectFieldOffset(methodModifiers);

    // and now we set this modifiers field for our method to new value - just simple public modifier.
    unsafe.getAndSetInt(setAccessible, methodModifiersOffset, Modifier.PUBLIC);

    // and now we can prepare our function as simple reflections invoke call: 
    return obj -> {
        try {
            setAccessible.invoke(obj, true);
        } catch (Exception e) {
            throw new RuntimeException(e); // you definitely should do this in a different way :D
        }
    };
}
```
And now we can add small changes to our code:
```java
ArrayList<String> list = new ArrayList<>();
list.add("abc");

// we only need to call it once in our whole app and then store that function somewhere safe
Consumer<AccessibleObject> setAccessible = doUnsafeMagic();

Field elementDataField = ArrayList.class.getDeclaredField("elementData");
// elementDataField.setAccessible(true);
setAccessible.accept(elementDataField);
Object[] elementData = (Object[]) elementDataField.get(list);
Assert.assertSame("abc", elementData[0]); // NOTE: we can use ==/same, as "abc" is literal added to constant pool on compile time.
System.out.println(Arrays.toString(elementData));
```
And it works! But using unsafe is kind of bad idea too, we might want to use something different - as unsafe might be removed too.  
But that will be covered in next post, as it will be too long for this one.  

So, for now remember that you should not use all this weird stuff unless it is really required!  
But I still don't like oracle for making life harder for some of us, some projects like ByteBuddy needs to use more dirty hacks because of oracle, and it is even more weird if you will think about the reward they get:
> In October 2015, Byte Buddy was distinguished with a Duke's Choice award by Oracle. The award appreciates Byte Buddy for its "tremendous amount of innovation in Java Technology".   

And now they are making developing and supporting such libraries harder.