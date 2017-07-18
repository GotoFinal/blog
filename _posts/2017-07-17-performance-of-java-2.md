---
layout: post
title: Performance of java, part 2
date:   2017-07-17 8:00
categories: [java, benchmark, performance]
---

Previous posts:  
[***1.* Introduction, primitives, random and modulo**](https://blog.gotofinal.com/java/benchmark/performance/2017/07/09/performance-of-java-1.html)

After first post I was asked to do a test of:
* Using a stream to do simple tasks like sum numbers or sort strings VS old good loops.
* Lambdas VS anonymous classes.
* For loop without index checking.

So instead of testing what I wanted, I will do what you want instead, especially that I already have some of this ideas in my plans, but just not for today.  

## Indexed for loop with try/catch
Someone asked if a for loop can be faster by using a try/catch (for the `IndexOfBoundException`) instead of index checking, throwing an exception can be slow (as a stacktrace must be created), but there is only one exception thrown instead of thousands range checks.  
But to throw an exception java itself also need to check that index, and JIT should do the magic to not check it when we are already doing so, but does it?  

Also... everyone should first think what you will be doing in a loop, as in most cases you really don't need to care about this, as operations inside the loop will consume most of the time and time needed to just roll the loop is invisible at such scale!

This seems to be a pretty complicated topic, so creating one simple test would be just a stupid idea, so I will test multiple different cases:
* for-each loop on the array of 10/1000/10_000_000 elements.
* indexed for loop on the array of 10/1000/10_000_000 elements.
* try/catch indexed for loop on the array of 10/1000/10_000_000 elements.
* indexed for loop with a jumping index inside the loop body (moving backward on some condition etc) on the array of 10/1000/10_000_000 elements.
* try/catch indexed for loop with a jumping index inside the loop body (moving backward on some condition etc) on the array of 10/1000/10_000_000 elements.

All tests will be done on the array of random ints using both a c1 and c2 JIT settings, and with and without some computations inside.  
We also need to be sure that JIT will not remove our loop, I will just use simple trick and sum all numbers and then return it to a JMH blackhole, for sure this isn't best method, but consuming each value in a blackhole also does not work well.  

As we have a 5 different cases, with a 3 different amount and all of that is tested on a 2 different JIT settings and in 2 different scenarios... I will just put link to code at github for anyone who want to read it, as this is 60 separate benchmarks, it would be longer than this post.  
Link: [**[Benchmark source code]**](https://github.com/GotoFinal/blog-benchmarks/blob/master/basic/src/main/java/com/gotofinal/blog/benchmark/part2/ForLoop.java)  
If some people are scared by usage of random in "jumping index" tests, notice that errors are not much bigger than in other cases, in some stats they are even lower.  

Anyway, it was a common myth in java, that iterating with a try/catch is faster, but this is not true...  
And what is even more important, even simple operation in loop make all that problems disappear, as difference between all methods are so small that they are just invisible if you are doing anything more than few simple math operations inside of loop.  

But if you do such small operations that you think you will be able to see difference, then results are pretty interesting... as they are different for C1 and C2 JIT settings.  

For the C1 we can see that overhead of an exception is especially visible for small loops, but what is weird, that even larger loops are still much slower if they use try/catch instead of simple indexed loop, much more than time needed to throw that single exception, how is it possible?  
Everything changes for loops that change indexes while iterating, as then for larger loops we can see very small benefit for try/catch method.  

For the C2 something interesting happens, all overhead of an exception just disappear, there is just no difference between both methods, all results are just this same.  
It didn't just remove loops, as times are still pretty normal, but we just don't see any additional overhead from anything, jumping indexes are still slower, as they just do more operations and they are less predictable, but we can't see any difference between using try/catch and normal range checks.  

You can find full results here: [**[Benchmark results]**](https://gist.github.com/GotoFinal/54d2b1be6888c8c9445af5e9df344aa3)

And if you need performance, just use the C2 JIT (AFAIR: default on server) and don't waste your time on thinking how to write some loop ¯\\_(ツ)_/¯

## Lambdas and anonymous classes
If it still did not change (as this is not part of specification and might be changed in any moment) lambdas are implemented with anonymous classes, and we can see that in stacktraces - how awful they looks in logs.  
So performance should be this same? or worse due to additional overhead? or better due to some JIT magic?  
I think that if there will be any difference, it will be less than 10ns, so nothing important, even in tight loops... but it was requested by few people, so I will do it anyway!  

As someone why asked for this test used a `Runnable` as an example, I will also use a runnable for all my tests.  

We should consider two scenarios:
* When we don't need to pass additional arguments that are not part of method parameters (so any arguments in case of a Runnable)
* And when we need to.

This gives us following 10 cases:
* Normal class used as a lambda by `new MyTask()`
* Cached class instance.
* Nested class used as a lambda by `new MyTask()`
* Cached nested instance.
* Anonymous used as `new Runnable(){}` without additional arguments.
* Anonymous used as `new Runnable(){}` with additional arguments.
* Cached anonymous without additional arguments. (case with additional argument is just impossible, as there is only one instance of it)
* Lambda used as `() -> ...` without additional arguments.
* Lambda used as `() -> ...` with additional arguments.
* Cached lambda without additional arguments

As operation we will again just use `Blackhole.consumeCPU` method with just 1 token, just to ensure that JIT will be fooled that this method is needed.  
There is one problem with this test, JIT might inline that code completely removing lambda, but this isn't real life scenario, as there is depth limit of inlining, and limit for size of code to inline and resulting one, so our tests are a bit simplified. 

All benchmarks were run with the C2 JIT.
```java
Runnable CACHED_ANONYMOUS = new Runnable() {
    public void run() {
        Blackhole.consumeCPU(1);
    }
};
Runnable CACHED_LAMBDA = () -> Blackhole.consumeCPU(1);

void normalClass(Blackhole blackhole) { someTaskConsumer(blackhole, new NormalClass()); }
void normalClassCached(Blackhole blackhole) { someTaskConsumer(blackhole, NormalClass.CACHED); }
void nestedClass(Blackhole blackhole) { someTaskConsumer(blackhole, new NestedClass()); }
void nestedClassCached(Blackhole blackhole) { someTaskConsumer(blackhole, NESTED_CACHED); }
void anonymousWithoutData(Blackhole blackhole) {
    someTaskConsumer(blackhole, new Runnable() {
        public void run() {
            Blackhole.consumeCPU(1);
        }}); }
void anonymousWithData(Blackhole blackhole) {
    someTaskConsumer(blackhole, new Runnable() {
        public void run() {
            Blackhole.consumeCPU(1);
            blackhole.consume(blackhole);
        }}); }
void anonymousCached(Blackhole blackhole) { someTaskConsumer(blackhole, CACHED_ANONYMOUS); }
void lambdaWithoutData(Blackhole blackhole) { someTaskConsumer(blackhole, () -> Blackhole.consumeCPU(1)); }
void lambdaWithData(Blackhole blackhole) { 
    someTaskConsumer(blackhole, () -> {
        Blackhole.consumeCPU(1);
        blackhole.consume(blackhole);
    }); }
void lambdaCached(Blackhole blackhole) { someTaskConsumer(blackhole, CACHED_LAMBDA); }

void someTaskConsumer(Blackhole blackhole, Runnable runnable) {
    Blackhole.consumeCPU(1);
    runnable.run();
    blackhole.consume(runnable);  // to prevent additional optimizations
    Blackhole.consumeCPU(1);
}
static class NormalClass implements Runnable {
    static NormalClass CACHED = new NormalClass();
    public void run() { Blackhole.consumeCPU(1); }}
NestedClass NESTED_CACHED = new NestedClass();
class NestedClass implements Runnable { 
    public void run() { Blackhole.consumeCPU(1); 
}}
```
(You can find this code in more readable from on my github)


And results are just like I expected, nothing really special: 
```
Benchmark                              Mode  Cnt   Score   Error  Units
LambdasVsClasses.anonymousCached       avgt    5  10,614 ± 0,044  ns/op
LambdasVsClasses.anonymousWithData     avgt    5  14,357 ± 0,173  ns/op
LambdasVsClasses.anonymousWithoutData  avgt    5  11,500 ± 0,240  ns/op
LambdasVsClasses.lambdaCached          avgt    5  10,627 ± 0,221  ns/op
LambdasVsClasses.lambdaWithData        avgt    5  14,547 ± 0,139  ns/op
LambdasVsClasses.lambdaWithoutData     avgt    5  10,907 ± 0,050  ns/op
LambdasVsClasses.nestedClass           avgt    5  11,392 ± 0,118  ns/op
LambdasVsClasses.nestedClassCached     avgt    5  10,306 ± 0,084  ns/op
LambdasVsClasses.normalClass           avgt    5  11,414 ± 0,171  ns/op
LambdasVsClasses.normalClassCached     avgt    5  10,607 ± 0,058  ns/op
```
Lambdas on current JVM are just as effective as normal classes etc, if there is any difference, then it is below 1ns.

## Java streams
But what about streams? In many places streams can be used to write much more code in less time in more readable form, but what if performance matters too?  
In most cases that performance isn't needed, but lets check it anyway, as some of use really need it.  

Lets start with something very simple, just sum of random numbers in array:
```java
    int[] random_1_000_000 = new Random(123).ints(1_000_000).toArray();
    long intSumStream() { return IntStream.of(random_1_000_000).sum(); }
    long intSumStreamParallel() { return IntStream.of(random_1_000_000).parallel().sum(); }
    long intSumOldJava() {
        long sum = 0;
        for (int i : random_1_000_000) { sum += i; }
        return sum;
    }
```
And results:
```
Benchmark                             Mode  Cnt        Score       Error  Units
StreamBenchmark.intSumOldJava         avgt    5   314838,491 ±  1775,410  ns/op
StreamBenchmark.intSumStream          avgt    5  2212535,192 ± 14008,312  ns/op
StreamBenchmark.intSumStreamParallel  avgt    5    68159,671 ±  8894,159  ns/op
```
So even for simple operations the overhead of streams are pretty big, but we can really easily do this in parallel, imagine doing that manually in fork join pools? it would be muuuuuuch more work.  
Also results change if we will increase size of stream:
```
Benchmark                                         Mode  Cnt         Score        Error  Units
StreamBenchmark.intSumOldJava_100_000_000         avgt    5  39966676,024 ± 251586,568  ns/op
StreamBenchmark.intSumStreamParallel_100_000_000  avgt    5  21673341,982 ± 582044,682  ns/op
StreamBenchmark.intSumStream_100_000_000          avgt    5  36250534,350 ± 158270,861  ns/op
```
Pretty weird but somehow now stream is faster!

Also it is great place to say that parallel streams... sucks. They use common fork join pool, so if we use them from different threads they might fill all that threads - for simple operations like that, this is even better, as we can't use more cores than exists anyway.  
But you should never do blocking operations in parallel stream, or never ever forever use some locks, as you might end up blocking all parallel threads and blocking them for all other threads, also if unlocking code is run somewhere from parallel stream you will just end up with dead lock.  

But here we are doing near nothing, we should test some much more advanced situations, maybe something like this:
We have 1_000_000 people in database, each peron have uuid, name, age and any amount of bank accounts.
We want to find all people named Kate or Anna that have 15 or less years, and sort them by age and them by name, then we are assuming we need to provide such collection to other code.
Then we need to find all bank accounts of that people from previous collection but only if account does not have money on it.
```java
static final int SIZE = 1_000_000;
Random random = new Random(123);
Map<UUID, Person> workerMap = Stream.generate(() -> new Person(random)).limit(SIZE).collect(Collectors.toMap(p -> p.uuid, p -> p));
static String[] names = {"Steve", "Kate", "Anna", "Brajanek", "( ͡º ͜ʖ͡º)", "Somebody"};
static class Person {
    final UUID uuid = UUID.randomUUID();
    final String name;
    final int age;
    final Collection<Account> accounts;

    Person(Random random) {
        this.name = names[random.nextInt(names.length)];
        this.age = random.nextInt(60) + 1;
        int i = random.nextInt(4);
        this.accounts = new ArrayList<>(i);
        for (int x = 0; x < i; x++) {
            accounts.add(new Account(this, random));
        }
    }
}
static class Account {
    final UUID uuid = UUID.randomUUID();
    final Person owner;
    final double money;

    Account(Person owner, Random random) {
        this.owner = owner;
        this.money = 4000 - random.nextInt(5000);
    }
}
```
We will be using a special random instance with constant seed to ensure that in both cases code will need to process this same amount of data(83541 matching people and a 25117 accounts)  
Implementation without streams:
```java
@Benchmark
public void advancedOperationsOldJava(Blackhole blackhole) {
    Collection<Person> people = new TreeSet<>((a, b) -> {
        int c = Integer.compare(a.age, b.age);
        if (c != 0) {
            return c;
        }
        c = a.name.compareTo(b.name);
        if (c != 0) {
            return c;
        }
        return a.uuid.compareTo(b.uuid);
    });
    for (Person person : workerMap.values()) {
        if ((person.name.equals("Kate") || person.name.equals("Anna")) && (person.age <= 15)) {
            people.add(person);
        }
    }
    if (people.size() != 83541) {
        throw new AssertionError();
    }
    blackhole.consume(people);
    List<Account> accounts = new ArrayList<>();
    for (Person person : people) {
        for (Account account : person.accounts) {
            if (account.money <= 0) {
                accounts.add(account);
            }
        }
    }
    if (accounts.size() != 25117) {
        throw new AssertionError();
    }
    blackhole.consume(accounts);
}
```
Huge and nasty but probably faster (but can be implemented in more readable form :D), vs streams:
```java
@Benchmark
public void advancedOperationsStream(Blackhole blackhole) {
    Collection<Person> people = workerMap.values().stream()
        .filter(person -> ((person.name.equals("Kate") || person.name.equals("Anna")) && (person.age <= 15)))
        .sorted(Comparator.comparingInt((Person p) -> p.age).thenComparing(p -> p.name).thenComparing(p -> p.uuid))
        .collect(Collectors.toList());
    blackhole.consume(people);
    if (people.size() != 83541) {
        throw new AssertionError();
    }
    // NOTE: .flatMap(p -> p.accounts.stream().filter(a -> a.money <= 0)) will be SLOWER
    List<Account> accounts = people.stream()
        .flatMap(p -> p.accounts.stream()).filter(a -> a.money <= 0)
        .collect(Collectors.toList());
    if (accounts.size() != 25117) {
        throw new AssertionError();
    }
    blackhole.consume(accounts);
}
```
I also did a test of this same code but with a parallel stream.  

And results:
```
Benchmark                                          Mode  Cnt    Score   Error  Units
StreamBenchmark2.advancedOperationsOldJava         avgt   10  100,531 ± 1,430  ms/op
StreamBenchmark2.advancedOperationsStream          avgt   10  152,553 ± 0,754  ms/op
StreamBenchmark2.advancedOperationsStreamParallel  avgt   10   36,596 ± 0,515  ms/op
```

And again, normal java way is much faster, but a stream way can be very easily run as parallel task and then be much faster than java one - of we still have enough free threads in pool.

So... streams are great tool to reduce amount of code, but if we need performance we should use normal java OR make sure that we can do this operation in parallel, as like I said, parallel streams sucks for blocking operations.  
Also it is possible to skip that problem, but it requires you to create a new ForkJoinPool and submit a task that will run the parallel stream inside that pool, so it does not look great, and seems to be one more dirty hack.

# What next?

In next posts I will write about performance and costs of:
- `javax.script.ScriptEngine`, how you should use it, and why invoking javascript is so slow, and how to make it faster. 
- Optionals
- Reflections, performance of reflections, MethodHandles and interesting behavior of MethodHandle under some circumstances. Can be reflections faster than normal code?
- Exceptions
- Write to me/in comments if you want to see benchmark of something else!

(Not necessary in this order)  

# Final note

Benchmarks are created using JMH benchmark framework.  
All code used for benchmarks can be found on GitHub: [**[Blog benchmarks]**](https://github.com/GotoFinal/blog-benchmarks)