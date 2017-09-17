---
layout: post
title: Performance of java, part 3
date:   2017-09-17 14:00
categories: [java, benchmark, performance]
---

Sorry for no updates for such long time, but I just had a lot of other problems. Posts should be now more often, but probably shorter.

Previous posts:  
[***1.* Introduction, primitives, random and modulo**](https://blog.gotofinal.com/java/benchmark/performance/2017/07/09/performance-of-java-1.html)  
[***2.* For loops, lambdas, streams**](https://blog.gotofinal.com/java/benchmark/performance/2017/07/17/performance-of-java-2.html)

In this post we will only focus on reflections, and some two interesting cases when using MethodHandles, we will test reflective access to both private and public fields, and how reflections/method handles performance can be affected if field that store MethodHandle/Field is static and/or final.  
[**[Benchmark source code]**](https://github.com/GotoFinal/blog-benchmarks/blob/master/basic/src/main/java/com/gotofinal/blog/benchmark/part3/ReflectionBenchmark.java)  

Raw results can be found in link above too, here I will only point most interesting cases. 

Lets start with comparing normal reflections:
```
Benchmark                                                Mode  Cnt  Score   Error  Units
normalDirectAccess                                       avgt   10  2,867 ± 0,142  ns/op

somethingPublicFieldAccessor_nonAccessible_access        avgt   10  6,622 ± 0,422  ns/op
somethingPublicFieldAccessor_nonAccessible_static_access avgt   10  5,790 ± 0,177  ns/op
somethingPublicFieldAccessor_access                      avgt   10  6,106 ± 1,180  ns/op
somethingPublicFieldAccessor_static_access               avgt   10  4,840 ± 0,261  ns/op

somethingPrivateFieldAccessor_access                     avgt   10  5,397 ± 0,125  ns/op
somethingPrivateFieldAccessor_static_access              avgt   10  4,758 ± 0,122  ns/op
somethingPrivateFieldAccessor_static_final_access        avgt   10  4,739 ± 0,120  ns/op
```
From that we can see that static or final does not change much, the only difference between static and non-static is less time needed to fetch `Field` instance.  
But we can see that `.setAccessible` gives small performance boost even when you don't need to use it.  
Also time between public and private access does not change much, seems to be this same.
And direct access is 2/3x faster, nothing special here.  

As public and private results are this same in all cases I wll now focus on private access only.

Now something more interesting, method handles:
```
Benchmark                                                Mode  Cnt  Score   Error  Units
somethingPrivateFieldAccessor_handle_access              avgt   10  5,831 ± 0,204  ns/op
somethingPrivateFieldAccessor_handle_bound_access        avgt   10  5,498 ± 0,175  ns/op

somethingPrivateFieldAccessor_static_handle_access       avgt   10  5,408 ± 0,202  ns/op
somethingPrivateFieldAccessor_static_handle_bound_access avgt   10  5,327 ± 0,265  ns/op
```
using `.bind` can also improve performance, and again, nothing special.

But... if we use `static final MethodHandle = ...` in our code something interesting happens:
```
Benchmark                                                      Mode  Cnt  Score   Error  Units
normalDirectAccess                                             avgt   10  2,867 ± 0,142  ns/op
somethingPrivateFieldAccessor_static_final_handle_access       avgt   10  2,827 ± 0,058  ns/op
somethingPrivateFieldAccessor_static_final_handle_bound_access avgt   10  2,859 ± 0,084  ns/op
```
JIT can optimize such MethodHandles much better than all other reflection, allowing to get this same performance as direct access, even on final fields!  
It's great and sad at this same time, as we can use reflections without any overhead, but only if we can construct MethodHandles in static blocks while loading class.  

# Final note

Benchmarks are created using JMH benchmark framework.  
All code used for benchmarks can be found on GitHub: [**[Blog benchmarks]**](https://github.com/GotoFinal/blog-benchmarks)