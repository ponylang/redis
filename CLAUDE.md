# Redis Client for Pony

## Building

```
make          # build and run tests
make test     # same as above
make clean    # clean build artifacts
```

## Architecture

Package: `redis`

### RESP2 Protocol Layer

- `RespValue` (union type in `resp_value.pony`): Core type for RESP2 wire format values. Union of `RespSimpleString`, `RespBulkString`, `RespInteger`, `RespArray`, `RespError`, `RespNull`.
- `RespMalformed` (in `resp_value.pony`): Parser error type indicating invalid RESP data. Not part of `RespValue` — represents a protocol violation, not a valid value.
- `_RespParser` (in `_resp_parser.pony`): Two-pass parser — peek-based completeness check, then destructive parse. Returns `(RespValue | None | RespMalformed)` from a `buffered.Reader`.
- `_RespSerializer` (in `_resp_serializer.pony`): Serializes commands (`Array[ByteSeq] val`) to RESP2 wire format.

## File Layout

- `redis/` — main package source
- `examples/` — example programs
