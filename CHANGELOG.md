# Changelog

All notable changes to the Countly Helm Charts will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]


### Changed
- improvements for actions
- (countly,countly-clickhouse,countly-kafka,countly-mongodb,countly-observability,profiles,environments,docs,helmfile) restructure repo: composable profiles
- (countly-observability,profiles,environments) fixes for bucketing and calcs
- (countly-kafka,countly-observability,environments) nginx trace passing
- (countly-observability) polishing to dashboards
- (countly-kafka,countly-observability) fixes for dashboards
- (profiles,environments) Integrate OpenTelemetry across Helm charts: add support for Kafka, ClickHouse, and Tempo spans, enable NGINX and Kafka Connect instrumentation, and update configurations for observability stack.
- (countly,countly-clickhouse,countly-kafka,countly-mongodb,countly-observability) Add OpenTelemetry support to Countly Helm charts: enable instrumentation and tracing for Kafka, ClickHouse, and Tempo; configure MongoDB exporter deployment.
- (countly,countly-clickhouse,countly-kafka,countly-mongodb,countly-observability,profiles,environments,docs) Remove ClickHouse Comprehensive Monitoring dashboard from Countly Observability chart.
- (countly,countly-clickhouse,countly-kafka,countly-mongodb,countly-observability,profiles,environments,docs,helmfile) Delete local, reference, and tier1 Helm values files; deprecate environment-specific configurations.
- (environments,docs) Update observability stack: introduce Alloy-OTLP Deployment for OTLP traces and profiling, enhance sampling strategies, add retention settings for components, configure object storage, and include smoke test script.
- (countly,countly-observability) Refactor observability chart: split Alloy into dedicated components for logs (DaemonSet), OTLP traces, and profiling (Deployment); update sampling options, object storage configurations, and documentation.
- (countly-kafka) Update Countly Kafka chart with worker configuration settings and align Strimzi API version to v1
- (countly,countly-observability,environments,docs,helmfile) Add observability Helm chart for metrics, logs, traces, and profiling; update documentation and configuration examples
- (countly,environments) Reduce health check `initialDelaySeconds` to 30s for Countly services across all Helm configurations.
- (environments) Update Countly Helm chart configurations with production-ready defaults; document YAML key conflicts and enhance component-level settings
- (countly,docs) Add TLS overlay examples and streamline TLS configuration documentation
- (docs) Add F5 NGINX Ingress Controller and transition from community ingress-nginx; document TLS configurations and update version matrix
- (countly) Update NGINX ingress annotations to align with F5 NGINX Ingress Controller standards; add optional self-signed TLS certificate generation
- (environments,docs) Update Strimzi to 0.51.0, Kafka to 4.2.0, and MongoDB to 8.2.5; replace MongoDB Community Operator with MCK and update instructions
- (countly-mongodb) Update Countly MongoDB chart to use appVersion 8.2.5
- (countly-kafka) Update Countly Kafka chart to use appVersion 4.2.0 and update Kafka Connect image version
- (countly-clickhouse) Update ClickHouse version to 26.2 and increase default persistence size to 50Gi
- (environments) Update versions for Strimzi Kafka Operator, ClickHouse, and Kafka charts
- (docs) Update Strimzi Kafka Operator version to 0.49.1 in PREREQUISITES.md
- (countly-mongodb) Add resource policy to MongoDBCommunity resource in Countly MongoDB chart
- (countly-kafka) Add resource policies to KafkaNodePool resources in Countly Kafka chart
- (countly-clickhouse) Add resource policies to ClickHouse and Keeper clusters
- (countly,countly-kafka,environments,docs) Add MongoDB namespace configuration, enforce password requirements, and enhance documentation with troubleshooting and deployment guides.
- initial working version

