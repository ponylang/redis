## Fix send() return value checks in negotiation code paths

Previously, when the session sent HELLO (for RESP3 negotiation) or AUTH (for password authentication) immediately after TCP connection, the return value from the underlying TCP send was not checked. If the send failed, the session would hang indefinitely in a negotiating or authenticating state, waiting for a server response to a command that was never sent.

Now, all negotiation send paths check the result. If the send fails, the session shuts down cleanly and fires `redis_session_closed`.
