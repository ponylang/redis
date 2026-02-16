FROM redis:7

LABEL org.opencontainers.image.source="https://github.com/ponylang/redis"

RUN apt-get update && apt-get install -y --no-install-recommends openssl && \
    rm -rf /var/lib/apt/lists/* && \
    mkdir -p /tls && \
    openssl req -new -x509 -days 3650 -nodes \
      -out /tls/redis.crt -keyout /tls/redis.key \
      -subj '/CN=localhost' && \
    chmod 600 /tls/redis.key

CMD ["redis-server", "--tls-port", "6379", "--port", "0", \
     "--tls-cert-file", "/tls/redis.crt", \
     "--tls-key-file", "/tls/redis.key", \
     "--tls-auth-clients", "no"]
