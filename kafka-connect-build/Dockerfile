ARG KAFKA_VERSION=4.2.0
ARG CH_SINK_VERSION=1.3.5
ARG STRIMZI_VERSION=0.51.0
ARG OTEL_AGENT_VERSION=2.12.0

FROM quay.io/strimzi/kafka:${STRIMZI_VERSION}-kafka-${KAFKA_VERSION}
USER root:root
ARG CH_SINK_VERSION
ARG OTEL_AGENT_VERSION
ARG PLUGINS_DIR=/opt/kafka/plugins
RUN microdnf -y install unzip && microdnf clean all && \
    mkdir -p ${PLUGINS_DIR}/clickhouse && \
    curl -fSL https://github.com/ClickHouse/clickhouse-kafka-connect/releases/download/v${CH_SINK_VERSION}/clickhouse-kafka-connect-v${CH_SINK_VERSION}.zip \
      -o /tmp/ch-sink.zip && \
    unzip -q /tmp/ch-sink.zip -d ${PLUGINS_DIR}/clickhouse && \
    rm -f /tmp/ch-sink.zip && \
    # OpenTelemetry Java agent — activated only when JAVA_TOOL_OPTIONS is set
    mkdir -p /opt/otel && \
    curl -fSL https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/download/v${OTEL_AGENT_VERSION}/opentelemetry-javaagent.jar \
      -o /opt/otel/opentelemetry-javaagent.jar
USER 1001
