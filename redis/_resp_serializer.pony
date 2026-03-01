primitive _RespSerializer
  """
  Serialize a Redis command (an array of bulk strings) into RESP2 wire
  format. Each element of the input array becomes a bulk string in the
  output.
  """
  fun apply(command: Array[ByteSeq] val): Array[U8] val =>
    recover val
      let buf = Array[U8]

      // *<count>\r\n
      buf.push('*')
      for byte in command.size().string().values() do
        buf.push(byte)
      end
      buf.push('\r')
      buf.push('\n')

      for elem in command.values() do
        let elem_size = match \exhaustive\ elem
        | let s: String val => s.size()
        | let a: Array[U8] val => a.size()
        end

        // $<len>\r\n
        buf.push('$')
        for byte in elem_size.string().values() do
          buf.push(byte)
        end
        buf.push('\r')
        buf.push('\n')

        // <data>\r\n
        match \exhaustive\ elem
        | let s: String val =>
          for byte in s.values() do buf.push(byte) end
        | let a: Array[U8] val =>
          for byte in a.values() do buf.push(byte) end
        end
        buf.push('\r')
        buf.push('\n')
      end

      buf
    end
