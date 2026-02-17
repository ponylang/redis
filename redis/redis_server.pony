primitive RedisServer
  """
  Command builders for Redis server operations.
  """

  fun ping(): Array[ByteSeq] val =>
    """
    Build a PING command.

    Response: `RespSimpleString` "PONG".
    """
    recover val [as ByteSeq: "PING"] end

  fun echo(message: ByteSeq): Array[ByteSeq] val =>
    """
    Build an ECHO command.

    Response: `RespBulkString` echoing the message.
    """
    recover val [as ByteSeq: "ECHO"; message] end

  fun dbsize(): Array[ByteSeq] val =>
    """
    Build a DBSIZE command.

    Response: `RespInteger` with the number of keys in the current database.
    """
    recover val [as ByteSeq: "DBSIZE"] end

  fun flushdb(): Array[ByteSeq] val =>
    """
    Build a FLUSHDB command. Removes all keys from the current database.

    Response: `RespSimpleString` "OK".
    """
    recover val [as ByteSeq: "FLUSHDB"] end
