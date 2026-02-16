use "cli"
use lori = "lori"
// in your code this `use` statement would be:
// use "redis"
use "../../redis"

actor Main
  new create(env: Env) =>
    let info = ServerInfo(env.vars)
    let auth = lori.TCPConnectAuth(env.root)
    PubSubDemo(auth, info, env.out)

actor PubSubDemo is
  (SessionStatusNotify & SubscriptionNotify & ResultReceiver)
  let _subscriber: Session
  let _publisher: Session
  let _out: OutStream
  var _subscriber_ready: Bool = false
  var _publisher_ready: Bool = false

  new create(auth: lori.TCPConnectAuth, info: ServerInfo,
    out: OutStream)
  =>
    _out = out
    _subscriber = Session(
      ConnectInfo(auth, info.host, info.port),
      this)
    _publisher = Session(
      ConnectInfo(auth, info.host, info.port),
      this)

  be redis_session_ready(session: Session) =>
    if session is _subscriber then
      _subscriber_ready = true
    elseif session is _publisher then
      _publisher_ready = true
    end
    if _subscriber_ready and _publisher_ready then
      _out.print("Both sessions ready. Subscribing to 'demo-channel'...")
      let channels: Array[String] val = ["demo-channel"]
      _subscriber.subscribe(channels, this)
    end

  be redis_subscribed(session: Session, channel: String,
    count: USize)
  =>
    _out.print("Subscribed to '" + channel + "' (active: "
      + count.string() + ")")
    _out.print("Publishing a message...")
    let cmd: Array[ByteSeq] val =
      ["PUBLISH"; "demo-channel"; "Hello from Pony!"]
    _publisher.execute(cmd, this)

  be redis_message(session: Session, channel: String,
    data: Array[U8] val)
  =>
    _out.print("Received message on '" + channel + "': "
      + String.from_array(data))
    _out.print("Unsubscribing...")
    let channels: Array[String] val = ["demo-channel"]
    _subscriber.unsubscribe(channels)

  be redis_unsubscribed(session: Session, channel: String,
    count: USize)
  =>
    _out.print("Unsubscribed from '" + channel + "' (remaining: "
      + count.string() + ")")
    _subscriber.close()
    _publisher.close()

  be redis_session_connection_failed(session: Session) =>
    _out.print("Failed to connect.")

  be redis_response(session: Session, response: RespValue) =>
    match response
    | let i: RespInteger =>
      _out.print("Message delivered to " + i.value.string()
        + " subscriber(s).")
    end

  be redis_command_failed(session: Session,
    command: Array[ByteSeq] val, failure: ClientError)
  =>
    _out.print("Command failed: " + failure.message())

class val ServerInfo
  let host: String
  let port: String

  new val create(vars: (Array[String] val | None)) =>
    let e = EnvVars(vars)
    host = try e("REDIS_HOST")? else
      ifdef linux then "127.0.0.2" else "localhost" end
    end
    port = try e("REDIS_PORT")? else "6379" end
