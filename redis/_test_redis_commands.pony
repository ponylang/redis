use "pony_check"
use "pony_test"

// ---------------------------------------------------------------------------
// Test helper
// ---------------------------------------------------------------------------

primitive _ByteSeqString
  """
  Convert a ByteSeq to a String for test assertions.
  """
  fun apply(bs: ByteSeq): String =>
    match bs
    | let s: String val => s
    | let a: Array[U8] val => String.from_array(a)
    end

// ---------------------------------------------------------------------------
// Command builder property-based tests — key-list pattern
// ---------------------------------------------------------------------------

class \nodoc\ iso _TestRedisKeyDelProperty is
  Property1[Array[String] val]
  fun name(): String => "RedisKey/del/Property"

  fun gen(): Generator[Array[String] val] =>
    Generators.iso_seq_of[String, Array[String] iso](
      Generators.ascii_printable(1, 50), 1, 5)
      .map[Array[String] val]({(arr) => consume arr })

  fun property(keys: Array[String] val, h: PropertyHelper) ? =>
    let cmd = RedisKey.del(keys)
    h.assert_eq[USize](keys.size() + 1, cmd.size())
    h.assert_eq[String]("DEL", _ByteSeqString(cmd(0)?))
    var i: USize = 0
    while i < keys.size() do
      h.assert_eq[String](keys(i)?, _ByteSeqString(cmd(i + 1)?))
      i = i + 1
    end

class \nodoc\ iso _TestRedisKeyExistsProperty is
  Property1[Array[String] val]
  fun name(): String => "RedisKey/exists/Property"

  fun gen(): Generator[Array[String] val] =>
    Generators.iso_seq_of[String, Array[String] iso](
      Generators.ascii_printable(1, 50), 1, 5)
      .map[Array[String] val]({(arr) => consume arr })

  fun property(keys: Array[String] val, h: PropertyHelper) ? =>
    let cmd = RedisKey.exists(keys)
    h.assert_eq[USize](keys.size() + 1, cmd.size())
    h.assert_eq[String]("EXISTS", _ByteSeqString(cmd(0)?))
    var i: USize = 0
    while i < keys.size() do
      h.assert_eq[String](keys(i)?, _ByteSeqString(cmd(i + 1)?))
      i = i + 1
    end

class \nodoc\ iso _TestRedisStringMgetProperty is
  Property1[Array[String] val]
  fun name(): String => "RedisString/mget/Property"

  fun gen(): Generator[Array[String] val] =>
    Generators.iso_seq_of[String, Array[String] iso](
      Generators.ascii_printable(1, 50), 1, 5)
      .map[Array[String] val]({(arr) => consume arr })

  fun property(keys: Array[String] val, h: PropertyHelper) ? =>
    let cmd = RedisString.mget(keys)
    h.assert_eq[USize](keys.size() + 1, cmd.size())
    h.assert_eq[String]("MGET", _ByteSeqString(cmd(0)?))
    var i: USize = 0
    while i < keys.size() do
      h.assert_eq[String](keys(i)?, _ByteSeqString(cmd(i + 1)?))
      i = i + 1
    end

// ---------------------------------------------------------------------------
// Command builder property-based tests — key-then-members pattern
// ---------------------------------------------------------------------------

class \nodoc\ iso _TestRedisListLpushProperty is
  Property1[(String, Array[String] val)]
  fun name(): String => "RedisList/lpush/Property"

  fun gen(): Generator[(String, Array[String] val)] =>
    Generators.zip2[String, Array[String] val](
      Generators.ascii_printable(1, 50),
      Generators.iso_seq_of[String, Array[String] iso](
        Generators.ascii_printable(1, 50), 1, 5)
        .map[Array[String] val]({(arr) => consume arr }))

  fun property(sample: (String, Array[String] val),
    h: PropertyHelper) ?
  =>
    (let key, let values) = sample
    let cmd = RedisList.lpush(key, values)
    h.assert_eq[USize](values.size() + 2, cmd.size())
    h.assert_eq[String]("LPUSH", _ByteSeqString(cmd(0)?))
    h.assert_eq[String](key, _ByteSeqString(cmd(1)?))
    var i: USize = 0
    while i < values.size() do
      h.assert_eq[String](values(i)?, _ByteSeqString(cmd(i + 2)?))
      i = i + 1
    end

class \nodoc\ iso _TestRedisListRpushProperty is
  Property1[(String, Array[String] val)]
  fun name(): String => "RedisList/rpush/Property"

  fun gen(): Generator[(String, Array[String] val)] =>
    Generators.zip2[String, Array[String] val](
      Generators.ascii_printable(1, 50),
      Generators.iso_seq_of[String, Array[String] iso](
        Generators.ascii_printable(1, 50), 1, 5)
        .map[Array[String] val]({(arr) => consume arr }))

  fun property(sample: (String, Array[String] val),
    h: PropertyHelper) ?
  =>
    (let key, let values) = sample
    let cmd = RedisList.rpush(key, values)
    h.assert_eq[USize](values.size() + 2, cmd.size())
    h.assert_eq[String]("RPUSH", _ByteSeqString(cmd(0)?))
    h.assert_eq[String](key, _ByteSeqString(cmd(1)?))
    var i: USize = 0
    while i < values.size() do
      h.assert_eq[String](values(i)?, _ByteSeqString(cmd(i + 2)?))
      i = i + 1
    end

class \nodoc\ iso _TestRedisSetSaddProperty is
  Property1[(String, Array[String] val)]
  fun name(): String => "RedisSet/sadd/Property"

  fun gen(): Generator[(String, Array[String] val)] =>
    Generators.zip2[String, Array[String] val](
      Generators.ascii_printable(1, 50),
      Generators.iso_seq_of[String, Array[String] iso](
        Generators.ascii_printable(1, 50), 1, 5)
        .map[Array[String] val]({(arr) => consume arr }))

  fun property(sample: (String, Array[String] val),
    h: PropertyHelper) ?
  =>
    (let key, let members) = sample
    let cmd = RedisSet.sadd(key, members)
    h.assert_eq[USize](members.size() + 2, cmd.size())
    h.assert_eq[String]("SADD", _ByteSeqString(cmd(0)?))
    h.assert_eq[String](key, _ByteSeqString(cmd(1)?))
    var i: USize = 0
    while i < members.size() do
      h.assert_eq[String](members(i)?, _ByteSeqString(cmd(i + 2)?))
      i = i + 1
    end

class \nodoc\ iso _TestRedisSetSremProperty is
  Property1[(String, Array[String] val)]
  fun name(): String => "RedisSet/srem/Property"

  fun gen(): Generator[(String, Array[String] val)] =>
    Generators.zip2[String, Array[String] val](
      Generators.ascii_printable(1, 50),
      Generators.iso_seq_of[String, Array[String] iso](
        Generators.ascii_printable(1, 50), 1, 5)
        .map[Array[String] val]({(arr) => consume arr }))

  fun property(sample: (String, Array[String] val),
    h: PropertyHelper) ?
  =>
    (let key, let members) = sample
    let cmd = RedisSet.srem(key, members)
    h.assert_eq[USize](members.size() + 2, cmd.size())
    h.assert_eq[String]("SREM", _ByteSeqString(cmd(0)?))
    h.assert_eq[String](key, _ByteSeqString(cmd(1)?))
    var i: USize = 0
    while i < members.size() do
      h.assert_eq[String](members(i)?, _ByteSeqString(cmd(i + 2)?))
      i = i + 1
    end

class \nodoc\ iso _TestRedisHashHdelProperty is
  Property1[(String, Array[String] val)]
  fun name(): String => "RedisHash/hdel/Property"

  fun gen(): Generator[(String, Array[String] val)] =>
    Generators.zip2[String, Array[String] val](
      Generators.ascii_printable(1, 50),
      Generators.iso_seq_of[String, Array[String] iso](
        Generators.ascii_printable(1, 50), 1, 5)
        .map[Array[String] val]({(arr) => consume arr }))

  fun property(sample: (String, Array[String] val),
    h: PropertyHelper) ?
  =>
    (let key, let fields) = sample
    let cmd = RedisHash.hdel(key, fields)
    h.assert_eq[USize](fields.size() + 2, cmd.size())
    h.assert_eq[String]("HDEL", _ByteSeqString(cmd(0)?))
    h.assert_eq[String](key, _ByteSeqString(cmd(1)?))
    var i: USize = 0
    while i < fields.size() do
      h.assert_eq[String](fields(i)?, _ByteSeqString(cmd(i + 2)?))
      i = i + 1
    end

// ---------------------------------------------------------------------------
// Command builder property-based tests — key-value pairs pattern
// ---------------------------------------------------------------------------

class \nodoc\ iso _TestRedisStringMsetProperty is
  Property1[Array[(String, String)] val]
  fun name(): String => "RedisString/mset/Property"

  fun gen(): Generator[Array[(String, String)] val] =>
    let str_gen = Generators.ascii_printable(1, 50)
    Generators.usize(1, 5)
      .flat_map[Array[(String, String)] val]({(count)(str_gen) =>
        Generators.iso_seq_of[String, Array[String] iso](
          str_gen, count * 2, count * 2)
          .map[Array[(String, String)] val]({(arr) =>
            let strings: Array[String] val = consume arr
            recover val
              let pairs = Array[(String, String)](strings.size() / 2)
              try
                var i: USize = 0
                while i < strings.size() do
                  pairs.push((strings(i)?, strings(i + 1)?))
                  i = i + 2
                end
              end
              pairs
            end
          })
      })

  fun property(pairs: Array[(String, String)] val,
    h: PropertyHelper) ?
  =>
    let cmd = RedisString.mset(pairs)
    h.assert_eq[USize]((pairs.size() * 2) + 1, cmd.size())
    h.assert_eq[String]("MSET", _ByteSeqString(cmd(0)?))
    var i: USize = 0
    while i < pairs.size() do
      (let k, let v) = pairs(i)?
      h.assert_eq[String](k, _ByteSeqString(cmd((i * 2) + 1)?))
      h.assert_eq[String](v, _ByteSeqString(cmd((i * 2) + 2)?))
      i = i + 1
    end

// ---------------------------------------------------------------------------
// Command builder example-based tests
// ---------------------------------------------------------------------------

class \nodoc\ iso _TestRedisServerExamples is UnitTest
  fun name(): String => "RedisServer/Examples"

  fun apply(h: TestHelper) ? =>
    // ping
    let ping_cmd = RedisServer.ping()
    h.assert_eq[USize](1, ping_cmd.size())
    h.assert_eq[String]("PING", _ByteSeqString(ping_cmd(0)?))

    // echo
    let echo_cmd = RedisServer.echo("hello")
    h.assert_eq[USize](2, echo_cmd.size())
    h.assert_eq[String]("ECHO", _ByteSeqString(echo_cmd(0)?))
    h.assert_eq[String]("hello", _ByteSeqString(echo_cmd(1)?))

    // dbsize
    let dbsize_cmd = RedisServer.dbsize()
    h.assert_eq[USize](1, dbsize_cmd.size())
    h.assert_eq[String]("DBSIZE", _ByteSeqString(dbsize_cmd(0)?))

    // flushdb
    let flushdb_cmd = RedisServer.flushdb()
    h.assert_eq[USize](1, flushdb_cmd.size())
    h.assert_eq[String]("FLUSHDB", _ByteSeqString(flushdb_cmd(0)?))

class \nodoc\ iso _TestRedisStringExamples is UnitTest
  fun name(): String => "RedisString/Examples"

  fun apply(h: TestHelper) ? =>
    // get
    let get_cmd = RedisString.get("mykey")
    h.assert_eq[USize](2, get_cmd.size())
    h.assert_eq[String]("GET", _ByteSeqString(get_cmd(0)?))
    h.assert_eq[String]("mykey", _ByteSeqString(get_cmd(1)?))

    // set
    let set_cmd = RedisString.set("mykey", "myvalue")
    h.assert_eq[USize](3, set_cmd.size())
    h.assert_eq[String]("SET", _ByteSeqString(set_cmd(0)?))
    h.assert_eq[String]("mykey", _ByteSeqString(set_cmd(1)?))
    h.assert_eq[String]("myvalue", _ByteSeqString(set_cmd(2)?))

    // set_nx
    let setnx_cmd = RedisString.set_nx("mykey", "myvalue")
    h.assert_eq[USize](4, setnx_cmd.size())
    h.assert_eq[String]("SET", _ByteSeqString(setnx_cmd(0)?))
    h.assert_eq[String]("mykey", _ByteSeqString(setnx_cmd(1)?))
    h.assert_eq[String]("myvalue", _ByteSeqString(setnx_cmd(2)?))
    h.assert_eq[String]("NX", _ByteSeqString(setnx_cmd(3)?))

    // set_ex
    let setex_cmd = RedisString.set_ex("mykey", "myvalue", 60)
    h.assert_eq[USize](5, setex_cmd.size())
    h.assert_eq[String]("SET", _ByteSeqString(setex_cmd(0)?))
    h.assert_eq[String]("mykey", _ByteSeqString(setex_cmd(1)?))
    h.assert_eq[String]("myvalue", _ByteSeqString(setex_cmd(2)?))
    h.assert_eq[String]("EX", _ByteSeqString(setex_cmd(3)?))
    h.assert_eq[String]("60", _ByteSeqString(setex_cmd(4)?))

    // incr
    let incr_cmd = RedisString.incr("counter")
    h.assert_eq[USize](2, incr_cmd.size())
    h.assert_eq[String]("INCR", _ByteSeqString(incr_cmd(0)?))
    h.assert_eq[String]("counter", _ByteSeqString(incr_cmd(1)?))

    // decr
    let decr_cmd = RedisString.decr("counter")
    h.assert_eq[USize](2, decr_cmd.size())
    h.assert_eq[String]("DECR", _ByteSeqString(decr_cmd(0)?))
    h.assert_eq[String]("counter", _ByteSeqString(decr_cmd(1)?))

    // incr_by
    let incrby_cmd = RedisString.incr_by("counter", 5)
    h.assert_eq[USize](3, incrby_cmd.size())
    h.assert_eq[String]("INCRBY", _ByteSeqString(incrby_cmd(0)?))
    h.assert_eq[String]("counter", _ByteSeqString(incrby_cmd(1)?))
    h.assert_eq[String]("5", _ByteSeqString(incrby_cmd(2)?))

    // decr_by with negative amount
    let decrby_cmd = RedisString.decr_by("counter", -3)
    h.assert_eq[USize](3, decrby_cmd.size())
    h.assert_eq[String]("DECRBY", _ByteSeqString(decrby_cmd(0)?))
    h.assert_eq[String]("counter", _ByteSeqString(decrby_cmd(1)?))
    h.assert_eq[String]("-3", _ByteSeqString(decrby_cmd(2)?))

    // mget
    let mget_keys: Array[String] val = ["k1"; "k2"; "k3"]
    let mget_cmd = RedisString.mget(mget_keys)
    h.assert_eq[USize](4, mget_cmd.size())
    h.assert_eq[String]("MGET", _ByteSeqString(mget_cmd(0)?))
    h.assert_eq[String]("k1", _ByteSeqString(mget_cmd(1)?))
    h.assert_eq[String]("k2", _ByteSeqString(mget_cmd(2)?))
    h.assert_eq[String]("k3", _ByteSeqString(mget_cmd(3)?))

    // mset
    let mset_pairs: Array[(String, String)] val = recover val
      let arr = Array[(String, String)](2)
      arr.push(("k1", "v1"))
      arr.push(("k2", "v2"))
      arr
    end
    let mset_cmd = RedisString.mset(mset_pairs)
    h.assert_eq[USize](5, mset_cmd.size())
    h.assert_eq[String]("MSET", _ByteSeqString(mset_cmd(0)?))
    h.assert_eq[String]("k1", _ByteSeqString(mset_cmd(1)?))
    h.assert_eq[String]("v1", _ByteSeqString(mset_cmd(2)?))
    h.assert_eq[String]("k2", _ByteSeqString(mset_cmd(3)?))
    h.assert_eq[String]("v2", _ByteSeqString(mset_cmd(4)?))

class \nodoc\ iso _TestRedisKeyExamples is UnitTest
  fun name(): String => "RedisKey/Examples"

  fun apply(h: TestHelper) ? =>
    // del
    let del_keys: Array[String] val = ["k1"; "k2"]
    let del_cmd = RedisKey.del(del_keys)
    h.assert_eq[USize](3, del_cmd.size())
    h.assert_eq[String]("DEL", _ByteSeqString(del_cmd(0)?))
    h.assert_eq[String]("k1", _ByteSeqString(del_cmd(1)?))
    h.assert_eq[String]("k2", _ByteSeqString(del_cmd(2)?))

    // exists
    let exists_keys: Array[String] val = ["k1"]
    let exists_cmd = RedisKey.exists(exists_keys)
    h.assert_eq[USize](2, exists_cmd.size())
    h.assert_eq[String]("EXISTS", _ByteSeqString(exists_cmd(0)?))
    h.assert_eq[String]("k1", _ByteSeqString(exists_cmd(1)?))

    // expire
    let expire_cmd = RedisKey.expire("mykey", 300)
    h.assert_eq[USize](3, expire_cmd.size())
    h.assert_eq[String]("EXPIRE", _ByteSeqString(expire_cmd(0)?))
    h.assert_eq[String]("mykey", _ByteSeqString(expire_cmd(1)?))
    h.assert_eq[String]("300", _ByteSeqString(expire_cmd(2)?))

    // ttl
    let ttl_cmd = RedisKey.ttl("mykey")
    h.assert_eq[USize](2, ttl_cmd.size())
    h.assert_eq[String]("TTL", _ByteSeqString(ttl_cmd(0)?))
    h.assert_eq[String]("mykey", _ByteSeqString(ttl_cmd(1)?))

    // persist
    let persist_cmd = RedisKey.persist("mykey")
    h.assert_eq[USize](2, persist_cmd.size())
    h.assert_eq[String]("PERSIST", _ByteSeqString(persist_cmd(0)?))
    h.assert_eq[String]("mykey", _ByteSeqString(persist_cmd(1)?))

    // keys
    let keys_cmd = RedisKey.keys("user:*")
    h.assert_eq[USize](2, keys_cmd.size())
    h.assert_eq[String]("KEYS", _ByteSeqString(keys_cmd(0)?))
    h.assert_eq[String]("user:*", _ByteSeqString(keys_cmd(1)?))

    // rename
    let rename_cmd = RedisKey.rename("oldkey", "newkey")
    h.assert_eq[USize](3, rename_cmd.size())
    h.assert_eq[String]("RENAME", _ByteSeqString(rename_cmd(0)?))
    h.assert_eq[String]("oldkey", _ByteSeqString(rename_cmd(1)?))
    h.assert_eq[String]("newkey", _ByteSeqString(rename_cmd(2)?))

    // type_of -> TYPE
    let type_cmd = RedisKey.type_of("mykey")
    h.assert_eq[USize](2, type_cmd.size())
    h.assert_eq[String]("TYPE", _ByteSeqString(type_cmd(0)?))
    h.assert_eq[String]("mykey", _ByteSeqString(type_cmd(1)?))

class \nodoc\ iso _TestRedisHashExamples is UnitTest
  fun name(): String => "RedisHash/Examples"

  fun apply(h: TestHelper) ? =>
    // hget
    let hget_cmd = RedisHash.hget("myhash", "field1")
    h.assert_eq[USize](3, hget_cmd.size())
    h.assert_eq[String]("HGET", _ByteSeqString(hget_cmd(0)?))
    h.assert_eq[String]("myhash", _ByteSeqString(hget_cmd(1)?))
    h.assert_eq[String]("field1", _ByteSeqString(hget_cmd(2)?))

    // hset
    let hset_cmd = RedisHash.hset("myhash", "field1", "value1")
    h.assert_eq[USize](4, hset_cmd.size())
    h.assert_eq[String]("HSET", _ByteSeqString(hset_cmd(0)?))
    h.assert_eq[String]("myhash", _ByteSeqString(hset_cmd(1)?))
    h.assert_eq[String]("field1", _ByteSeqString(hset_cmd(2)?))
    h.assert_eq[String]("value1", _ByteSeqString(hset_cmd(3)?))

    // hdel
    let hdel_fields: Array[String] val = ["f1"; "f2"]
    let hdel_cmd = RedisHash.hdel("myhash", hdel_fields)
    h.assert_eq[USize](4, hdel_cmd.size())
    h.assert_eq[String]("HDEL", _ByteSeqString(hdel_cmd(0)?))
    h.assert_eq[String]("myhash", _ByteSeqString(hdel_cmd(1)?))
    h.assert_eq[String]("f1", _ByteSeqString(hdel_cmd(2)?))
    h.assert_eq[String]("f2", _ByteSeqString(hdel_cmd(3)?))

    // hget_all
    let hgetall_cmd = RedisHash.hget_all("myhash")
    h.assert_eq[USize](2, hgetall_cmd.size())
    h.assert_eq[String]("HGETALL", _ByteSeqString(hgetall_cmd(0)?))
    h.assert_eq[String]("myhash", _ByteSeqString(hgetall_cmd(1)?))

    // hexists
    let hexists_cmd = RedisHash.hexists("myhash", "field1")
    h.assert_eq[USize](3, hexists_cmd.size())
    h.assert_eq[String]("HEXISTS", _ByteSeqString(hexists_cmd(0)?))
    h.assert_eq[String]("myhash", _ByteSeqString(hexists_cmd(1)?))
    h.assert_eq[String]("field1", _ByteSeqString(hexists_cmd(2)?))

class \nodoc\ iso _TestRedisListExamples is UnitTest
  fun name(): String => "RedisList/Examples"

  fun apply(h: TestHelper) ? =>
    // lpush
    let lpush_vals: Array[String] val = ["a"; "b"]
    let lpush_cmd = RedisList.lpush("mylist", lpush_vals)
    h.assert_eq[USize](4, lpush_cmd.size())
    h.assert_eq[String]("LPUSH", _ByteSeqString(lpush_cmd(0)?))
    h.assert_eq[String]("mylist", _ByteSeqString(lpush_cmd(1)?))
    h.assert_eq[String]("a", _ByteSeqString(lpush_cmd(2)?))
    h.assert_eq[String]("b", _ByteSeqString(lpush_cmd(3)?))

    // rpush
    let rpush_vals: Array[String] val = ["c"]
    let rpush_cmd = RedisList.rpush("mylist", rpush_vals)
    h.assert_eq[USize](3, rpush_cmd.size())
    h.assert_eq[String]("RPUSH", _ByteSeqString(rpush_cmd(0)?))
    h.assert_eq[String]("mylist", _ByteSeqString(rpush_cmd(1)?))
    h.assert_eq[String]("c", _ByteSeqString(rpush_cmd(2)?))

    // lpop
    let lpop_cmd = RedisList.lpop("mylist")
    h.assert_eq[USize](2, lpop_cmd.size())
    h.assert_eq[String]("LPOP", _ByteSeqString(lpop_cmd(0)?))
    h.assert_eq[String]("mylist", _ByteSeqString(lpop_cmd(1)?))

    // rpop
    let rpop_cmd = RedisList.rpop("mylist")
    h.assert_eq[USize](2, rpop_cmd.size())
    h.assert_eq[String]("RPOP", _ByteSeqString(rpop_cmd(0)?))
    h.assert_eq[String]("mylist", _ByteSeqString(rpop_cmd(1)?))

    // llen
    let llen_cmd = RedisList.llen("mylist")
    h.assert_eq[USize](2, llen_cmd.size())
    h.assert_eq[String]("LLEN", _ByteSeqString(llen_cmd(0)?))
    h.assert_eq[String]("mylist", _ByteSeqString(llen_cmd(1)?))

    // lrange with negative index
    let lrange_cmd = RedisList.lrange("mylist", 0, -1)
    h.assert_eq[USize](4, lrange_cmd.size())
    h.assert_eq[String]("LRANGE", _ByteSeqString(lrange_cmd(0)?))
    h.assert_eq[String]("mylist", _ByteSeqString(lrange_cmd(1)?))
    h.assert_eq[String]("0", _ByteSeqString(lrange_cmd(2)?))
    h.assert_eq[String]("-1", _ByteSeqString(lrange_cmd(3)?))

class \nodoc\ iso _TestRedisSetExamples is UnitTest
  fun name(): String => "RedisSet/Examples"

  fun apply(h: TestHelper) ? =>
    // sadd
    let sadd_members: Array[String] val = ["a"; "b"; "c"]
    let sadd_cmd = RedisSet.sadd("myset", sadd_members)
    h.assert_eq[USize](5, sadd_cmd.size())
    h.assert_eq[String]("SADD", _ByteSeqString(sadd_cmd(0)?))
    h.assert_eq[String]("myset", _ByteSeqString(sadd_cmd(1)?))
    h.assert_eq[String]("a", _ByteSeqString(sadd_cmd(2)?))
    h.assert_eq[String]("b", _ByteSeqString(sadd_cmd(3)?))
    h.assert_eq[String]("c", _ByteSeqString(sadd_cmd(4)?))

    // srem
    let srem_members: Array[String] val = ["a"]
    let srem_cmd = RedisSet.srem("myset", srem_members)
    h.assert_eq[USize](3, srem_cmd.size())
    h.assert_eq[String]("SREM", _ByteSeqString(srem_cmd(0)?))
    h.assert_eq[String]("myset", _ByteSeqString(srem_cmd(1)?))
    h.assert_eq[String]("a", _ByteSeqString(srem_cmd(2)?))

    // smembers
    let smembers_cmd = RedisSet.smembers("myset")
    h.assert_eq[USize](2, smembers_cmd.size())
    h.assert_eq[String]("SMEMBERS", _ByteSeqString(smembers_cmd(0)?))
    h.assert_eq[String]("myset", _ByteSeqString(smembers_cmd(1)?))

    // sismember
    let sismember_cmd = RedisSet.sismember("myset", "a")
    h.assert_eq[USize](3, sismember_cmd.size())
    h.assert_eq[String]("SISMEMBER", _ByteSeqString(sismember_cmd(0)?))
    h.assert_eq[String]("myset", _ByteSeqString(sismember_cmd(1)?))
    h.assert_eq[String]("a", _ByteSeqString(sismember_cmd(2)?))

    // scard
    let scard_cmd = RedisSet.scard("myset")
    h.assert_eq[USize](2, scard_cmd.size())
    h.assert_eq[String]("SCARD", _ByteSeqString(scard_cmd(0)?))
    h.assert_eq[String]("myset", _ByteSeqString(scard_cmd(1)?))
