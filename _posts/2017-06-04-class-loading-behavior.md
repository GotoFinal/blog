---
layout: post
title: Weird class loading and verification behavior
date:   2017-06-04 20:38
categories: java
---

Something about interesting behavior of java class loading...  
Imagine 4 different classes:  
```java
class A { public static UnknownType field; }  
class B { public static void test(UnknownType arg){} }  
class C { public static UnknownType test(UnknownType arg){return arg;} }  
class D { public static UnknownType test(UnknownType arg){throw new RuntimeException();} }  
```  
Where `UnknownType` is some type that isn't available at runtime, do you know what will happen when we will try to load that classes?  
```java
class Test {  
    public static void main(String[] args) throws Throwable {  
        System.out.println(new A());  
        System.out.println(new B());  
        System.out.println(new C());  
        System.out.println(new D());  
    }  
}  
```  
And... it will fail on the `C` class (`java.lang.NoClassDefFoundError: UnknownType`), if we change order of `C` and `D` we will see that ONLY class `C` can't be loaded, why?  
I started from trying other ways of loading and testing that 4 classes, first I loaded them using:  
```java
Class.forName("X", false, Test.class.getClassLoader())  
```  
And then it works, so it is something related to class initialization, but why you can have field of unavailable type, but not a return type of method? And why it works if there is an exception?  

There is only one place where you can try to find answer, the JVM specification, but after few minutes of reading about all class loading and resolving stuff I didn't find anything that would perform such checks.   
So if this is something related to class initialization, maybe it is a class verification? but why it happens that late, and why only that one case is affected?  
Let's forget about `A` and `B`, and check the bytecode of `C` and `D` classes (I will use simplified form of bytecode to improve readability):  
```java
public static UnknownType test(UnknownType arg0) { //(LUnknownType;)LUnknownType;  
    new java/lang/RuntimeException // create new instance of a given type and put in on the top of the stack  
    dup // duplicate a top stack element and also put it one the top of the stack  
    invokespecial java/lang/RuntimeException <init>(()V); // invoke a constructor of the RuntimeException class using first object from stack (so it is removed from stack)  
    athrow // and now throw exception from the stack. (this is why we needed that DUP instruction)  
}  
public static UnknownType main(UnknownType arg0) { //(LUnknownType;)LUnknownType;  
    aload0 // load first local variable to the stack, in this case it is a first argument of the method (for non-static method it would be reference to `this`  
    areturn // and just return it  
}  
```  
And there is nothing special... we can only see that in the first case we don't even touch `UnknownType`, so it must be something related to `aload` or `areturn` instructions, but we didn't call this method, we only loaded a class that was containing it.  
So the only one place where such checks are performed is class verification, so let's try to run this code with `-noveirfy` flag.  
And yes, it works! So now we know where to look: https://docs.oracle.com/javase/specs/jvms/se8/html/jvms-4.html#jvms-4.10.1.9  
Let's start with aload:
![aload](/assets/class-loading-behavior-1.png)  
And nothing, `aload` does not care about type, it just push element to stack. So let's check areturn:
![areturn](/assets/class-loading-behavior-2.png)  
And we can see that it perform multiple checks that involve return type, as it must check if value we want to return is compatible with return type of the method, and that cause JVM to load return type class, but there isn't such class so we have our `java.lang.NoClassDefFoundError: UnknownType` error.  
So... that would be everything I wanted to show you today, I hope you find this interesting (and you were able to understand my english and bytecode (✌ ﾟ ∀ ﾟ)☞). 


(Huh, I need to add some comment section)  