use "cli"
use "collections"
use lori = "lori"
use "pony_test"

class \nodoc\ val _RedisTestConfiguration
  let host: String
  let port: String

  new val create(vars: (Array[String] val | None)) =>
    let e = EnvVars(vars)
    host = try e("REDIS_HOST")? else
      ifdef linux then "127.0.0.2" else "localhost" end
    end
    port = try e("REDIS_PORT")? else "6379" end

// integration/Session/ConnectAndReady

class \nodoc\ iso _TestSessionConnectAndReady is UnitTest
  fun name(): String =>
    "integration/Session/ConnectAndReady"

  fun apply(h: TestHelper) =>
    let info = _RedisTestConfiguration(h.env.vars)
    let auth = lori.TCPConnectAuth(h.env.root)
    let session = Session(
      ConnectInfo(auth, info.host, info.port),
      _ConnectAndReadyNotify(h))
    h.dispose_when_done(session)
    h.long_test(5_000_000_000)

actor \nodoc\ _ConnectAndReadyNotify is SessionStatusNotify
  let _h: TestHelper

  new create(h: TestHelper) =>
    _h = h

  be redis_session_ready(session: Session) =>
    _h.complete(true)

  be redis_session_connection_failed(session: Session) =>
    _h.fail("Connection failed")
    _h.complete(false)

// integration/Session/SetAndGet

class \nodoc\ iso _TestSessionSetAndGet is UnitTest
  fun name(): String =>
    "integration/Session/SetAndGet"

  fun apply(h: TestHelper) =>
    let info = _RedisTestConfiguration(h.env.vars)
    let auth = lori.TCPConnectAuth(h.env.root)
    let client = _SetAndGetClient(h)
    let session = Session(
      ConnectInfo(auth, info.host, info.port),
      client)
    h.dispose_when_done(session)
    h.long_test(5_000_000_000)

actor \nodoc\ _SetAndGetClient is (SessionStatusNotify & ResultReceiver)
  let _h: TestHelper
  var _step: USize = 0

  new create(h: TestHelper) =>
    _h = h

  be redis_session_ready(session: Session) =>
    let set_cmd: Array[ByteSeq] val =
      ["SET"; "_test_set_and_get"; "hello_redis"]
    session.execute(set_cmd, this)

  be redis_response(session: Session, response: RespValue) =>
    _step = _step + 1
    if _step == 1 then
      // SET response — should be +OK
      match response
      | let s: RespSimpleString =>
        if s.value != "OK" then
          _h.fail("Expected OK from SET, got: " + s.value)
          _h.complete(false)
          return
        end
      else
        _h.fail("Expected RespSimpleString from SET")
        _h.complete(false)
        return
      end
      let get_cmd: Array[ByteSeq] val = ["GET"; "_test_set_and_get"]
      session.execute(get_cmd, this)
    elseif _step == 2 then
      // GET response — should be bulk string "hello_redis"
      match response
      | let b: RespBulkString =>
        let value = String.from_array(b.value)
        if value != "hello_redis" then
          _h.fail("Expected 'hello_redis', got: '" + value + "'")
          _h.complete(false)
          return
        end
      else
        _h.fail("Expected RespBulkString from GET")
        _h.complete(false)
        return
      end
      // Clean up test key
      let del_cmd: Array[ByteSeq] val = ["DEL"; "_test_set_and_get"]
      session.execute(del_cmd, this)
    else
      // DEL response — done
      _h.complete(true)
    end

  be redis_command_failed(session: Session,
    command: Array[ByteSeq] val, failure: ClientError)
  =>
    _h.fail("Command failed: " + failure.message())
    _h.complete(false)

  be redis_session_connection_failed(session: Session) =>
    _h.fail("Connection failed")
    _h.complete(false)

// integration/Session/ConnectionFailure

class \nodoc\ iso _TestSessionConnectionFailure is UnitTest
  fun name(): String =>
    "integration/Session/ConnectionFailure"

  fun apply(h: TestHelper) =>
    let auth = lori.TCPConnectAuth(h.env.root)
    // Connect to a port that is (almost certainly) not listening.
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    let session = Session(
      ConnectInfo(auth, host, "59872"),
      _ConnectionFailureNotify(h))
    h.dispose_when_done(session)
    h.long_test(5_000_000_000)

actor \nodoc\ _ConnectionFailureNotify is SessionStatusNotify
  let _h: TestHelper

  new create(h: TestHelper) =>
    _h = h

  be redis_session_connection_failed(session: Session) =>
    _h.complete(true)

  be redis_session_ready(session: Session) =>
    _h.fail("Should not have connected")
    _h.complete(false)

// integration/Session/ExecuteBeforeReady

class \nodoc\ iso _TestSessionExecuteBeforeReady is UnitTest
  fun name(): String =>
    "integration/Session/ExecuteBeforeReady"

  fun apply(h: TestHelper) =>
    let info = _RedisTestConfiguration(h.env.vars)
    let auth = lori.TCPConnectAuth(h.env.root)
    let client = _ExecuteBeforeReadyClient(h)
    let session = Session(
      ConnectInfo(auth, info.host, info.port),
      client)
    // Execute immediately — before redis_session_ready fires.
    let cmd: Array[ByteSeq] val = ["PING"]
    session.execute(cmd, client)
    h.dispose_when_done(session)
    h.long_test(5_000_000_000)

actor \nodoc\ _ExecuteBeforeReadyClient is
  (SessionStatusNotify & ResultReceiver)
  let _h: TestHelper

  new create(h: TestHelper) =>
    _h = h

  be redis_command_failed(session: Session,
    command: Array[ByteSeq] val, failure: ClientError)
  =>
    match failure
    | SessionNotReady =>
      _h.complete(true)
    else
      _h.fail("Expected SessionNotReady, got: " + failure.message())
      _h.complete(false)
    end

  be redis_response(session: Session, response: RespValue) =>
    _h.fail("Should not have received a response")
    _h.complete(false)

// integration/Session/ExecuteAfterClose

class \nodoc\ iso _TestSessionExecuteAfterClose is UnitTest
  fun name(): String =>
    "integration/Session/ExecuteAfterClose"

  fun apply(h: TestHelper) =>
    let info = _RedisTestConfiguration(h.env.vars)
    let auth = lori.TCPConnectAuth(h.env.root)
    let client = _ExecuteAfterCloseClient(h)
    let session = Session(
      ConnectInfo(auth, info.host, info.port),
      client)
    h.dispose_when_done(session)
    h.long_test(5_000_000_000)

actor \nodoc\ _ExecuteAfterCloseClient is
  (SessionStatusNotify & ResultReceiver)
  let _h: TestHelper

  new create(h: TestHelper) =>
    _h = h

  be redis_session_ready(session: Session) =>
    session.close()
    let cmd: Array[ByteSeq] val = ["PING"]
    session.execute(cmd, this)

  be redis_command_failed(session: Session,
    command: Array[ByteSeq] val, failure: ClientError)
  =>
    match failure
    | SessionClosed =>
      _h.complete(true)
    else
      _h.fail("Expected SessionClosed, got: " + failure.message())
      _h.complete(false)
    end

  be redis_response(session: Session, response: RespValue) =>
    _h.fail("Should not have received a response")
    _h.complete(false)

  be redis_session_connection_failed(session: Session) =>
    _h.fail("Connection failed")
    _h.complete(false)

// integration/Session/MultipleCommands

class \nodoc\ iso _TestSessionMultipleCommands is UnitTest
  fun name(): String =>
    "integration/Session/MultipleCommands"

  fun apply(h: TestHelper) =>
    let info = _RedisTestConfiguration(h.env.vars)
    let auth = lori.TCPConnectAuth(h.env.root)
    let client = _MultipleCommandsClient(h)
    let session = Session(
      ConnectInfo(auth, info.host, info.port),
      client)
    h.dispose_when_done(session)
    h.long_test(5_000_000_000)

actor \nodoc\ _MultipleCommandsClient is
  (SessionStatusNotify & ResultReceiver)
  let _h: TestHelper
  var _step: USize = 0

  new create(h: TestHelper) =>
    _h = h

  be redis_session_ready(session: Session) =>
    let set_cmd: Array[ByteSeq] val =
      ["SET"; "_test_multi_cmd"; "value1"]
    session.execute(set_cmd, this)
    let get_cmd: Array[ByteSeq] val = ["GET"; "_test_multi_cmd"]
    session.execute(get_cmd, this)
    let del_cmd: Array[ByteSeq] val = ["DEL"; "_test_multi_cmd"]
    session.execute(del_cmd, this)

  be redis_response(session: Session, response: RespValue) =>
    _step = _step + 1
    match _step
    | 1 =>
      // SET response
      match response
      | let s: RespSimpleString =>
        if s.value != "OK" then
          _h.fail("SET: expected OK, got: " + s.value)
          _h.complete(false)
        end
      else
        _h.fail("SET: expected RespSimpleString")
        _h.complete(false)
      end
    | 2 =>
      // GET response
      match response
      | let b: RespBulkString =>
        let value = String.from_array(b.value)
        if value != "value1" then
          _h.fail("GET: expected 'value1', got: '" + value + "'")
          _h.complete(false)
        end
      else
        _h.fail("GET: expected RespBulkString")
        _h.complete(false)
      end
    | 3 =>
      // DEL response — should be integer 1
      match response
      | let i: RespInteger =>
        if i.value != 1 then
          _h.fail("DEL: expected 1, got: " + i.value.string())
          _h.complete(false)
          return
        end
      else
        _h.fail("DEL: expected RespInteger")
        _h.complete(false)
        return
      end
      _h.complete(true)
    else
      _h.fail("Unexpected response step: " + _step.string())
      _h.complete(false)
    end

  be redis_command_failed(session: Session,
    command: Array[ByteSeq] val, failure: ClientError)
  =>
    _h.fail("Command failed: " + failure.message())
    _h.complete(false)

  be redis_session_connection_failed(session: Session) =>
    _h.fail("Connection failed")
    _h.complete(false)

// integration/Session/Pipeline

class \nodoc\ iso _TestSessionPipeline is UnitTest
  fun name(): String =>
    "integration/Session/Pipeline"

  fun apply(h: TestHelper) =>
    let info = _RedisTestConfiguration(h.env.vars)
    let auth = lori.TCPConnectAuth(h.env.root)
    let client = _PipelineClient(h)
    let session = Session(
      ConnectInfo(auth, info.host, info.port),
      client)
    h.dispose_when_done(session)
    h.long_test(5_000_000_000)

actor \nodoc\ _PipelineClient is (SessionStatusNotify & ResultReceiver)
  let _h: TestHelper
  var _step: USize = 0

  new create(h: TestHelper) =>
    _h = h

  be redis_session_ready(session: Session) =>
    // Pipeline 5 SET commands at once.
    for i in Range(0, 5) do
      let key: String val = "_test_pipeline_" + i.string()
      let value: String val = "value_" + i.string()
      let cmd: Array[ByteSeq] val = ["SET"; key; value]
      session.execute(cmd, this)
    end
    // Then pipeline 5 GET commands.
    for i in Range(0, 5) do
      let key: String val = "_test_pipeline_" + i.string()
      let cmd: Array[ByteSeq] val = ["GET"; key]
      session.execute(cmd, this)
    end

  be redis_response(session: Session, response: RespValue) =>
    _step = _step + 1
    if _step <= 5 then
      // SET responses — all should be +OK
      match response
      | let s: RespSimpleString =>
        if s.value != "OK" then
          _h.fail("SET: expected OK, got: " + s.value)
          _h.complete(false)
        end
      else
        _h.fail("SET: expected RespSimpleString")
        _h.complete(false)
      end
    elseif _step <= 10 then
      // GET responses — should match the values we set.
      let i = _step - 6
      let expected: String val = "value_" + i.string()
      match response
      | let b: RespBulkString =>
        let value = String.from_array(b.value)
        if value != expected then
          _h.fail("GET: expected '" + expected + "', got: '" + value + "'")
          _h.complete(false)
        end
      else
        _h.fail("GET: expected RespBulkString")
        _h.complete(false)
      end
      if _step == 10 then
        // Clean up test keys.
        for j in Range(0, 5) do
          let key: String val = "_test_pipeline_" + j.string()
          let cmd: Array[ByteSeq] val = ["DEL"; key]
          session.execute(cmd, this)
        end
      end
    elseif _step == 15 then
      // All DEL responses received — done.
      _h.complete(true)
    end

  be redis_command_failed(session: Session,
    command: Array[ByteSeq] val, failure: ClientError)
  =>
    _h.fail("Command failed: " + failure.message())
    _h.complete(false)

  be redis_session_connection_failed(session: Session) =>
    _h.fail("Connection failed")
    _h.complete(false)

// integration/Session/PipelineMixedResponses

class \nodoc\ iso _TestSessionPipelineMixedResponses is UnitTest
  fun name(): String =>
    "integration/Session/PipelineMixedResponses"

  fun apply(h: TestHelper) =>
    let info = _RedisTestConfiguration(h.env.vars)
    let auth = lori.TCPConnectAuth(h.env.root)
    let client = _PipelineMixedClient(h)
    let session = Session(
      ConnectInfo(auth, info.host, info.port),
      client)
    h.dispose_when_done(session)
    h.long_test(5_000_000_000)

actor \nodoc\ _PipelineMixedClient is (SessionStatusNotify & ResultReceiver)
  let _h: TestHelper
  var _step: USize = 0

  new create(h: TestHelper) =>
    _h = h

  be redis_session_ready(session: Session) =>
    // Pipeline three commands: SET (OK), invalid (ERR), GET (bulk string).
    let set_cmd: Array[ByteSeq] val =
      ["SET"; "_test_pipeline_mixed"; "hello"]
    session.execute(set_cmd, this)
    // SET with wrong arity produces -ERR.
    let bad_cmd: Array[ByteSeq] val = ["SET"; "only_one_arg"]
    session.execute(bad_cmd, this)
    let get_cmd: Array[ByteSeq] val = ["GET"; "_test_pipeline_mixed"]
    session.execute(get_cmd, this)

  be redis_response(session: Session, response: RespValue) =>
    _step = _step + 1
    match _step
    | 1 =>
      // SET response — should be +OK
      match response
      | let s: RespSimpleString =>
        if s.value != "OK" then
          _h.fail("SET: expected OK, got: " + s.value)
          _h.complete(false)
        end
      else
        _h.fail("SET: expected RespSimpleString")
        _h.complete(false)
      end
    | 2 =>
      // Invalid command — should be RespError
      match response
      | let _: RespError => None
      else
        _h.fail("Invalid command: expected RespError")
        _h.complete(false)
      end
    | 3 =>
      // GET response — should be bulk string "hello"
      match response
      | let b: RespBulkString =>
        let value = String.from_array(b.value)
        if value != "hello" then
          _h.fail("GET: expected 'hello', got: '" + value + "'")
          _h.complete(false)
          return
        end
      else
        _h.fail("GET: expected RespBulkString")
        _h.complete(false)
        return
      end
      // Clean up test key.
      let del_cmd: Array[ByteSeq] val = ["DEL"; "_test_pipeline_mixed"]
      session.execute(del_cmd, this)
    | 4 =>
      // DEL response — done.
      _h.complete(true)
    else
      _h.fail("Unexpected response step: " + _step.string())
      _h.complete(false)
    end

  be redis_command_failed(session: Session,
    command: Array[ByteSeq] val, failure: ClientError)
  =>
    _h.fail("Command failed: " + failure.message())
    _h.complete(false)

  be redis_session_connection_failed(session: Session) =>
    _h.fail("Connection failed")
    _h.complete(false)

// integration/Session/PipelineClose

class \nodoc\ iso _TestSessionPipelineClose is UnitTest
  fun name(): String =>
    "integration/Session/PipelineClose"

  fun apply(h: TestHelper) =>
    let info = _RedisTestConfiguration(h.env.vars)
    let auth = lori.TCPConnectAuth(h.env.root)
    let client = _PipelineCloseClient(h)
    let session = Session(
      ConnectInfo(auth, info.host, info.port),
      client)
    h.dispose_when_done(session)
    h.long_test(5_000_000_000)

actor \nodoc\ _PipelineCloseClient is (SessionStatusNotify & ResultReceiver)
  let _h: TestHelper
  var _callback_count: USize = 0

  new create(h: TestHelper) =>
    _h = h

  be redis_session_ready(session: Session) =>
    // Pipeline 5 SET commands and immediately close.
    for i in Range(0, 5) do
      let key: String val = "_test_pipeline_close_" + i.string()
      let cmd: Array[ByteSeq] val = ["SET"; key; "value"]
      session.execute(cmd, this)
    end
    session.close()

  be redis_response(session: Session, response: RespValue) =>
    _callback_count = _callback_count + 1
    if _callback_count == 5 then
      _h.complete(true)
    end

  be redis_command_failed(session: Session,
    command: Array[ByteSeq] val, failure: ClientError)
  =>
    match failure
    | SessionClosed =>
      _callback_count = _callback_count + 1
      if _callback_count == 5 then
        _h.complete(true)
      end
    else
      _h.fail("Expected SessionClosed, got: " + failure.message())
      _h.complete(false)
    end

  be redis_session_connection_failed(session: Session) =>
    _h.fail("Connection failed")
    _h.complete(false)

// integration/Session/ServerError

class \nodoc\ iso _TestSessionServerError is UnitTest
  fun name(): String =>
    "integration/Session/ServerError"

  fun apply(h: TestHelper) =>
    let info = _RedisTestConfiguration(h.env.vars)
    let auth = lori.TCPConnectAuth(h.env.root)
    let client = _ServerErrorClient(h)
    let session = Session(
      ConnectInfo(auth, info.host, info.port),
      client)
    h.dispose_when_done(session)
    h.long_test(5_000_000_000)

actor \nodoc\ _ServerErrorClient is (SessionStatusNotify & ResultReceiver)
  let _h: TestHelper

  new create(h: TestHelper) =>
    _h = h

  be redis_session_ready(session: Session) =>
    // Send a command with the wrong number of arguments.
    let cmd: Array[ByteSeq] val = ["SET"; "only_one_arg"]
    session.execute(cmd, this)

  be redis_response(session: Session, response: RespValue) =>
    match response
    | let e: RespError =>
      _h.complete(true)
    else
      _h.fail("Expected RespError from invalid command")
      _h.complete(false)
    end

  be redis_command_failed(session: Session,
    command: Array[ByteSeq] val, failure: ClientError)
  =>
    _h.fail("Command failed: " + failure.message())
    _h.complete(false)

  be redis_session_connection_failed(session: Session) =>
    _h.fail("Connection failed")
    _h.complete(false)
