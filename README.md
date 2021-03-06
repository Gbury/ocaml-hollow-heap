Hollow heap
===========

[![CircleCI](https://circleci.com/gh/aspiwack/ocaml-hollow-heap.svg?style=svg)](https://circleci.com/gh/aspiwack/ocaml-hollow-heap)

This repository contains an implementation
of [hollow heaps](http://cs.au.dk/~tdh/papers/Hollow-heaps.pdf) in
Ocaml.

Hollow heaps are an imperative brand of heaps with O(1) `insert`,
`merge`, `find_min`, and `decrease_key` (all the complexity is born by
`delete_min`). It has a relatively simple implementation, and is
supposed to have very good performance.

## Documentation ##

The documentation of the latest development version can be found at
https://aspiwack.github.io/ocaml-hollow-heap/master/ .

## Thoughts about hollow heap ##

The hollow heap data structure implemented in this repository was
initially implemented blindly (using
the [article](http://cs.au.dk/~tdh/papers/Hollow-heaps.pdf) as a
guide, after spending some 15-30 minutes figuring out the general
picture). Property-based testing detected a total of two bugs, which
happened to be typos (they were rather annoying to track down, it must
be confessed).

This indicates that, as advertised, hollow heaps are a very simple
heap data structure, despite supporting `decrease_key`, a notoriously
tricky operation.

## Status ##

This hasn't been used in practice, but the property-based testing run
in CI exercises the API very well. This gives rather good confidence
in the correctness of the implementation.

- [X] Type-checks
- [X] API & code documentation
- [X] Tests & CI
- [X] Publish API documentation
- [ ] Benchmark
- [ ] Package to Opam

