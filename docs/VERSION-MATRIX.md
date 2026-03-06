# Version Matrix

Known-good operator and image version combinations.

| Strimzi | Apache Kafka | CH Sink Connector | ClickHouse | ClickHouse Operator | cert-manager | MongoDB | MongoDB Operator | Status |
|---------|-------------|-------------------|------------|---------------------|--------------|---------|------------------|--------|
| 0.47.0 | 4.0.0 | 1.3.5 | 25.8 | 0.0.2 | 1.17.2 | 8.0.13 | 0.13.0 | **Current** |

## Notes

- **Strimzi** moves fast and may drop older Kafka version support. Pin deliberately and test upgrades.
- **ClickHouse Operator** uses `clickhouse.com/v1alpha1` CRDs. The `clickhouseOperator.apiVersion` value allows overriding when the operator graduates.
- **MongoDB Community Operator** generates connection string secrets automatically.
- CR `apiVersion` fields are configurable in each chart's values for forward compatibility.
