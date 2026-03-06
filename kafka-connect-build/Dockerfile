ARG KAFKA_VERSION=4.2.0
ARG CH_SINK_VERSION=1.3.5
ARG STRIMZI_VERSION=0.51.0

FROM quay.io/strimzi/kafka:${STRIMZI_VERSION}-kafka-${KAFKA_VERSION}
USER root:root
ARG CH_SINK_VERSION
ARG PLUGINS_DIR=/opt/kafka/plugins
RUN microdnf -y install unzip && microdnf clean all && \
    mkdir -p ${PLUGINS_DIR}/clickhouse && \
    curl -fSL https://github.com/ClickHouse/clickhouse-kafka-connect/releases/download/v${CH_SINK_VERSION}/clickhouse-kafka-connect-v${CH_SINK_VERSION}.zip \
      -o /tmp/ch-sink.zip && \
    unzip -q /tmp/ch-sink.zip -d ${PLUGINS_DIR}/clickhouse && \
    rm -f /tmp/ch-sink.zip
USER 1001
