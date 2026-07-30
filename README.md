# redis

A Redis client for [Pony](https://www.ponylang.io/).

## Status

This library is under active development. The API is not yet stable.

## Installation

* Requires ponyc 0.67.0 or later.
* Install [corral](https://github.com/ponylang/corral)
* `corral add github.com/ponylang/redis.git --version 0.0.0`
* `corral fetch` to fetch your dependencies
* `use "redis"` to include this package
* `corral run -- ponyc` to compile your application

This library has a transitive dependency on [ponylang/ssl](https://github.com/ponylang/ssl). It requires a C SSL library to be installed. Please see the [ssl installation instructions](https://github.com/ponylang/ssl?tab=readme-ov-file#installation) for more information.

## API Documentation

[https://ponylang.github.io/redis](https://ponylang.github.io/redis)
