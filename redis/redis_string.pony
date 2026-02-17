primitive RedisString
  """
  Command builders for Redis string operations.
  """

  fun get(key: ByteSeq): Array[ByteSeq] val =>
    """
    Build a GET command.

    Response: `RespBulkString` with the value, or `RespNull` if the key
    does not exist.
    """
    recover val [as ByteSeq: "GET"; key] end

  fun set(key: ByteSeq, value: ByteSeq): Array[ByteSeq] val =>
    """
    Build a SET command.

    Response: `RespSimpleString` "OK".
    """
    recover val [as ByteSeq: "SET"; key; value] end

  fun set_nx(key: ByteSeq, value: ByteSeq): Array[ByteSeq] val =>
    """
    Build a SET key value NX command. Sets the key only if it does not
    already exist.

    Response: `RespSimpleString` "OK" if the key was set, or `RespNull`
    if the key already exists.
    """
    recover val [as ByteSeq: "SET"; key; value; "NX"] end

  fun set_ex(key: ByteSeq, value: ByteSeq, seconds: U64)
    : Array[ByteSeq] val
  =>
    """
    Build a SET key value EX seconds command. Sets the key with a timeout
    in seconds.

    Response: `RespSimpleString` "OK".
    """
    recover val [as ByteSeq: "SET"; key; value; "EX"; seconds.string()] end

  fun incr(key: ByteSeq): Array[ByteSeq] val =>
    """
    Build an INCR command. Increments the integer value by one.

    Response: `RespInteger` with the value after incrementing.
    """
    recover val [as ByteSeq: "INCR"; key] end

  fun decr(key: ByteSeq): Array[ByteSeq] val =>
    """
    Build a DECR command. Decrements the integer value by one.

    Response: `RespInteger` with the value after decrementing.
    """
    recover val [as ByteSeq: "DECR"; key] end

  fun incr_by(key: ByteSeq, amount: I64): Array[ByteSeq] val =>
    """
    Build an INCRBY command. Increments the integer value by the given
    amount.

    Response: `RespInteger` with the value after incrementing.
    """
    recover val [as ByteSeq: "INCRBY"; key; amount.string()] end

  fun decr_by(key: ByteSeq, amount: I64): Array[ByteSeq] val =>
    """
    Build a DECRBY command. Decrements the integer value by the given
    amount.

    Response: `RespInteger` with the value after decrementing.
    """
    recover val [as ByteSeq: "DECRBY"; key; amount.string()] end

  fun mget(keys: ReadSeq[ByteSeq] val): Array[ByteSeq] val =>
    """
    Build an MGET command. Returns the values of all specified keys.

    Response: `RespArray` of `RespBulkString` or `RespNull` per key.
    """
    recover val
      let arr = Array[ByteSeq](keys.size() + 1)
      arr.push("MGET")
      for k in keys.values() do arr.push(k) end
      arr
    end

  fun mset(pairs: ReadSeq[(ByteSeq, ByteSeq)] val): Array[ByteSeq] val =>
    """
    Build an MSET command. Sets multiple key-value pairs atomically.

    Response: `RespSimpleString` "OK".
    """
    recover val
      let arr = Array[ByteSeq]((pairs.size() * 2) + 1)
      arr.push("MSET")
      for (k, v) in pairs.values() do
        arr.push(k)
        arr.push(v)
      end
      arr
    end
