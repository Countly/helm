# Kafka Connect ClickHouse Image

Custom Kafka Connect image with the ClickHouse Sink Connector plugin.

## Build

```bash
docker build \
  --build-arg STRIMZI_VERSION=0.49.1 \
  --build-arg KAFKA_VERSION=4.1.1 \
  --build-arg CH_SINK_VERSION=1.3.5 \
  -t myregistry/kafka-connect-clickhouse:1.3.5 .
```

## Push

```bash
docker push myregistry/kafka-connect-clickhouse:1.3.5
```

## Version Matrix

See `../docs/VERSION-MATRIX.md` for known-good version combinations.
