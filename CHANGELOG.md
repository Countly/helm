# Changelog

All notable changes to the Countly Helm Charts will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- Initial release of all 5 Helm charts
  - countly: Countly web analytics platform
  - countly-mongodb: MongoDB via MongoDB Community Operator
  - countly-clickhouse: ClickHouse via ClickHouse Operator
  - countly-kafka: Kafka for event streaming via Strimzi Operator
  - countly-observability: Full observability stack (Prometheus, Grafana, Loki, Tempo, Pyroscope)
- Composable profile system: sizing, observability, kafka-connect, tls
- Helmfile-based deployment orchestration
- Comprehensive documentation
