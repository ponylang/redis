# redis

A Redis client for Pony. Speaks RESP2 and RESP3, with pub/sub and pipelined commands.

<!-- contributor-only -->
## Contributing with an AI assistant

This is a Pony project. The ponylang org maintains a set of LLM coding skills. Get set up with them before contributing:

- **Not set up yet?** Install them once:

  ```bash
  git clone https://github.com/ponylang/llm-skills.git
  cd llm-skills
  python install.py
  ```

- **Already set up?** Make sure you're on the latest. If you installed with the script above, `git pull` in the directory where you cloned `llm-skills` and the symlinked skills update automatically — if you set them up another way, refresh them however that setup expects.

See the [llm-skills README](https://github.com/ponylang/llm-skills) for details and other harnesses.

When you start working on this project, load the `pony-skills` skill — it tells your assistant which Pony skill to use for each task.

Read [CONTRIBUTING.md](CONTRIBUTING.md).
<!-- /contributor-only -->

## Building and testing

```
make ssl=3.0.x                       # build + run all tests (needs Redis running)
make unit-tests ssl=3.0.x            # unit tests only (no Redis needed)
make test-one t=TestName ssl=3.0.x   # run a single test by name
make integration-tests ssl=3.0.x     # integration tests only (needs Redis)
make examples ssl=3.0.x              # build examples
make start-redis                     # start plaintext, SSL, and RESP2-only Redis in Docker
make stop-redis                      # stop and remove them
make clean                           # clean build artifacts
```

`ssl=` is required on build targets (lori pulls in `ssl`): for example `ssl=3.0.x` for OpenSSL 3.x, `ssl=libressl` for LibreSSL. Add `config=debug` for a debug build.

Run the integration tests locally with `make start-redis`, then `make test ssl=3.0.x`, then `make stop-redis`. They read `REDIS_*` environment variables (see `_RedisTestConfiguration`), which default to `127.0.0.2` on Linux rather than the usual loopback, dodging the WSL2 mirrored-networking hang.

## Architecture

The `Session` actor is the entry point. It tracks connection and pub/sub lifecycle with explicit state classes, all in `session.pony`.

```
_SessionUnopened ──on_connected──► _SessionNegotiating (if Resp3)
                 ──on_connected──► _SessionConnected (if Resp2 + password)
                 ──on_connected──► _SessionReady (if Resp2, no password)
                 ──on_failure──► _SessionClosed

_SessionNegotiating ──HELLO map──► _SessionReady
                    ──HELLO error──► _SessionConnected (if password, send AUTH)
                    ──HELLO error──► _SessionReady (if no password)

_SessionConnected ──AUTH OK──► _SessionReady
                  ──AUTH error──► _SessionClosed

_SessionReady ──subscribe/psubscribe──► _SessionSubscribed
              ──close/error──► _SessionClosed

_SessionSubscribed ──unsub count 0──► _SessionReady
                   ──close/error──► _SessionClosed
```

## Testing

- **Never connect with SSL to a plaintext Redis server, even in a test.** The TLS ClientHello carries no `\r\n`, so Redis's RESP parser buffers it forever waiting for a line terminator while the SSL client waits for a ServerHello — both block indefinitely. To exercise the SSL constructor path, connect to a non-listening port instead; connection-refused is fast and deterministic.
- Backpressure tests use a fake server built on lori's listener/connection APIs, because real Redis fill rates vary by environment. The fake listener must track the connections it spawns and dispose them in `_on_closed()`, or the test hangs.
- Integration tests are named `integration/…` and set `exclusion_group() => "integration"`; they need a running Redis.

## Conventions

- Impossible states call `_IllegalState()` / `_Unreachable()` (`_mort.pony`).
- `\nodoc\` on test classes.
