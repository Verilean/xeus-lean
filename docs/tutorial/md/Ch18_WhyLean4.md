# Chapter 18 — Why Lean 4 runs like C, not GHC

Lean 4 is dependently typed, so it is easy to file it next to Agda or
Idris as "a proof assistant". But its *runtime* was designed for
application code, and it makes choices that differ sharply from GHC.
Those choices — compile to C, reference counting instead of a tracing
GC, first-class C interop with destructors — are why Lean is sometimes
the better engineering choice, not just the better prover. This chapter
is the "why", for people writing applications.

## 18.1 The compilation pipeline: Lean → C → native

Lean does **not** have its own code generator/optimizer the way GHC has
its STG machine and native-code backend. Instead:

```text
your .lean  →  (elaborate + type-check)  →  Lean IR  →  C  →  (leanc → clang/gcc)  →  native
```

The compiler emits **portable C**, and a normal C compiler produces the
binary. Consequences:

- **Portability & embedding.** If a platform has a C compiler, Lean runs
  there. And because the output is C, a Lean library drops into a C/C++
  program as just another `.o`/`.a` — Lean-as-a-library is natural.
- **Where the time goes.** Compile cost is dominated by *elaboration*
  (type-checking, especially heavy proofs), not code generation — the
  C lowering is thin. Ordinary application code elaborates quickly; it
  is proof-heavy code that is slow, and applications avoid that. So
  "dependently typed but compiles fine" is not a paradox: the dependent
  types cost you at the proof, not at every function.

## 18.2 Reference counting, not a tracing GC

This is the big one. GHC uses a generational **tracing** garbage
collector. Lean uses **reference counting**: every heap object carries a
count; when the last reference drops, the object is freed *immediately*.

- **Deterministic, pause-free.** There is no stop-the-world pause, no
  tail-latency spike from a major GC. Memory is reclaimed at the exact
  point the last reference dies — like C++ `shared_ptr` or CPython.
- **Cost is per-object, not per-live-set.** A tracing GC does work
  proportional to the *live* heap it must traverse. Reference counting
  does work only when an object is created or destroyed — idle live
  objects cost nothing.

The classic trade-offs are honest: reference counting pays for count
updates on sharing, and it cannot reclaim reference *cycles* on its own.
Lean mitigates the first with FBIP (§18.3) and borrow analysis, and
immutable functional data rarely forms cycles.

And to be fair to GHC: a generational **copying** GC is *excellent* for
the workload Haskell actually produces — a torrent of tiny, short-lived
allocations in the nursery, where only the handful of survivors get
copied out and everything else is reclaimed in bulk, essentially for
free. For pure, short-lived Haskell values that is hard to beat. The
mismatch is not with Haskell's own values; it is with **external
resources**, and that is the subject of §18.5.

## 18.3 FBIP — functional but in-place

Because the runtime already tracks reference counts, Lean can do
**functional-but-in-place** update: when a value is *uniquely*
referenced (count = 1), an operation that would "copy and modify" — like
`Array.set`, or rebuilding a list in `map` — mutates the existing memory
in place instead of allocating. You write pure, persistent code; when
the data is not shared, you get the performance of destructive update
for free. GHC's laziness + tracing GC make this kind of guaranteed
in-place reuse much harder to reason about.

## 18.4 C/C++ interop with destructors

Binding to C is first class. A Lean function can be implemented in C:

```text
@[extern "my_c_function"]
opaque myFunction : UInt32 → UInt32
```

and a C resource (a file handle, a socket, a GPU buffer, a database
connection) can be wrapped as an **external object** registered with a
**finalizer**. That finalizer is Lean's destructor: it runs *the moment
the wrapper's reference count hits zero*.

```text
// C side (sketch): the finalizer is the destructor.
static void my_resource_finalize(void* p) { close_resource(p); }
static lean_external_class* g_cls;      // registered once with the finalizer
```

So resource management in Lean feels like Python or C++ RAII, **not**
like Haskell: a file wrapper closes its handle deterministically when it
goes out of scope, no `bracket`, no `withFile` gymnastics required for
the common case, and no waiting for a GC to get around to the finalizer.

## 18.5 The GC × FFI mismatch (a concrete case)

A copying GC is great for short-lived Haskell values (§18.2) but
structurally awkward for **external custom resources**, for three
reasons:

- **It can't move them.** A copying collector relocates objects to
  compact the heap. Foreign memory can't be moved, so FFI data must be
  *pinned* (causing fragmentation) or reached through a `ForeignPtr`
  indirection the GC has to special-case.
- **Their cost is invisible to it.** A 16-byte Haskell wrapper can own a
  1 GB GPU buffer or a scarce file descriptor. The GC sizes pressure by
  *Haskell* heap bytes, feels nothing from the tiny wrapper, and so
  leaves the huge/scarce resource alive far longer than it should — you
  hit "too many open files" or run out of VRAM while the Haskell heap
  looks fine. Reference counting frees the resource the instant the
  wrapper drops.
- **Cleanup is nondeterministic.** The finalizer that releases the
  resource runs whenever the *GC* runs, not when the resource dies.

The steady-state cost shows the same thing. Say your program holds
**100 000 live FFI resource wrappers** — cursors
into a C library, texture handles, open connections — for the duration
of a session.

- **Under a tracing GC (GHC):** those 100 000 objects are live heap. The
  collector's work scales with the live set it must traverse, so every
  major collection *walks them again*, and each is a `ForeignPtr` with a
  finalizer tracked through the weak-pointer machinery the GC must
  process on collection. Nothing about them changed — they are just
  sitting there being used — yet they are re-scanned on every GC cycle,
  and they inflate pause times. The cost is proportional to *how many
  resources you hold*, not to how much work you do.
- **Under reference counting (Lean):** there is no traversal at all. A
  live, unchanging object costs **zero** — reference counting only does
  work when a count changes (create / share / drop). 100 000 idle
  wrappers are free; the finalizer for each fires exactly once, when
  that specific wrapper dies. Cleanup is deterministic and the steady
  state has no GC term.

So for FFI-heavy, resource-holding applications — bindings to a big C/C++
library, a long-lived server juggling many native handles — Lean's model
removes a whole class of GC-pressure and finalizer-latency problems that
you would otherwise spend real effort tuning around in GHC.

## 18.6 When Lean 4 is the better choice — and when it isn't

| You value… | Prefer |
|---|---|
| deterministic memory / no GC pauses (real-time, embedded, low-latency servers) | **Lean 4** |
| holding many long-lived native/FFI resources | **Lean 4** (§18.5) |
| easy C/C++ interop, or embedding the language in a C program | **Lean 4** |
| deterministic resource cleanup (files/sockets closed on scope exit) | **Lean 4** |
| one language for both verified components and application code | **Lean 4** |
| a huge library ecosystem (Hackage), mature green-thread concurrency / STM | **GHC/Haskell** |
| decades of production hardening and tooling breadth | **GHC/Haskell** |
| collecting cyclic data structures without care | **GHC/Haskell** |

The honest summary: Haskell still wins on ecosystem breadth and
battle-tested runtime maturity. Lean wins when you want **predictable,
C-like memory behaviour and interop** — plus the option, when you need
it, of proving your code correct in the same language. For an
application developer, the reference-counted, compile-to-C runtime is the
headline feature, and §18.5 is the case where it is not a nicety but a
different order of performance.

## 18.7 Further reading — the primary sources

The claims above are not folklore; the reference-counting runtime is
documented and open. If you want the specification rather than the
summary:

- **"Counting Immutable Beans: Reference Counting Optimized for Purely
  Functional Programming"**, Sebastian Ullrich & Leonardo de Moura
  (IFL 2019) — <https://arxiv.org/abs/1908.05647>. The definitive
  description of Lean 4's reference counting, the reuse analysis behind
  FBIP (§18.3), and borrow inference. Read this first.
- **"Perceus: Garbage Free Reference Counting with Reuse"**, Reinking,
  Xie, de Moura & Leijen (PLDI 2021) —
  <https://www.microsoft.com/en-us/research/publication/perceus-garbage-free-reference-counting-with-reuse/>.
  The same line of work in Koka; the precise-reuse theory Lean's model
  shares.
- **The runtime object model, in the source** — the header defines the
  object layout, `lean_inc` / `lean_dec` (the count operations), and
  `lean_register_external_class` (the finalizer = destructor of §18.4):
  <https://github.com/leanprover/lean4/blob/master/src/include/lean/lean.h>
  with the implementation in
  <https://github.com/leanprover/lean4/blob/master/src/runtime/object.cpp>.
- **The Lean FFI documentation** — `@[extern]`, external objects, and
  how a C resource is wrapped with a finalizer:
  <https://lean-lang.org/doc/reference/latest/> (Lean Language Reference,
  FFI section) and the compiler/runtime docs under
  <https://github.com/leanprover/lean4/tree/master/src/runtime>.

## 18.8 Where to go next

- Ch 17 — the Haskell → Lean translation guide and how to find APIs.
- Ch 11 / Ch 12 — processes and sockets, where deterministic handle
  cleanup shows up in practice.
