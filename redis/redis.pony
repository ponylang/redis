"""
Redis client for Pony.

## RESP2 Value Types

The protocol layer uses `RespValue` as the core type for data exchanged with
a Redis server. This is a union of:

* `RespSimpleString` — short status responses like "OK"
* `RespBulkString` — binary-safe string data
* `RespInteger` — signed 64-bit integers
* `RespArray` — ordered collections of values
* `RespError` — error responses from the server
* `RespNull` — null/nil values
"""
