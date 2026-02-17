primitive RedisList
  """
  Command builders for Redis list operations.
  """

  fun lpush(key: ByteSeq, values: ReadSeq[ByteSeq] val)
    : Array[ByteSeq] val
  =>
    """
    Build an LPUSH command. Prepends one or more values to a list.

    Response: `RespInteger` with the list length after the push.
    """
    recover val
      let arr = Array[ByteSeq](values.size() + 2)
      arr.push("LPUSH")
      arr.push(key)
      for v in values.values() do arr.push(v) end
      arr
    end

  fun rpush(key: ByteSeq, values: ReadSeq[ByteSeq] val)
    : Array[ByteSeq] val
  =>
    """
    Build an RPUSH command. Appends one or more values to a list.

    Response: `RespInteger` with the list length after the push.
    """
    recover val
      let arr = Array[ByteSeq](values.size() + 2)
      arr.push("RPUSH")
      arr.push(key)
      for v in values.values() do arr.push(v) end
      arr
    end

  fun lpop(key: ByteSeq): Array[ByteSeq] val =>
    """
    Build an LPOP command. Removes and returns the first element.

    Response: `RespBulkString` with the value, or `RespNull` if the list
    is empty.
    """
    recover val [as ByteSeq: "LPOP"; key] end

  fun rpop(key: ByteSeq): Array[ByteSeq] val =>
    """
    Build an RPOP command. Removes and returns the last element.

    Response: `RespBulkString` with the value, or `RespNull` if the list
    is empty.
    """
    recover val [as ByteSeq: "RPOP"; key] end

  fun llen(key: ByteSeq): Array[ByteSeq] val =>
    """
    Build an LLEN command. Returns the length of a list.

    Response: `RespInteger` with the list length.
    """
    recover val [as ByteSeq: "LLEN"; key] end

  fun lrange(key: ByteSeq, start: I64, stop: I64): Array[ByteSeq] val =>
    """
    Build an LRANGE command. Returns elements from index `start` to `stop`
    (inclusive). Negative indices count from the end (-1 is the last
    element).

    Response: `RespArray` of `RespBulkString` elements.
    """
    recover val
      [as ByteSeq: "LRANGE"; key; start.string(); stop.string()]
    end
