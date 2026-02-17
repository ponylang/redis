primitive RedisHash
  """
  Command builders for Redis hash operations.
  """

  fun hget(key: ByteSeq, field: ByteSeq): Array[ByteSeq] val =>
    """
    Build an HGET command. Returns the value of a hash field.

    Response: `RespBulkString` with the value, or `RespNull` if the field
    or key does not exist.
    """
    recover val [as ByteSeq: "HGET"; key; field] end

  fun hset(key: ByteSeq, field: ByteSeq, value: ByteSeq)
    : Array[ByteSeq] val
  =>
    """
    Build an HSET command. Sets a hash field to a value.

    Response: `RespInteger` 1 if the field is new, 0 if the field was
    updated.
    """
    recover val [as ByteSeq: "HSET"; key; field; value] end

  fun hdel(key: ByteSeq, fields: ReadSeq[ByteSeq] val)
    : Array[ByteSeq] val
  =>
    """
    Build an HDEL command. Removes the specified fields from a hash.

    Response: `RespInteger` with the number of fields deleted.
    """
    recover val
      let arr = Array[ByteSeq](fields.size() + 2)
      arr.push("HDEL")
      arr.push(key)
      for f in fields.values() do arr.push(f) end
      arr
    end

  fun hget_all(key: ByteSeq): Array[ByteSeq] val =>
    """
    Build an HGETALL command. Returns all fields and values in a hash.

    In RESP2: `RespArray` of alternating field name and value bulk strings.
    In RESP3: `RespMap` of field-value pairs.
    """
    recover val [as ByteSeq: "HGETALL"; key] end

  fun hexists(key: ByteSeq, field: ByteSeq): Array[ByteSeq] val =>
    """
    Build an HEXISTS command. Checks whether a field exists in a hash.

    Response: `RespInteger` 1 if the field exists, 0 if it does not.
    """
    recover val [as ByteSeq: "HEXISTS"; key; field] end
