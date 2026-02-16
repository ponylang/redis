interface tag SubscriptionNotify
  """
  Receives pub/sub events: subscription confirmations, incoming messages,
  and unsubscription confirmations. All callbacks have default no-op
  implementations, so consumers only need to override the events they
  care about.

  When a subscribed session closes (voluntarily or due to error), this
  interface receives no notification — messages simply stop arriving.
  Implement `SessionStatusNotify` alongside this interface to detect
  connection loss during subscribed mode.
  """
  be redis_subscribed(session: Session, channel: String, count: USize) =>
    """
    Called when a channel subscription is confirmed by the server. The
    count is the total number of active subscriptions (channels and
    patterns combined).
    """
    None

  be redis_unsubscribed(session: Session, channel: String, count: USize) =>
    """
    Called when a channel unsubscription is confirmed by the server. The
    count is the total number of remaining active subscriptions. When
    count reaches 0, the session exits subscribed mode and
    `redis_session_ready` fires on the `SessionStatusNotify`.
    """
    None

  be redis_message(session: Session, channel: String,
    data: Array[U8] val)
  =>
    """
    Called when a message is received on a subscribed channel. The data
    is raw bytes because Redis pub/sub messages can contain arbitrary
    binary data.
    """
    None

  be redis_psubscribed(session: Session, pattern: String,
    count: USize)
  =>
    """
    Called when a pattern subscription is confirmed by the server. The
    count is the total number of active subscriptions (channels and
    patterns combined).
    """
    None

  be redis_punsubscribed(session: Session, pattern: String,
    count: USize)
  =>
    """
    Called when a pattern unsubscription is confirmed by the server. The
    count is the total number of remaining active subscriptions. When
    count reaches 0, the session exits subscribed mode and
    `redis_session_ready` fires on the `SessionStatusNotify`.
    """
    None

  be redis_pmessage(session: Session, pattern: String, channel: String,
    data: Array[U8] val)
  =>
    """
    Called when a message is received matching a subscribed pattern. The
    pattern is the glob that matched, the channel is the actual channel
    the message was published to, and the data is raw bytes.
    """
    None
