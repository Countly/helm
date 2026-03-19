{{/*
Expand the name of the chart.
*/}}
{{- define "countly-migrations.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "countly-migrations.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "countly-migrations.labels" -}}
helm.sh/chart: {{ include "countly-migrations.chart" . }}
{{ include "countly-migrations.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Chart label
*/}}
{{- define "countly-migrations.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "countly-migrations.selectorLabels" -}}
app.kubernetes.io/name: {{ include "countly-migrations.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Kafka bootstrap servers computation
*/}}
{{- define "countly-migrations.bootstrapServers" -}}
{{ include "countly-migrations.fullname" . }}-kafka-bootstrap:9092
{{- end -}}

{{/*
KafkaConnect source cluster name
*/}}
{{- define "countly-migrations.connectSrcName" -}}
{{- .Values.connectSrc.name | default (printf "%s-connect-src" (include "countly-migrations.fullname" .)) -}}
{{- end -}}

{{/*
KafkaConnect sink cluster name
*/}}
{{- define "countly-migrations.connectSinkName" -}}
{{- .Values.connectSink.name | default (printf "%s-connect-sink" (include "countly-migrations.fullname" .)) -}}
{{- end -}}

{{/*
ClickHouse secret name (supports existingSecret)
*/}}
{{- define "countly-migrations.clickhouseSecretName" -}}
{{- if .Values.clickhouse.existingSecret -}}
{{ .Values.clickhouse.existingSecret }}
{{- else -}}
{{ .Values.clickhouse.secretName }}
{{- end -}}
{{- end -}}

{{/*
Storage class name for a component.
Falls back to storageClass.name, then global.storageClass.
Usage: {{ include "countly-migrations.storageClassName" (dict "component" .Values.brokers.persistence "root" .) }}
*/}}
{{- define "countly-migrations.storageClassName" -}}
{{- if .component.storageClass -}}
{{ .component.storageClass }}
{{- else if .root.Values.storageClass.name -}}
{{ .root.Values.storageClass.name }}
{{- else -}}
{{ .root.Values.global.storageClass }}
{{- end -}}
{{- end -}}

{{/*
ArgoCD sync-wave annotation (only when argocd.enabled).
Usage: {{- include "countly-migrations.syncWave" (dict "wave" "5" "root" .) | nindent 4 }}
*/}}
{{- define "countly-migrations.syncWave" -}}
{{- if .root.Values.argocd.enabled }}
argocd.argoproj.io/sync-wave: {{ .wave | quote }}
{{- end }}
{{- end -}}

{{/*
Resolve connector state: per-connector override > global migration.state.
Usage: {{ include "countly-migrations.connectorState" (dict "connector" .Values.connectors.source "global" .Values.migration) }}
*/}}
{{- define "countly-migrations.connectorState" -}}
{{- if .connector.state -}}
{{ .connector.state }}
{{- else -}}
{{ .global.state }}
{{- end -}}
{{- end -}}

{{/*
Resolve deleteClaim: migration.deleteClaim overrides per-component setting.
*/}}
{{- define "countly-migrations.deleteClaim" -}}
{{- if .Values.migration.deleteClaim -}}
true
{{- else -}}
false
{{- end -}}
{{- end -}}
