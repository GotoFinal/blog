---
layout: post
title: Performance of java, part 1
date:   2017-07-09 19:10
categories: [java, benchmark, performance]
---

This will be a small series about java performance, bigger and smaller tips what you should and what you should not do to create an optimized code.  
As everyone probably know "premature optimization is the root of all evil", but many people does not really understand that, it isn't about writing super slow code like you just do not care about performance, but not wasting time trying to get additional milliseconds where you don't need them.  
But if you already know that option#1 is faster than option#2, then it would be just stupid to still use option#2 if it isn't longer or harder to maintain or read ;)

I will also deal with some larger or smaller myths of performance in java, like performance of streams, optionals etc.  
All posts will be in special [**\[performance\]**](https://blog.gotofinal.com/category/performance) category.

## 1. Primitives vs objects 
Lets start with something very simple, and yet most important optimization that everyone should consider. I will not write much about that, I will just show you some simple code and how slow it is when using objects and how fast it can be.
```java
@Benchmark
public BigDecimal objectPerformance() {
    ThreadLocalRandom current = ThreadLocalRandom.current();
    Collection<Long> longs = new ArrayList<>(1_000_000);
    for (int i = 0; i < 1_000_000; i++) {
        longs.add(current.nextLong());
    }
    BigDecimal sum = new BigDecimal(0);
    for (Long aLong : longs) {
        sum = sum.add(new BigDecimal(aLong));
    }
    return sum;
}

@Benchmark
public BigDecimal primitivesPerformance() {
    ThreadLocalRandom current = ThreadLocalRandom.current();
    long[] longs = new long[1_000_000];
    for (int i = 0; i < 1_000_000; i++) {
        longs[i] = current.nextInt();
    }
    BigDecimal sum = new BigDecimal(0);
    for (long aLong : longs) {
        sum = sum.add(new BigDecimal(aLong));
    }
    return sum;
}
```
Notice that we are adding all numbers to `BigDecimal` so we are performing some additional operations and wrapping primitives to objects anyway, so it is still that big difference? yes, it is:  
```
Benchmark                                       Mode  Cnt   Score   Error  Units
PrimitiveVsObjects.objectPerformance            avgt   20  81.319 ± 6.135  ms/op
PrimitiveVsObjects.primitivesPerformance        avgt   20   7.197 ± 0.089  ms/op
```
If we will just sum that to `long` (and probably overflow long multiple times) we will get:
```

Benchmark                                       Mode  Cnt   Score   Error  Units
PrimitiveVsObjects.objectPerformanceLong        avgt   20  40.422 ± 2.711  ms/op
PrimitiveVsObjects.primitivesPerformanceLong    avgt   20   2.609 ± 0.071  ms/op
```

NOTE: when doing such simple additions, just should first think if you can sum them while reading instead of reading them all to array, it will save you a lot of memory.

And about memory... do you know how much memory you would need for a simple `HashMap<Integer, Integer>`?  
Results might be different depending on machine and jvm arguments, like a compressed Oops, here we will just imagine a typical 64 bit env.  
Lets start with single `Integer` vs `int`, an int itself needs a 32 bits, but Integer is also an Object, and each object in java have special header, and header is 64 bits long, but we also need to store that integer somewhere, we need some variable for it, and variable must reference that `Integer` object, so we need next 64 bits to store reference to object.  
So to store an int, we just need 32 bits of memory, but for an integer we already need `64+64+32 = 160` bits.  

We ofc need to store two of them, so it is now 64 bits vs 320 bits, now we should focus on a HashMap implementation:  
For simplicity I will skip size of the map and additional fields in it, as they are only constant price of each HashMap and does not depend on the amount of data in it.  
So a HashMap use `Node<K,V>[] table;` to store all data, and each node is made of:
```java
class Node<K,V> { // object header of 64 bits
int hash; // 32 bits
K key; // 64-bit reference to 64+32 bit object, so 160 bits. 
V value; // also 160 bits
Node<K,V> next; // 64-bit reference
}
```
Also a table itself is table of 64-bit references, so if we sum this up: 64 + 64 + 32 + 160 + 160 + 64 = 544, and this isn't final result, as an array of nodes will be probably near twice as big as amount of nodes in it to provide good hashing  
We need 544 bits to store 64 bits of data, so you should really think twice before making such map, if you need to create maps like that, you should think about using some library like [**\[fastutil\]**](http://fastutil.di.unimi.it/) (there are different libraries too, like koloboke, or much smaller trovy), it have special `Int2IntOpenHashMap` (that also implements `Map<Integer, Integer>`) that will use much less memory, and will be also much more efficient:  
Fastutil for `Int2IntOpenHashMap` use two int[] arrays, so it only needs 64 bits per entry! + this same overhead for bigger array to provide better hashing.  

Imagine that we need to store:
```
100 entries
Java: 6800 bytes
Fastutil: 800 bytes
// so not big deal.

1 000 000 entries:
Java: 64.85 mebibytes
Fastutils: 7.63 mebibytes
// and now we can see some difference, especially if we will do this on android! (but on android they probably use compressed oops?)
```
As everyone already did a lot of performance benchmarks of all primitive collection libraries, I will not do own one, just google for more, but it can save whole seconds.


## 2. Random
As the `java.util.Random` class exists for a really long time and near everyone use it, but in java 7 we also get new interesting class called `java.util.concurrent.ThreadLocalRandom`  
The difference is that we don't create own one and pass it where we want, but we always need to use it in this same thread as we fetched it:
```java
ThreadLocalRandom current = ThreadLocalRandom.current();
```
And we can not set a seed of it, so it can't be used in places where we need repeatable results for this same input.  
But if we just need to do something randomly, and we don't care about seed... then use a `ThreadLocalRandom` it is much better:
```java
Random              random = new Random();
ThreadLocal<Random> cached = ThreadLocal.withInitial(Random::new);
@Benchmark
public long useThreadLocalRandom() {
    return ThreadLocalRandom.current().nextLong();
}
@Benchmark
public long useNewRandom() {
    return new Random().nextLong();
}
@Benchmark
public long useSingleRandom() {
    return random.nextLong();
}
@Benchmark @Threads(8)
public long useSingleRandomMultiThread() {
    return random.nextLong();
}
@Benchmark @Threads(8)
public long useCachedRandomMultiThread() {
    return cached.get().nextLong();
}
@Benchmark @Threads(8) 
public long useNewRandomMultiThread() {
    return new Random().nextLong();
}
@Benchmark @Threads(8)
public long useThreadLocalRandomMultiThread() {
    return ThreadLocalRandom.current().nextLong();
}
```
And results:
```
RandomTest.useCachedRandomMultiThread       avgt   10    30,419 ±  1,099  ns/op
RandomTest.useNewRandom                     avgt   10    56,680 ±  0,458  ns/op
RandomTest.useNewRandomMultiThread          avgt   10   958,275 ±  3,038  ns/op
RandomTest.useSingleRandom                  avgt   10    22,207 ±  0,058  ns/op
RandomTest.useSingleRandomMultiThread       avgt   10  2083,847 ± 92,389  ns/op
RandomTest.useThreadLocalRandom             avgt   10     4,013 ±  0,030  ns/op
RandomTest.useThreadLocalRandomMultiThread  avgt   10     8,136 ±  0,127  ns/op
```
Notice how creating new Random instance can be faster than using this same on each call in multithreaded environment.  
But even when using singe thread ThreadLocalRandom can be much faster than any Random instance.  
It is 5x faster, but it is also only few ns, so you don't need change exiting code (unless you are creating something that ust mostly randoms) and nothing will happen if you will still use old Random, so just remember that there is such class, maybe you will need that additional performance some day, and it does not involve any changes to existing code, so... why not.  


## 3. Checking if number is odd
What do you think is faster for checking if number can be divided by 2? `(n & 1) == 0` or `(n % 2) == 0)`?  
First one for sure looks like much faster operation, but I heard many people that were saying that JIT will make both of that equals, is that true?
```java
    public static Random rand = ThreadLocalRandom.current();
    @Benchmark
    public int rand() { return rand.nextInt(); } // so we can see how much time is needed just to generate number.
    @Benchmark
    public boolean isDivBy2_and() {
        return ((rand.nextInt() & 1) == 0);
    }
    @Benchmark
    public boolean isDivBy2_mod() {
        return (rand.nextInt() % 2) == 0;
    }
```
And results:
```
Benchmark                       Mode  Cnt   Score   Error  Units
ModuleBench.isDivBy2_and        avgt    3   4,315 ± 0,029  ns/op
ModuleBench.isDivBy2_mod        avgt    3  10,395 ± 0,335  ns/op
ModuleBench.rand                avgt    3   4,305 ± 0,107  ns/op
```
And... `%` is a lot slower here, most of the time for `&` is just generating random number, but for `%` it take more time to perform modulo than to generate random number.  
What about readability? I would say that both are easy to read, but ofc I know that some of you might think differently.  
But again, this is only few ns, you only need think about that if you are doing such operations in tight loop.


# What next?

In next posts I will write about performance and costs of:
- `javax.script.ScriptEngine`, how you should use it, and why invoking javascript is so slow, and how to make it faster. 
- Collection.removeIf, can it save time? or just add some lambda overhead over using iterator?
- Lambdas and streams, is there any overhead?
- Optionals
- Reflections, performance of reflections, MethodHandles and interesting behavior of MethodHandle under some circumstances. Can be reflections faster than normal code?
- Exceptions
- Write to me/in comments if you want to see benchmark of something else!

(Not necessary in this order)  

# Final note
(added after publishing of part 2)  
Benchmarks are created using JMH benchmark framework.  
All code used for benchmarks can be found on GitHub: [**[Blog benchmarks]**](https://github.com/GotoFinal/blog-benchmarks)