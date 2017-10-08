---
layout: post
title: Default hashcode in java and biased locking
date:   2017-10-08 22:00
categories: [java]
---

I see a lot of people asking in many places how default hashcode is implemented?

And in many places I found answer that it is generated from memory address of given object, but this is kind of invalid, so I 
decided to write something about it.  

First, we should know how java handles default hashcode, if object does not override hashcode method java on first call to hashcode will 
generate special hashcode. (you can get it via `System.identityHashCode` too)  
But there is something interesting about that, java does not store that hashcode in some normal variable, or does not recalculate it on each usage 
but instead java stores identity hashcode directly in object header!  
In source code of JVM we can find this nice comment about object header structure:
```
// The markOop describes the header of an object.
//
// Note that the mark is not a real oop but just a word.
// It is placed in the oop hierarchy for historical reasons.
//
// Bit-format of an object header (most significant first, big endian layout below):
//
//  32 bits:
//  --------
//             hash:25 ------------>| age:4    biased_lock:1 lock:2 (normal object)
//             JavaThread*:23 epoch:2 age:4    biased_lock:1 lock:2 (biased object)
//             size:32 ------------------------------------------>| (CMS free block)
//             PromotedObject*:29 ---------->| promo_bits:3 ----->| (CMS promoted object)
//
//  64 bits:
//  --------
//  unused:25 hash:31 -->| unused:1   age:4    biased_lock:1 lock:2 (normal object)
//  JavaThread*:54 epoch:2 unused:1   age:4    biased_lock:1 lock:2 (biased object)
//  PromotedObject*:61 --------------------->| promo_bits:3 ----->| (CMS promoted object)
//  size:64 ----------------------------------------------------->| (CMS free block)
//
//  unused:25 hash:31 -->| cms_free:1 age:4    biased_lock:1 lock:2 (COOPs && normal object)
//  JavaThread*:54 epoch:2 cms_free:1 age:4    biased_lock:1 lock:2 (COOPs && biased object)
//  narrowOop:32 unused:24 cms_free:1 unused:4 promo_bits:3 ----->| (COOPs && CMS promoted object)
//  unused:21 size:35 -->| cms_free:1 unused:7 ------------------>| (COOPs && CMS free block)
```
We can see that there are few bits for hash, but this same bits are used for biased locking!  
But what is biased locking you may ask?  
```
Enables a technique for improving the performance of uncontended synchronization. An object is "biased" toward the thread which first acquires its monitor via a monitorenter bytecode or synchronized method invocation; subsequent monitor-related operations performed by that thread are relatively much faster on multiprocessor machines.
```
So it is just a nice optimization made by the JVM if mostly only one thread is synchronizing on given object, as then JVM can skip many additional 
checks and reduce amount of overhead for simple cases.  
So if we use the identity/default hashcode then we will lose that feature for given object, this is something worth to remember!  

But now, what is that hashcode? After some digging I found that we can actually control what it is, let's try run this simple code:
```java
Object o = new Object();
System.out.println(o.hashCode());
```
With this simple jvm argument: `-XX:hashCode=2`  
And then after each run we will get this same results: `1`  
The `hashCode` argument allow us to choose from 5 different hashcode implementations:  
```c
static inline intptr_t get_next_hash(Thread * Self, oop obj) {
  intptr_t value = 0;
  if (hashCode == 0) {
    // This form uses an unguarded global Park-Miller RNG,
    // so it's possible for two threads to race and generate the same RNG.
    // On MP system we'll have lots of RW access to a global, so the
    // mechanism induces lots of coherency traffic.
    value = os::random();
  } else if (hashCode == 1) {
    // This variation has the property of being stable (idempotent)
    // between STW operations.  This can be useful in some of the 1-0
    // synchronization schemes.
    intptr_t addrBits = cast_from_oop<intptr_t>(obj) >> 3;
    value = addrBits ^ (addrBits >> 5) ^ GVars.stwRandom;
  } else if (hashCode == 2) {
    value = 1;            // for sensitivity testing
  } else if (hashCode == 3) {
    value = ++GVars.hcSequence;
  } else if (hashCode == 4) {
    value = cast_from_oop<intptr_t>(obj);
  } else {
    // Marsaglia's xor-shift scheme with thread-specific state
    // This is probably the best overall implementation -- we'll
    // likely make this the default in future releases.
    unsigned t = Self->_hashStateX;
    t ^= (t << 11);
    Self->_hashStateX = Self->_hashStateY;
    Self->_hashStateY = Self->_hashStateZ;
    Self->_hashStateZ = Self->_hashStateW;
    unsigned v = Self->_hashStateW;
    v = (v ^ (v >> 19)) ^ (t ^ (t >> 8));
    Self->_hashStateW = v;
    value = v;
  }

  value &= markOopDesc::hash_mask;
  if (value == 0) value = 0xBAD;
  assert(value != markOopDesc::no_hash, "invariant");
  TEVENT(hashCode: GENERATE);
  return value;
}
```
So, we have a simple global Park-Miller RNG, some random value based on object address, always `1`, simple counter, just 32 bit pointer address, and currently used "Marsaglia's xor-shift scheme with thread-specific state".  
What can be also interesting, identity hash code can never be 0, if it will somehow generate 0, it will be changed to `0xBAD` value.  

And that would be all for this simple post, next time when you will be reading/talking about internal hashcode generation, as we all do this after work (oh, you don't? that's weird!), you will know how it works and that you should not synchronize on objects that don't override hashcode or are stored as keys in identity hash map!
