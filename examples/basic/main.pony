use "../../redis"

actor Main
  new create(env: Env) =>
    env.out.print("Redis client example")
