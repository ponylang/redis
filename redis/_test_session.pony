use "cli"
use "collections"
use lori = "lori"
use "pony_test"
use "ssl/net"

class \nodoc\ val _RedisTestConfiguration
  let host: String
  let port: String
  let ssl_host: String
  let ssl_port: String
  let resp2_host: String
  let resp2_port: String

  new val create(vars: (Array[String] val | None)) =>
    let e = EnvVars(vars)
    host = try e("REDIS_HOST")? else
      ifdef linux then "127.0.0.2" else "localhost" end
    end
    port = try e("REDIS_PORT")? else "6379" end
    ssl_host = try e("REDIS_SSL_HOST")? else host end
    ssl_port = try e("REDIS_SSL_PORT")? else "6380" end
    resp2_host = try e("REDIS_RESP2_HOST")? else host end
    resp2_port = try e("REDIS_RESP2_PORT")? else "6381" end

// integration/Session/ConnectAndReady

class \nodoc\ iso _TestSessionConnectAndReady is UnitTest
  fun name(): String =>
    "integration/Session/ConnectAndReady"

  fun exclusion_group(): String => "integration"

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
  var _done: Bool = false

  new create(h: TestHelper) =>
    _h = h

  be redis_session_ready(session: Session) =>
    _done = true
    _h.complete(true)

  be redis_session_connection_failed(session: Session) =>
    _h.fail("Connection failed")
    _h.complete(false)

  be redis_session_closed(session: Session) =>
    if not _done then
      _h.fail("Session closed unexpectedly")
      _h.complete(false)
    end

// integration/Session/SetAndGet

class \nodoc\ iso _TestSessionSetAndGet is UnitTest
  fun name(): String =>
    "integration/Session/SetAndGet"

  fun exclusion_group(): String => "integration"

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
  var _done: Bool = false
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
      _done = true
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

  be redis_session_closed(session: Session) =>
    if not _done then
      _h.fail("Session closed unexpectedly")
      _h.complete(false)
    end

// integration/Session/ConnectionFailure

class \nodoc\ iso _TestSessionConnectionFailure is UnitTest
  fun name(): String =>
    "integration/Session/ConnectionFailure"

  fun exclusion_group(): String => "integration"

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
  var _done: Bool = false

  new create(h: TestHelper) =>
    _h = h

  be redis_session_connection_failed(session: Session) =>
    _done = true
    _h.complete(true)

  be redis_session_ready(session: Session) =>
    _h.fail("Should not have connected")
    _h.complete(false)

  be redis_session_closed(session: Session) =>
    if not _done then
      _h.fail("Session closed unexpectedly")
      _h.complete(false)
    end

// integration/Session/ExecuteBeforeReady

class \nodoc\ iso _TestSessionExecuteBeforeReady is UnitTest
  fun name(): String =>
    "integration/Session/ExecuteBeforeReady"

  fun exclusion_group(): String => "integration"

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
  var _done: Bool = false

  new create(h: TestHelper) =>
    _h = h

  be redis_command_failed(session: Session,
    command: Array[ByteSeq] val, failure: ClientError)
  =>
    match failure
    | SessionNotReady =>
      _done = true
      _h.complete(true)
    else
      _h.fail("Expected SessionNotReady, got: " + failure.message())
      _h.complete(false)
    end

  be redis_response(session: Session, response: RespValue) =>
    _h.fail("Should not have received a response")
    _h.complete(false)

  be redis_session_closed(session: Session) =>
    if not _done then
      _h.fail("Session closed unexpectedly")
      _h.complete(false)
    end

// integration/Session/ExecuteAfterClose

class \nodoc\ iso _TestSessionExecuteAfterClose is UnitTest
  fun name(): String =>
    "integration/Session/ExecuteAfterClose"

  fun exclusion_group(): String => "integration"

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

  fun exclusion_group(): String => "integration"

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
  var _done: Bool = false
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
      _done = true
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

  be redis_session_closed(session: Session) =>
    if not _done then
      _h.fail("Session closed unexpectedly")
      _h.complete(false)
    end

// integration/Session/Pipeline

class \nodoc\ iso _TestSessionPipeline is UnitTest
  fun name(): String =>
    "integration/Session/Pipeline"

  fun exclusion_group(): String => "integration"

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
  var _done: Bool = false
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
      _done = true
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

  be redis_session_closed(session: Session) =>
    if not _done then
      _h.fail("Session closed unexpectedly")
      _h.complete(false)
    end

// integration/Session/PipelineMixedResponses

class \nodoc\ iso _TestSessionPipelineMixedResponses is UnitTest
  fun name(): String =>
    "integration/Session/PipelineMixedResponses"

  fun exclusion_group(): String => "integration"

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
  var _done: Bool = false
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
      _done = true
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

  be redis_session_closed(session: Session) =>
    if not _done then
      _h.fail("Session closed unexpectedly")
      _h.complete(false)
    end

// integration/Session/PipelineClose

class \nodoc\ iso _TestSessionPipelineClose is UnitTest
  fun name(): String =>
    "integration/Session/PipelineClose"

  fun exclusion_group(): String => "integration"

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

  fun exclusion_group(): String => "integration"

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
  var _done: Bool = false

  new create(h: TestHelper) =>
    _h = h

  be redis_session_ready(session: Session) =>
    // Send a command with the wrong number of arguments.
    let cmd: Array[ByteSeq] val = ["SET"; "only_one_arg"]
    session.execute(cmd, this)

  be redis_response(session: Session, response: RespValue) =>
    match response
    | let e: RespError =>
      _done = true
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

  be redis_session_closed(session: Session) =>
    if not _done then
      _h.fail("Session closed unexpectedly")
      _h.complete(false)
    end

// integration/Session/PubSub

class \nodoc\ iso _TestSessionPubSub is UnitTest
  fun name(): String =>
    "integration/Session/PubSub"

  fun exclusion_group(): String => "integration"

  fun apply(h: TestHelper) =>
    let info = _RedisTestConfiguration(h.env.vars)
    let auth = lori.TCPConnectAuth(h.env.root)
    _PubSubClient(h, auth, info.host, info.port)
    h.long_test(5_000_000_000)

actor \nodoc\ _PubSubClient is
  (SessionStatusNotify & SubscriptionNotify & ResultReceiver)
  let _h: TestHelper
  var _done: Bool = false
  let _subscriber: Session
  let _publisher: Session
  var _ready_count: USize = 0

  new create(h: TestHelper, auth: lori.TCPConnectAuth,
    host: String, port: String)
  =>
    _h = h
    _subscriber = Session(ConnectInfo(auth, host, port), this)
    _publisher = Session(ConnectInfo(auth, host, port), this)
    h.dispose_when_done(_subscriber)
    h.dispose_when_done(_publisher)

  be redis_session_ready(session: Session) =>
    _ready_count = _ready_count + 1
    if _ready_count == 2 then
      let channels: Array[String] val = ["_test_pubsub"]
      _subscriber.subscribe(channels, this)
    end

  be redis_subscribed(session: Session, channel: String,
    count: USize)
  =>
    let cmd: Array[ByteSeq] val = ["PUBLISH"; "_test_pubsub"; "hello"]
    _publisher.execute(cmd, this)

  be redis_message(session: Session, channel: String,
    data: Array[U8] val)
  =>
    if channel != "_test_pubsub" then
      _h.fail("Expected channel '_test_pubsub', got: '" + channel + "'")
      _h.complete(false)
      return
    end
    if String.from_array(data) != "hello" then
      _h.fail("Expected data 'hello', got: '"
        + String.from_array(data) + "'")
      _h.complete(false)
      return
    end
    let channels: Array[String] val = ["_test_pubsub"]
    _subscriber.unsubscribe(channels)

  be redis_unsubscribed(session: Session, channel: String,
    count: USize)
  =>
    if count == 0 then
      _done = true
      _h.complete(true)
    end

  be redis_response(session: Session, response: RespValue) =>
    // PUBLISH response — ignore.
    None

  be redis_command_failed(session: Session,
    command: Array[ByteSeq] val, failure: ClientError)
  =>
    _h.fail("Command failed: " + failure.message())
    _h.complete(false)

  be redis_session_connection_failed(session: Session) =>
    _h.fail("Connection failed")
    _h.complete(false)

  be redis_session_closed(session: Session) =>
    if not _done then
      _h.fail("Session closed unexpectedly")
      _h.complete(false)
    end

// integration/Session/PubSubPattern

class \nodoc\ iso _TestSessionPubSubPattern is UnitTest
  fun name(): String =>
    "integration/Session/PubSubPattern"

  fun exclusion_group(): String => "integration"

  fun apply(h: TestHelper) =>
    let info = _RedisTestConfiguration(h.env.vars)
    let auth = lori.TCPConnectAuth(h.env.root)
    _PubSubPatternClient(h, auth, info.host, info.port)
    h.long_test(5_000_000_000)

actor \nodoc\ _PubSubPatternClient is
  (SessionStatusNotify & SubscriptionNotify & ResultReceiver)
  let _h: TestHelper
  var _done: Bool = false
  let _subscriber: Session
  let _publisher: Session
  var _ready_count: USize = 0

  new create(h: TestHelper, auth: lori.TCPConnectAuth,
    host: String, port: String)
  =>
    _h = h
    _subscriber = Session(ConnectInfo(auth, host, port), this)
    _publisher = Session(ConnectInfo(auth, host, port), this)
    h.dispose_when_done(_subscriber)
    h.dispose_when_done(_publisher)

  be redis_session_ready(session: Session) =>
    _ready_count = _ready_count + 1
    if _ready_count == 2 then
      let patterns: Array[String] val = ["_test_pubsub_p:*"]
      _subscriber.psubscribe(patterns, this)
    end

  be redis_psubscribed(session: Session, pattern: String,
    count: USize)
  =>
    let cmd: Array[ByteSeq] val =
      ["PUBLISH"; "_test_pubsub_p:foo"; "hello"]
    _publisher.execute(cmd, this)

  be redis_pmessage(session: Session, pattern: String,
    channel: String, data: Array[U8] val)
  =>
    if pattern != "_test_pubsub_p:*" then
      _h.fail("Expected pattern '_test_pubsub_p:*', got: '"
        + pattern + "'")
      _h.complete(false)
      return
    end
    if channel != "_test_pubsub_p:foo" then
      _h.fail("Expected channel '_test_pubsub_p:foo', got: '"
        + channel + "'")
      _h.complete(false)
      return
    end
    if String.from_array(data) != "hello" then
      _h.fail("Expected data 'hello', got: '"
        + String.from_array(data) + "'")
      _h.complete(false)
      return
    end
    let patterns: Array[String] val = ["_test_pubsub_p:*"]
    _subscriber.punsubscribe(patterns)

  be redis_punsubscribed(session: Session, pattern: String,
    count: USize)
  =>
    if count == 0 then
      _done = true
      _h.complete(true)
    end

  be redis_response(session: Session, response: RespValue) =>
    // PUBLISH response — ignore.
    None

  be redis_command_failed(session: Session,
    command: Array[ByteSeq] val, failure: ClientError)
  =>
    _h.fail("Command failed: " + failure.message())
    _h.complete(false)

  be redis_session_connection_failed(session: Session) =>
    _h.fail("Connection failed")
    _h.complete(false)

  be redis_session_closed(session: Session) =>
    if not _done then
      _h.fail("Session closed unexpectedly")
      _h.complete(false)
    end

// integration/Session/ExecuteWhileSubscribed

class \nodoc\ iso _TestSessionExecuteWhileSubscribed is UnitTest
  fun name(): String =>
    "integration/Session/ExecuteWhileSubscribed"

  fun exclusion_group(): String => "integration"

  fun apply(h: TestHelper) =>
    let info = _RedisTestConfiguration(h.env.vars)
    let auth = lori.TCPConnectAuth(h.env.root)
    let client = _ExecuteWhileSubscribedClient(h)
    let session = Session(
      ConnectInfo(auth, info.host, info.port),
      client)
    h.dispose_when_done(session)
    h.long_test(5_000_000_000)

actor \nodoc\ _ExecuteWhileSubscribedClient is
  (SessionStatusNotify & SubscriptionNotify & ResultReceiver)
  let _h: TestHelper
  var _done: Bool = false

  new create(h: TestHelper) =>
    _h = h

  be redis_session_ready(session: Session) =>
    let channels: Array[String] val = ["_test_exec_subscribed"]
    session.subscribe(channels, this)

  be redis_subscribed(session: Session, channel: String,
    count: USize)
  =>
    let cmd: Array[ByteSeq] val = ["PING"]
    session.execute(cmd, this)

  be redis_command_failed(session: Session,
    command: Array[ByteSeq] val, failure: ClientError)
  =>
    match failure
    | SessionInSubscribedMode =>
      // Clean up by unsubscribing.
      let channels: Array[String] val = ["_test_exec_subscribed"]
      session.unsubscribe(channels)
    else
      _h.fail("Expected SessionInSubscribedMode, got: "
        + failure.message())
      _h.complete(false)
    end

  be redis_unsubscribed(session: Session, channel: String,
    count: USize)
  =>
    if count == 0 then
      _done = true
      _h.complete(true)
    end

  be redis_response(session: Session, response: RespValue) =>
    _h.fail("Should not have received a response while subscribed")
    _h.complete(false)

  be redis_session_connection_failed(session: Session) =>
    _h.fail("Connection failed")
    _h.complete(false)

  be redis_session_closed(session: Session) =>
    if not _done then
      _h.fail("Session closed unexpectedly")
      _h.complete(false)
    end

// integration/Session/PubSubBackToReady

class \nodoc\ iso _TestSessionPubSubBackToReady is UnitTest
  fun name(): String =>
    "integration/Session/PubSubBackToReady"

  fun exclusion_group(): String => "integration"

  fun apply(h: TestHelper) =>
    let info = _RedisTestConfiguration(h.env.vars)
    let auth = lori.TCPConnectAuth(h.env.root)
    let client = _PubSubBackToReadyClient(h)
    let session = Session(
      ConnectInfo(auth, info.host, info.port),
      client)
    h.dispose_when_done(session)
    h.long_test(5_000_000_000)

actor \nodoc\ _PubSubBackToReadyClient is
  (SessionStatusNotify & SubscriptionNotify & ResultReceiver)
  let _h: TestHelper
  var _done: Bool = false
  var _was_subscribed: Bool = false

  new create(h: TestHelper) =>
    _h = h

  be redis_session_ready(session: Session) =>
    if _was_subscribed then
      // Second time ready — execute a command to verify.
      let cmd: Array[ByteSeq] val = ["PING"]
      session.execute(cmd, this)
    else
      // First time ready — subscribe.
      let channels: Array[String] val = ["_test_pubsub_back"]
      session.subscribe(channels, this)
    end

  be redis_subscribed(session: Session, channel: String,
    count: USize)
  =>
    _was_subscribed = true
    let channels: Array[String] val = ["_test_pubsub_back"]
    session.unsubscribe(channels)

  be redis_unsubscribed(session: Session, channel: String,
    count: USize)
  =>
    // Transition back to ready happens when count == 0.
    // redis_session_ready will fire and we verify with PING.
    None

  be redis_response(session: Session, response: RespValue) =>
    match response
    | let s: RespSimpleString =>
      if s.value == "PONG" then
        _done = true
        _h.complete(true)
      else
        _h.fail("Expected PONG, got: " + s.value)
        _h.complete(false)
      end
    else
      _h.fail("Expected RespSimpleString")
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

  be redis_session_closed(session: Session) =>
    if not _done then
      _h.fail("Session closed unexpectedly")
      _h.complete(false)
    end

// integration/Session/PipelineDrain

class \nodoc\ iso _TestSessionPipelineDrain is UnitTest
  fun name(): String =>
    "integration/Session/PipelineDrain"

  fun exclusion_group(): String => "integration"

  fun apply(h: TestHelper) =>
    let info = _RedisTestConfiguration(h.env.vars)
    let auth = lori.TCPConnectAuth(h.env.root)
    let client = _PipelineDrainClient(h)
    let session = Session(
      ConnectInfo(auth, info.host, info.port),
      client)
    h.dispose_when_done(session)
    h.long_test(5_000_000_000)

actor \nodoc\ _PipelineDrainClient is
  (SessionStatusNotify & SubscriptionNotify & ResultReceiver)
  let _h: TestHelper
  var _done: Bool = false
  var _step: USize = 0
  var _subscribed: Bool = false

  new create(h: TestHelper) =>
    _h = h

  be redis_session_ready(session: Session) =>
    if _subscribed then
      // Back to ready after unsubscribe — clean up test key.
      let del_cmd: Array[ByteSeq] val = ["DEL"; "_test_pipeline_drain"]
      session.execute(del_cmd, this)
    else
      // Pipeline commands, then subscribe before responses arrive.
      let set_cmd: Array[ByteSeq] val =
        ["SET"; "_test_pipeline_drain"; "drain_value"]
      session.execute(set_cmd, this)
      let get_cmd: Array[ByteSeq] val = ["GET"; "_test_pipeline_drain"]
      session.execute(get_cmd, this)
      let channels: Array[String] val = ["_test_pipeline_drain_ch"]
      session.subscribe(channels, this)
    end

  be redis_response(session: Session, response: RespValue) =>
    _step = _step + 1
    match _step
    | 1 =>
      // SET response — drained from pending in subscribed mode.
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
      // GET response — drained from pending in subscribed mode.
      match response
      | let b: RespBulkString =>
        let value = String.from_array(b.value)
        if value != "drain_value" then
          _h.fail("GET: expected 'drain_value', got: '" + value + "'")
          _h.complete(false)
        end
      else
        _h.fail("GET: expected RespBulkString")
        _h.complete(false)
      end
    | 3 =>
      // DEL response — done.
      _done = true
      _h.complete(true)
    else
      _h.fail("Unexpected response step: " + _step.string())
      _h.complete(false)
    end

  be redis_subscribed(session: Session, channel: String,
    count: USize)
  =>
    // Subscribe confirmation arrived after pending commands were drained.
    if channel != "_test_pipeline_drain_ch" then
      _h.fail("Expected channel '_test_pipeline_drain_ch', got: '"
        + channel + "'")
      _h.complete(false)
      return
    end
    _subscribed = true
    let channels: Array[String] val = ["_test_pipeline_drain_ch"]
    session.unsubscribe(channels)

  be redis_unsubscribed(session: Session, channel: String,
    count: USize)
  =>
    // When count reaches 0, session transitions back to ready.
    // redis_session_ready will fire and we clean up.
    None

  be redis_command_failed(session: Session,
    command: Array[ByteSeq] val, failure: ClientError)
  =>
    _h.fail("Command failed: " + failure.message())
    _h.complete(false)

  be redis_session_connection_failed(session: Session) =>
    _h.fail("Connection failed")
    _h.complete(false)

  be redis_session_closed(session: Session) =>
    if not _done then
      _h.fail("Session closed unexpectedly")
      _h.complete(false)
    end

// integration/Session/SSLConnectionFailure

class \nodoc\ iso _TestSessionSSLConnectionFailure is UnitTest
  fun name(): String =>
    "integration/Session/SSLConnectionFailure"

  fun exclusion_group(): String => "integration"

  fun apply(h: TestHelper) =>
    let auth = lori.TCPConnectAuth(h.env.root)
    // Connect with SSL to a port with nothing listening. This exercises
    // the SSL constructor path (Session calls ssl_client instead of
    // client) and verifies connection failure is reported through the
    // existing state machine. We don't connect to the Redis port because
    // SSL-to-plaintext causes a deadlock: the ClientHello has no \r\n
    // so Redis waits for more data, while SSL waits for a ServerHello.
    let host = ifdef linux then "127.0.0.2" else "localhost" end
    let sslctx: SSLContext val =
      recover val SSLContext end
    let session = Session(
      ConnectInfo(auth, host, "59873" where
        ssl_mode' = SSLRequired(sslctx)),
      _SSLConnectionFailureNotify(h))
    h.dispose_when_done(session)
    h.long_test(5_000_000_000)

actor \nodoc\ _SSLConnectionFailureNotify is SessionStatusNotify
  let _h: TestHelper
  var _done: Bool = false

  new create(h: TestHelper) =>
    _h = h

  be redis_session_connection_failed(session: Session) =>
    _done = true
    _h.complete(true)

  be redis_session_ready(session: Session) =>
    _h.fail("Should not have connected — nothing listening on port")
    _h.complete(false)

  be redis_session_closed(session: Session) =>
    if not _done then
      _h.fail("Session closed unexpectedly")
      _h.complete(false)
    end

// integration/Session/SSLConnectAndReady

class \nodoc\ iso _TestSessionSSLConnectAndReady is UnitTest
  fun name(): String =>
    "integration/Session/SSLConnectAndReady"

  fun exclusion_group(): String => "integration"

  fun apply(h: TestHelper) =>
    let info = _RedisTestConfiguration(h.env.vars)
    let auth = lori.TCPConnectAuth(h.env.root)
    let sslctx: SSLContext val =
      recover val
        SSLContext
          .> set_client_verify(false)
          .> set_server_verify(false)
      end
    let session = Session(
      ConnectInfo(auth, info.ssl_host, info.ssl_port where
        ssl_mode' = SSLRequired(sslctx)),
      _SSLConnectAndReadyNotify(h))
    h.dispose_when_done(session)
    h.long_test(5_000_000_000)

actor \nodoc\ _SSLConnectAndReadyNotify is SessionStatusNotify
  let _h: TestHelper
  var _done: Bool = false

  new create(h: TestHelper) =>
    _h = h

  be redis_session_ready(session: Session) =>
    _done = true
    _h.complete(true)

  be redis_session_connection_failed(session: Session) =>
    _h.fail("SSL connection failed")
    _h.complete(false)

  be redis_session_closed(session: Session) =>
    if not _done then
      _h.fail("Session closed unexpectedly")
      _h.complete(false)
    end

// integration/Session/SSLSetAndGet

class \nodoc\ iso _TestSessionSSLSetAndGet is UnitTest
  fun name(): String =>
    "integration/Session/SSLSetAndGet"

  fun exclusion_group(): String => "integration"

  fun apply(h: TestHelper) =>
    let info = _RedisTestConfiguration(h.env.vars)
    let auth = lori.TCPConnectAuth(h.env.root)
    let sslctx: SSLContext val =
      recover val
        SSLContext
          .> set_client_verify(false)
          .> set_server_verify(false)
      end
    let client = _SSLSetAndGetClient(h)
    let session = Session(
      ConnectInfo(auth, info.ssl_host, info.ssl_port where
        ssl_mode' = SSLRequired(sslctx)),
      client)
    h.dispose_when_done(session)
    h.long_test(5_000_000_000)

actor \nodoc\ _SSLSetAndGetClient is (SessionStatusNotify & ResultReceiver)
  let _h: TestHelper
  var _done: Bool = false
  var _step: USize = 0

  new create(h: TestHelper) =>
    _h = h

  be redis_session_ready(session: Session) =>
    let set_cmd: Array[ByteSeq] val =
      ["SET"; "_test_ssl_set_and_get"; "hello_ssl"]
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
      let get_cmd: Array[ByteSeq] val = ["GET"; "_test_ssl_set_and_get"]
      session.execute(get_cmd, this)
    elseif _step == 2 then
      // GET response — should be bulk string "hello_ssl"
      match response
      | let b: RespBulkString =>
        let value = String.from_array(b.value)
        if value != "hello_ssl" then
          _h.fail("Expected 'hello_ssl', got: '" + value + "'")
          _h.complete(false)
          return
        end
      else
        _h.fail("Expected RespBulkString from GET")
        _h.complete(false)
        return
      end
      // Clean up test key
      let del_cmd: Array[ByteSeq] val = ["DEL"; "_test_ssl_set_and_get"]
      session.execute(del_cmd, this)
    else
      // DEL response — done
      _done = true
      _h.complete(true)
    end

  be redis_command_failed(session: Session,
    command: Array[ByteSeq] val, failure: ClientError)
  =>
    _h.fail("Command failed: " + failure.message())
    _h.complete(false)

  be redis_session_connection_failed(session: Session) =>
    _h.fail("SSL connection failed")
    _h.complete(false)

  be redis_session_closed(session: Session) =>
    if not _done then
      _h.fail("Session closed unexpectedly")
      _h.complete(false)
    end

// integration/Session/Resp3ConnectAndReady

class \nodoc\ iso _TestSessionResp3ConnectAndReady is UnitTest
  fun name(): String =>
    "integration/Session/Resp3ConnectAndReady"

  fun exclusion_group(): String => "integration"

  fun apply(h: TestHelper) =>
    let info = _RedisTestConfiguration(h.env.vars)
    let auth = lori.TCPConnectAuth(h.env.root)
    let session = Session(
      ConnectInfo(auth, info.host, info.port where protocol' = Resp3),
      _Resp3ConnectAndReadyNotify(h))
    h.dispose_when_done(session)
    h.long_test(5_000_000_000)

actor \nodoc\ _Resp3ConnectAndReadyNotify is SessionStatusNotify
  let _h: TestHelper
  var _done: Bool = false

  new create(h: TestHelper) =>
    _h = h

  be redis_session_ready(session: Session) =>
    _done = true
    _h.complete(true)

  be redis_session_connection_failed(session: Session) =>
    _h.fail("Connection failed")
    _h.complete(false)

  be redis_session_closed(session: Session) =>
    if not _done then
      _h.fail("Session closed unexpectedly")
      _h.complete(false)
    end

// integration/Session/Resp3SetAndGet

class \nodoc\ iso _TestSessionResp3SetAndGet is UnitTest
  fun name(): String =>
    "integration/Session/Resp3SetAndGet"

  fun exclusion_group(): String => "integration"

  fun apply(h: TestHelper) =>
    let info = _RedisTestConfiguration(h.env.vars)
    let auth = lori.TCPConnectAuth(h.env.root)
    let client = _Resp3SetAndGetClient(h)
    let session = Session(
      ConnectInfo(auth, info.host, info.port where protocol' = Resp3),
      client)
    h.dispose_when_done(session)
    h.long_test(5_000_000_000)

actor \nodoc\ _Resp3SetAndGetClient is (SessionStatusNotify & ResultReceiver)
  let _h: TestHelper
  var _done: Bool = false
  var _step: USize = 0

  new create(h: TestHelper) =>
    _h = h

  be redis_session_ready(session: Session) =>
    let set_cmd: Array[ByteSeq] val =
      ["SET"; "_test_resp3_set_and_get"; "hello_resp3"]
    session.execute(set_cmd, this)

  be redis_response(session: Session, response: RespValue) =>
    _step = _step + 1
    if _step == 1 then
      // SET response
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
      let get_cmd: Array[ByteSeq] val =
        ["GET"; "_test_resp3_set_and_get"]
      session.execute(get_cmd, this)
    elseif _step == 2 then
      // GET response
      match response
      | let b: RespBulkString =>
        let value = String.from_array(b.value)
        if value != "hello_resp3" then
          _h.fail("Expected 'hello_resp3', got: '" + value + "'")
          _h.complete(false)
          return
        end
      else
        _h.fail("Expected RespBulkString from GET")
        _h.complete(false)
        return
      end
      let del_cmd: Array[ByteSeq] val =
        ["DEL"; "_test_resp3_set_and_get"]
      session.execute(del_cmd, this)
    else
      // DEL response — done
      _done = true
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

  be redis_session_closed(session: Session) =>
    if not _done then
      _h.fail("Session closed unexpectedly")
      _h.complete(false)
    end

// integration/Session/Resp3FallbackToResp2

class \nodoc\ iso _TestSessionResp3FallbackToResp2 is UnitTest
  fun name(): String =>
    "integration/Session/Resp3FallbackToResp2"

  fun exclusion_group(): String => "integration"

  fun apply(h: TestHelper) =>
    let info = _RedisTestConfiguration(h.env.vars)
    let auth = lori.TCPConnectAuth(h.env.root)
    let client = _Resp3FallbackClient(h)
    let session = Session(
      ConnectInfo(auth, info.resp2_host, info.resp2_port
        where protocol' = Resp3),
      client)
    h.dispose_when_done(session)
    h.long_test(5_000_000_000)

actor \nodoc\ _Resp3FallbackClient is (SessionStatusNotify & ResultReceiver)
  let _h: TestHelper
  var _done: Bool = false
  var _step: USize = 0

  new create(h: TestHelper) =>
    _h = h

  be redis_session_ready(session: Session) =>
    let set_cmd: Array[ByteSeq] val =
      ["SET"; "_test_resp3_fallback"; "hello_fallback"]
    session.execute(set_cmd, this)

  be redis_response(session: Session, response: RespValue) =>
    _step = _step + 1
    if _step == 1 then
      // SET response
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
      let get_cmd: Array[ByteSeq] val =
        ["GET"; "_test_resp3_fallback"]
      session.execute(get_cmd, this)
    elseif _step == 2 then
      // GET response
      match response
      | let b: RespBulkString =>
        let value = String.from_array(b.value)
        if value != "hello_fallback" then
          _h.fail("Expected 'hello_fallback', got: '" + value + "'")
          _h.complete(false)
          return
        end
      else
        _h.fail("Expected RespBulkString from GET")
        _h.complete(false)
        return
      end
      let del_cmd: Array[ByteSeq] val =
        ["DEL"; "_test_resp3_fallback"]
      session.execute(del_cmd, this)
    else
      // DEL response — done
      _done = true
      _h.complete(true)
    end

  be redis_command_failed(session: Session,
    command: Array[ByteSeq] val, failure: ClientError)
  =>
    _h.fail("Command failed: " + failure.message())
    _h.complete(false)

  be redis_session_connection_failed(session: Session) =>
    _h.fail("Connection to RESP2-only server failed")
    _h.complete(false)

  be redis_session_closed(session: Session) =>
    if not _done then
      _h.fail("Session closed unexpectedly")
      _h.complete(false)
    end

// integration/CommandApi/SetAndGet

class \nodoc\ iso _TestCommandApiSetAndGet is UnitTest
  fun name(): String =>
    "integration/CommandApi/SetAndGet"

  fun exclusion_group(): String => "integration"

  fun apply(h: TestHelper) =>
    let info = _RedisTestConfiguration(h.env.vars)
    let auth = lori.TCPConnectAuth(h.env.root)
    let client = _CommandApiSetAndGetClient(h)
    let session = Session(
      ConnectInfo(auth, info.host, info.port),
      client)
    h.dispose_when_done(session)
    h.long_test(5_000_000_000)

actor \nodoc\ _CommandApiSetAndGetClient is
  (SessionStatusNotify & ResultReceiver)
  let _h: TestHelper
  var _done: Bool = false
  var _step: USize = 0

  new create(h: TestHelper) =>
    _h = h

  be redis_session_ready(session: Session) =>
    session.execute(RedisString.set("_test_cmd_api", "hello_api"), this)

  be redis_response(session: Session, response: RespValue) =>
    _step = _step + 1
    if _step == 1 then
      // SET response — verify with RespConvert.is_ok
      if not RespConvert.is_ok(response) then
        _h.fail("Expected OK from SET")
        _h.complete(false)
        return
      end
      session.execute(RedisString.get("_test_cmd_api"), this)
    elseif _step == 2 then
      // GET response — verify with RespConvert.as_string
      match RespConvert.as_string(response)
      | let value: String =>
        if value != "hello_api" then
          _h.fail("Expected 'hello_api', got: '" + value + "'")
          _h.complete(false)
          return
        end
      else
        _h.fail("Expected string from GET")
        _h.complete(false)
        return
      end
      let del_keys: Array[String] val = ["_test_cmd_api"]
      session.execute(RedisKey.del(del_keys), this)
    else
      // DEL response — done
      _done = true
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

  be redis_session_closed(session: Session) =>
    if not _done then
      _h.fail("Session closed unexpectedly")
      _h.complete(false)
    end

// BuildHelloCommand

class \nodoc\ iso _TestBuildHelloCommand is UnitTest
  fun name(): String => "BuildHelloCommand"

  fun apply(h: TestHelper) ? =>
    let auth = lori.TCPConnectAuth(h.env.root)

    // No password: ["HELLO"; "3"]
    let no_pw = ConnectInfo(auth, "localhost" where protocol' = Resp3)
    let cmd1 = _BuildHelloCommand(no_pw)
    h.assert_eq[USize](2, cmd1.size())
    _assert_byteseq(h, "HELLO", cmd1(0)?)
    _assert_byteseq(h, "3", cmd1(1)?)

    // Password, no username: ["HELLO"; "3"; "AUTH"; "default"; "secret"]
    let pw_no_user = ConnectInfo(auth, "localhost"
      where password' = "secret", protocol' = Resp3)
    let cmd2 = _BuildHelloCommand(pw_no_user)
    h.assert_eq[USize](5, cmd2.size())
    _assert_byteseq(h, "HELLO", cmd2(0)?)
    _assert_byteseq(h, "3", cmd2(1)?)
    _assert_byteseq(h, "AUTH", cmd2(2)?)
    _assert_byteseq(h, "default", cmd2(3)?)
    _assert_byteseq(h, "secret", cmd2(4)?)

    // Password + username: ["HELLO"; "3"; "AUTH"; "myuser"; "secret"]
    let pw_user = ConnectInfo(auth, "localhost"
      where password' = "secret", username' = "myuser", protocol' = Resp3)
    let cmd3 = _BuildHelloCommand(pw_user)
    h.assert_eq[USize](5, cmd3.size())
    _assert_byteseq(h, "HELLO", cmd3(0)?)
    _assert_byteseq(h, "3", cmd3(1)?)
    _assert_byteseq(h, "AUTH", cmd3(2)?)
    _assert_byteseq(h, "myuser", cmd3(3)?)
    _assert_byteseq(h, "secret", cmd3(4)?)

  fun _assert_byteseq(h: TestHelper, expected: String, actual: ByteSeq) =>
    match actual
    | let s: String val =>
      h.assert_eq[String](expected, s)
    | let a: Array[U8] val =>
      h.assert_eq[String](expected, String.from_array(a))
    end

// BuildAuthCommand

class \nodoc\ iso _TestBuildAuthCommand is UnitTest
  fun name(): String => "BuildAuthCommand"

  fun apply(h: TestHelper) ? =>
    // No username: ["AUTH"; "secret"]
    let cmd1 = _BuildAuthCommand(None, "secret")
    h.assert_eq[USize](2, cmd1.size())
    _assert_byteseq(h, "AUTH", cmd1(0)?)
    _assert_byteseq(h, "secret", cmd1(1)?)

    // With username: ["AUTH"; "myuser"; "secret"]
    let cmd2 = _BuildAuthCommand("myuser", "secret")
    h.assert_eq[USize](3, cmd2.size())
    _assert_byteseq(h, "AUTH", cmd2(0)?)
    _assert_byteseq(h, "myuser", cmd2(1)?)
    _assert_byteseq(h, "secret", cmd2(2)?)

  fun _assert_byteseq(h: TestHelper, expected: String, actual: ByteSeq) =>
    match actual
    | let s: String val =>
      h.assert_eq[String](expected, s)
    | let a: Array[U8] val =>
      h.assert_eq[String](expected, String.from_array(a))
    end
