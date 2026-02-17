## Add command builder primitives and response extraction helpers

Six new command builder primitives replace raw `Array[ByteSeq] val` construction for common Redis commands:

* `RedisServer` — PING, ECHO, DBSIZE, FLUSHDB
* `RedisString` — GET, SET, SET NX, SET EX, INCR, DECR, INCRBY, DECRBY, MGET, MSET
* `RedisKey` — DEL, EXISTS, EXPIRE, TTL, PERSIST, KEYS, RENAME, TYPE
* `RedisHash` — HGET, HSET, HDEL, HGETALL, HEXISTS
* `RedisList` — LPUSH, RPUSH, LPOP, RPOP, LLEN, LRANGE
* `RedisSet` — SADD, SREM, SMEMBERS, SISMEMBER, SCARD

A new `RespConvert` primitive provides type-safe extraction from `RespValue` responses without nested pattern matching.

Before:

```pony
// Building commands
let cmd: Array[ByteSeq] val = ["SET"; "key"; "value"]
session.execute(cmd, this)

// Extracting responses
match response
| let s: RespSimpleString =>
  if s.value == "OK" then ... end
| let b: RespBulkString =>
  let value = String.from_array(b.value)
end
```

After:

```pony
// Building commands
session.execute(RedisString.set("key", "value"), this)

// Extracting responses
if RespConvert.is_ok(response) then ... end
match RespConvert.as_string(response)
| let value: String => // use value
end
```
