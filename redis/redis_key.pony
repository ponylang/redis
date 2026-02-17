primitive RedisKey
  """
  Command builders for Redis key operations.
  """

  fun del(key_list: ReadSeq[ByteSeq] val): Array[ByteSeq] val =>
    """
    Build a DEL command. Removes the specified keys.

    Response: `RespInteger` with the number of keys deleted.
    """
    recover val
      let arr = Array[ByteSeq](key_list.size() + 1)
      arr.push("DEL")
      for k in key_list.values() do arr.push(k) end
      arr
    end

  fun exists(key_list: ReadSeq[ByteSeq] val): Array[ByteSeq] val =>
    """
    Build an EXISTS command. Checks how many of the specified keys exist.

    Response: `RespInteger` with the number of keys that exist.
    """
    recover val
      let arr = Array[ByteSeq](key_list.size() + 1)
      arr.push("EXISTS")
      for k in key_list.values() do arr.push(k) end
      arr
    end

  fun expire(key: ByteSeq, seconds: U64): Array[ByteSeq] val =>
    """
    Build an EXPIRE command. Sets a timeout on a key.

    Response: `RespInteger` 1 if the timeout was set, 0 if the key does
    not exist.
    """
    recover val [as ByteSeq: "EXPIRE"; key; seconds.string()] end

  fun ttl(key: ByteSeq): Array[ByteSeq] val =>
    """
    Build a TTL command. Returns the remaining time to live of a key.

    Response: `RespInteger` with seconds remaining, -1 if the key has no
    expiry, or -2 if the key does not exist.
    """
    recover val [as ByteSeq: "TTL"; key] end

  fun persist(key: ByteSeq): Array[ByteSeq] val =>
    """
    Build a PERSIST command. Removes the expiry from a key.

    Response: `RespInteger` 1 if the timeout was removed, 0 if the key
    has no expiry or does not exist.
    """
    recover val [as ByteSeq: "PERSIST"; key] end

  fun keys(pattern: ByteSeq): Array[ByteSeq] val =>
    """
    Build a KEYS command. Returns all keys matching the glob-style pattern.

    Response: `RespArray` of `RespBulkString` matching keys.
    """
    recover val [as ByteSeq: "KEYS"; pattern] end

  fun rename(key: ByteSeq, new_key: ByteSeq): Array[ByteSeq] val =>
    """
    Build a RENAME command. Renames a key.

    Response: `RespSimpleString` "OK".
    """
    recover val [as ByteSeq: "RENAME"; key; new_key] end

  fun type_of(key: ByteSeq): Array[ByteSeq] val =>
    """
    Build a TYPE command. Returns the type of the value stored at key.
    Named `type_of` because `type` is a reserved word in Pony.

    Response: `RespSimpleString` with the type name (string, list, set,
    zset, hash, or stream).
    """
    recover val [as ByteSeq: "TYPE"; key] end
