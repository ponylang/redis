class val _QueuedCommand
  """
  A command awaiting its response from the server.
  """
  let command: Array[ByteSeq] val
  let receiver: ResultReceiver

  new val create(
    command': Array[ByteSeq] val,
    receiver': ResultReceiver)
  =>
    command = command'
    receiver = receiver'

class val _BufferedSend
  """
  A serialized command buffered during backpressure. Holds wire-format
  bytes ready to send, and optionally a queued command for response
  matching. User commands from `execute()` have a `_QueuedCommand`;
  internal commands (SUBSCRIBE, UNSUBSCRIBE, etc.) do not.
  """
  let data: Array[U8] val
  let queued: (_QueuedCommand | None)

  new val create(
    data': Array[U8] val,
    queued': (_QueuedCommand | None) = None)
  =>
    data = data'
    queued = queued'

