primitive _BuildHelloCommand
  """
  Build the HELLO 3 command for RESP3 negotiation. If a password is
  configured, includes AUTH credentials in the HELLO command.
  """
  fun apply(info: ConnectInfo): Array[ByteSeq] val =>
    match \exhaustive\ info.password
    | let password: String =>
      let user =
        match \exhaustive\ info.username
        | let u: String => u
        | None => "default"
        end
      recover val [as ByteSeq: "HELLO"; "3"; "AUTH"; user; password] end
    | None =>
      recover val [as ByteSeq: "HELLO"; "3"] end
    end

primitive _BuildAuthCommand
  """
  Build an AUTH command. Includes the username for Redis 6.0+ ACL
  authentication when provided.
  """
  fun apply(username: (String | None), password: String)
    : Array[ByteSeq] val
  =>
    match \exhaustive\ username
    | let user: String =>
      recover val [as ByteSeq: "AUTH"; user; password] end
    | None =>
      recover val [as ByteSeq: "AUTH"; password] end
    end
