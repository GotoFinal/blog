---
layout: post
title: Dynamic enums in java
date:   2017-06-24 18:57
categories:  [java, diorite]
---

In java we have `enum` types, they might be great to describe some constant stuff, like days of week.  
But unfortunately some people use them to describe something that might change, like types of users, types of monsters in some game, etc. And this is just wrong, enums should be constant, they should never change or break.  
Now let's imagine that we want to create some game with support for modding, and we used enum for that monster thing... and now it is impossible to add new monster type from mod level. (or isn't?)


So I will show you two things in this post: how to add new constant to already existing enum, and how we can replace enums with something different in our code.

# Hacking into enums
REMEMBER: this is dirty hack, you should never use it, unless there is no other option.   
Let's create a simple enum:
```java
public enum Monster {
    ZOMBIE(Zombie.class, "zombie"),
    ORK(Ork.class, "ork"),
    WOLF(Wolf.class, "wolf");
    private final Class<? extends Entity> entityClass;
    private final String                  entityId;
    Monster(Class<? extends Entity> entityClass, String entityId) {
        this.entityClass = entityClass;
        this.entityId = "monster:" + entityId;
    }
    public Class<? extends Entity> getEntityClass() { return this.entityClass; }
    public String getEntityId() { return this.entityId; }
    public Entity create() {
        try { return entityClass.newInstance(); }
        catch (InstantiationException | IllegalAccessException e) { throw new InternalError(e); }
    }
}
```
(I don't format code like that normally, just for blog)  
Using normal reflections to create new enum instance will just fail, but there are two other ways to do it: 
### Reflections  
But first... Why does normal reflection fail to create our enum instance? We can just go to source of `Constructor` and see what is going here
```java
public T newInstance(Object ... initargs) throws InstantiationException, IllegalAccessException, IllegalArgumentException, InvocationTargetException
{
    if (!override) {
        if (!Reflection.quickCheckMemberAccess(clazz, modifiers)) {
            Class<?> caller = Reflection.getCallerClass();
            checkAccess(caller, clazz, null, modifiers);
    }}
    if ((clazz.getModifiers() & Modifier.ENUM) != 0) throw new IllegalArgumentException("Cannot reflectively create enum objects");
    ConstructorAccessor ca = constructorAccessor;
    if (ca == null) { ca = acquireConstructorAccessor(); }
    return (T) ca.newInstance(initargs);
}
```
And as we can see there is just that little, simple, check: `if ((clazz.getModifiers() & Modifier.ENUM) != 0)`, and we need to skip it.  
So easiest way to do so, is just call that code below this check using reflections:
```java
public static void reflectionWay() throws Throwable {
    Class<Monster> monsterClass = Monster.class;
    // first we need to find our constructor, and make it accessible
    Constructor<?> constructor = monsterClass.getDeclaredConstructors()[0];
    constructor.setAccessible(true);

    // this is this same code as in constructor.newInstance, but we just skipped all that useless enum checks ;)
    Field constructorAccessorField = Constructor.class.getDeclaredField("constructorAccessor");
    constructorAccessorField.setAccessible(true);
    // sun.reflect.ConstructorAccessor -> itnernal class, we should not use it, if you need use it, it would be better to actually not import it, but use it only via reflections. (as package may change, and will in java 9)
    ConstructorAccessor ca = (ConstructorAccessor) constructorAccessorField.get(constructor);
    if (ca == null) {
        Method acquireConstructorAccessorMethod = Constructor.class.getDeclaredMethod("acquireConstructorAccessor");
        acquireConstructorAccessorMethod.setAccessible(true);
        ca = (ConstructorAccessor) acquireConstructorAccessorMethod.invoke(constructor);
    }
    // note that real constructor contains 2 additional parameters, name and oridinal
    Monster enumValue = (Monster) ca.newInstance(new Object[]{"CAERBANNOG_RABBIT", 4, CaerbannogRabbit.class, "caerbannograbbit"});// you can call that using reflections too, reflecting reflections are best part of java ;)
}
```
And done! kind of... `Monster.values()` still does return only 3 objects, we need to fix that too.  
Every enum class have static field: `T[] $VALUES` (note that name can be changed if code was obfuscated, if you want to handle such cases, you should lookup for first field of `T[]`/`Monster[]` type)  
Bad thing is that this field is private, static, and... final, but we can *fix* that too:
```java
static void makeAccessible(Field field) throws Exception {
    field.setAccessible(true);
    Field modifiersField = Field.class.getDeclaredField("modifiers");
    modifiersField.setAccessible(true);
    modifiersField.setInt(field, field.getModifiers() & ~ Modifier.FINAL);
}
```
Yey, more reflections on reflections! So now we can just simple create own fixed array of values: 
```java
Field $VALUESField = Monster.class.getDeclaredField("$VALUES");
makeAccessible($VALUESField);
// just copy old values to new array and add our new field.
Monster[] oldValues = (Monster[]) $VALUESField.get(null);
Monster[] newValues = new Monster[oldValues.length + 1];
System.arraycopy(oldValues, 0, newValues, 0, oldValues.length);
newValues[oldValues.length] = enumValue;
$VALUESField.set(null, newValues);
```
And done!
![Intellij <3](/assets/dynamic-enum-1.png)  
![Intellij <3](/assets/dynamic-enum-2.png)  
(Note that we can't really add new field to enum, so it would never be like real enum field, adding new field is only possible using some bytecode manipulation AND only before class was loaded)
But again... there are still few things we CAN fix!  
`Monster.class.getEnumConstants()` - this still might return old array. (this array is created on first use)  
`Enum.valueOf(Monster.class, "CAERBANNOG_RABBIT")` - this also might fail.  
As you already know how to fix fields like that I will just skip that part (as it will be this same code as above), and only tell you where you need to apply your fixes:  
`private volatile transient T[] enumConstants = null;` - in `Class.class`, note that it can be null.  
`private volatile transient Map<String, T> enumConstantDirectory = null;` - in `Class.class`, note that it can be null too.  
Also note that you can just set that values back to `null` so java will regenerate them on next use.  

### Unsafe
This same thing can be done using unsafe (also should not be used):
```java
public static void unsafeWay() throws Throwable {
    Constructor<?> constructor = Unsafe.class.getDeclaredConstructors()[0];
    constructor.setAccessible(true);
    Unsafe unsafe = (Unsafe) constructor.newInstance();
    Monster enumValue = (Monster) unsafe.allocateInstance(Monster.class);
}
```
Looks simpler? But notice that we didn't even pass anything to constructor of monster, this is how `Unsafe` works, it does NOT call the constructor, it just allocate new object, and this is ver unsafe, as any action on object might now throw unexpected errors, we need to manually simulate constructor!  
So you just need to manually get all fields and set their values.  
```java
Field ordinalField = Enum.class.getDeclaredField("ordinal");
makeAccessible(ordinalField);
ordinalField.setInt(enumValue, 5);

Field nameField = Enum.class.getDeclaredField("name");
makeAccessible(nameField);
nameField.set(enumValue, "LION");

Field entityClassField = Monster.class.getDeclaredField("entityClass");
makeAccessible(entityClassField);
entityClassField.set(enumValue, Lion.class);

Field entityIdField = Monster.class.getDeclaredField("entityId");
makeAccessible(entityIdField);
entityIdField.set(enumValue, "Lion");
```
And then again, you need to add that value to all that arrays and maps (using this same code as for previous way).  
___  
Whole code: [**Gist: EnumHack.java**](https://gist.github.com/GotoFinal/74393bbc88d2b89646c93a9617e04795)

# Own enum
But what if we want to have something similar to enum? I created weird, but working, library that use new `StackWalker` API (java 9) that allows you to create simple and dynamic enums like that:
```java
public class SampleEnum extends DynamicEnum<SampleEnum> {
    public static final SampleEnum A = $("heh");
    private final String someProperty;
    SampleEnum(String someProperty) {this.someProperty = someProperty;}
    public String getSomeProperty() {return this.someProperty;}
    public static SampleEnum[] values() {return DynamicEnum.values(SampleEnum.class);}
    public static SampleEnum valueOf(String name) {return DynamicEnum.valueOf(SampleEnum.class, name);}
}
```
Or like this:
```java
    static class EnumExample extends DynamicEnum<EnumExample>
    {
        public static final EnumExample A = $();
        public static final EnumExample B = $();
        public static final EnumExample C = new EnumExample() { public int doSomething() {return 7;} };
        public int doSomething() {return 5;}
        public static EnumExample[] values() {return DynamicEnum.values(EnumExample.class);}
        public static EnumExample valueOf(String name) {return DynamicEnum.valueOf(EnumExample.class, name);}
    }
```
And it works! you can do `EnumExample.A.name()` and it returns valid `A` name!  
And ofc new values can be added:  
```java
EnumExample d = new EnumExample();
EnumExample e = new EnumExample() {};
Assert.assertSame(3, EnumExample.addEnumElement("D", d)); // returns assigned ordinal
Assert.assertSame(4, EnumExample.addEnumElement("E", e));
```
How it works? A bit tricky, but not that *hacky* as previous reflections: [**Github link**](https://gist.github.com/GotoFinal/2354ca1831aaaefc2a3a45bd71f7d636)  
You can also find it in diorite repository in a bit cleaner form (LazyValue is used, and reflections are handled by special library).  

It is possible to implement that for java 8, but then you need to use internal API `Reflections.getCallerClass()` to track where method was invoked.
____


Also... I need some ideas for new posts! :D