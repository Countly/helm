# Kafka Connect ClickHouse Image

Custom Kafka Connect image with the ClickHouse Sink Connector plugin.
Uses vanilla Apache Kafka from eclipse-temurin (no Strimzi dependency).

## Build

```bash
docker build \
  --build-arg KAFKA_VERSION=4.2.0 \
  --build-arg CH_SINK_VERSION=1.3.5 \
  -t myregistry/kafka-connect-clickhouse:4.2.0-1.3.5 .
```

## Push

```bash
docker push myregistry/kafka-connect-clickhouse:4.2.0-1.3.5
```

## Version Matrix

See `../docs/VERSION-MATRIX.md` for known-good version combinations.
