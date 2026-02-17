primitive RedisSet
  """
  Command builders for Redis set operations.
  """

  fun sadd(key: ByteSeq, members: ReadSeq[ByteSeq] val)
    : Array[ByteSeq] val
  =>
    """
    Build an SADD command. Adds one or more members to a set.

    Response: `RespInteger` with the number of new members added (not
    including members already present).
    """
    recover val
      let arr = Array[ByteSeq](members.size() + 2)
      arr.push("SADD")
      arr.push(key)
      for m in members.values() do arr.push(m) end
      arr
    end

  fun srem(key: ByteSeq, members: ReadSeq[ByteSeq] val)
    : Array[ByteSeq] val
  =>
    """
    Build an SREM command. Removes one or more members from a set.

    Response: `RespInteger` with the number of members removed.
    """
    recover val
      let arr = Array[ByteSeq](members.size() + 2)
      arr.push("SREM")
      arr.push(key)
      for m in members.values() do arr.push(m) end
      arr
    end

  fun smembers(key: ByteSeq): Array[ByteSeq] val =>
    """
    Build an SMEMBERS command. Returns all members of a set.

    In RESP2: `RespArray` of `RespBulkString` members.
    In RESP3: `RespSet` of `RespBulkString` members.
    """
    recover val [as ByteSeq: "SMEMBERS"; key] end

  fun sismember(key: ByteSeq, member: ByteSeq): Array[ByteSeq] val =>
    """
    Build an SISMEMBER command. Checks whether a value is a set member.

    Response: `RespInteger` 1 if the member exists, 0 if it does not.
    """
    recover val [as ByteSeq: "SISMEMBER"; key; member] end

  fun scard(key: ByteSeq): Array[ByteSeq] val =>
    """
    Build an SCARD command. Returns the number of members in a set.

    Response: `RespInteger` with the set size.
    """
    recover val [as ByteSeq: "SCARD"; key] end
