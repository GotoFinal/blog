---
layout: post
title: Everything is a duck, or not?
date:   2018-03-17 19:30
categories: [java, breakingjava]
---
I didn't post anything in a while again... maybe this time it will be better.  
This post will be short, and next one will be that promised instrumentation. (probably tomorrow)  

![u mad?](/assets/everything-is-a-duck-header.png)  

Anyway, I saw pretty interesting trick in other place (links at the bottom) and I wanted to explore it more.  
Probably many of you know issues with java generics that can allow to mix types and cause some bugs:  
```java
  List<String> strings = new ArrayList<>();
  strings.add("My String");
  ((List) strings).add(54);
  for (String string : strings) { // error
  }
```

But did you know that we can force java to pass any object as some interface? Like this:  
```java
  class SomeClass {
      interface Duck {}
      static void duck(Duck duck){}
      public static void main(String[] args) {
          duck((Duck) (Object) 5);
      }
  }
```

If we will look at the bytecode we can find that there is special instruction that prevent this:  
```java
    ICONST_5
    INVOKESTATIC java/lang/Integer.valueOf (I)Ljava/lang/Integer;
    CHECKCAST com/gotofinal/blog/tricks/SomeClass$Duck // this one!
    INVOKESTATIC com/gotofinal/blog/tricks/SomeClass.duck (Lcom/gotofinal/blog/tricks/SomeClass$Duck;)V
```

But what if we will remove this? I decided to make small code using javassist library that will remove any CHECKCAST instructions from given class:  
```java
  public static void makeUnsafe(String className) throws Exception {
      ClassPool pool = ClassPool.getDefault();
      CtClass originalClass = pool.getCtClass(className);
      originalClass.instrument(new ExprEditor() {
          @Override
          public void edit(Cast c) throws CannotCompileException {
              c.replace("{$_ = $1;}"); // who needs casting?
          }
      });
      originalClass.toClass(); // this will apply all edits
  }
```

It is very important to call such method before given class is loaded, if someone wants something more powerful 
you can always write java agent that will transform that any class you want at load time.  

And there is small showcase of what you can do with this:  
```java
class Executor {
    static List<Duck> ducks = new ArrayList<>();

    public static void run() {
        duck((Duck) (Object) "some string");
        duck((Duck) (Number) 12);
        duck((Duck) (Object) Executor.class);
        duck(new Duck() {});
        for (Duck duck : ducks) {
            System.out.println("Duck: " + duck + " {" + duck.getClass().getName() + "}");
        }
    }

    public static void duck(Duck arg) {
        System.out.println("Called duck with " + arg + " {" + arg.getClass().getName() + "} is this a duck: " + (arg instanceof Duck));
        ducks.add(arg);
// java.lang.IncompatibleClassChangeError: Class <arg class> does not implement the requested interface com.gotofinal.blog.tricks.Duck
//        arg.quack();
    }
}
interface Duck { default void quack() {} }
public class InterfaceTypeChecking {
    public static void main(String[] args) throws Exception {
        makeUnsafe("com.gotofinal.blog.tricks.Executor");
        Executor.run();
    }
}
```
I was pretty surprised that this works without any errors at all, I was pretty sure that method call will do additional checks, or that verify error would be thrown.   
Output:
```
Called duck with some string {java.lang.String} is this a duck: false
Called duck with 12 {java.lang.Integer} is this a duck: false
Called duck with class com.gotofinal.blog.tricks.Executor {java.lang.Class} is this a duck: false
Called duck with com.gotofinal.blog.tricks.Executor$1@1c655221 {com.gotofinal.blog.tricks.Executor$1} is this a duck: true
Duck: some string {java.lang.String}
Duck: 12 {java.lang.Integer}
Duck: class com.gotofinal.blog.tricks.Executor {java.lang.Class}
Duck: com.gotofinal.blog.tricks.Executor$1@1c655221 {com.gotofinal.blog.tricks.Executor$1}
```
As you can see it work, but as expected java still knows that this is not a duck, sadly. Maybe we will change that in one of further posts? ;)  

You can get whole code here: [**com/gotofinal/blog/tricks/InterfaceTypeChecking.java**](https://github.com/GotoFinal/blog-benchmarks/blob/master/java8/src/main/java/com/gotofinal/blog/tricks/InterfaceTypeChecking.java)  

Idea for the post: https://www.excelsiorjet.com/blog/articles/riddles-in-the-dark/  

I also got few new ideas for next posts, and created new category "breaking java" here, if I will find enough time I will try to show you some weird tricks similar to Lombok - so messing with compiler at runtime.  
Also I will write few posts about runtime annotation procession and amazing things that can be done using it - but like always, most of them will be totally impractical and unsafe, but just interesting to watch ;)
