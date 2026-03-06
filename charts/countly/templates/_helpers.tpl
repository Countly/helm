{{/*
Expand the name of the chart.
*/}}
{{- define "countly.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "countly.fullname" -}}
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
{{- define "countly.labels" -}}
helm.sh/chart: {{ include "countly.chart" . }}
{{ include "countly.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Chart label
*/}}
{{- define "countly.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "countly.selectorLabels" -}}
app.kubernetes.io/name: {{ include "countly.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Service account name
*/}}
{{- define "countly.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "countly.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
ClickHouse URL computation
*/}}
{{- define "countly.clickhouse.url" -}}
{{- $scheme := ternary "https" "http" (eq (toString (.Values.secrets.clickhouse.tls | default "false")) "true") -}}
{{- if .Values.secrets.clickhouse.host -}}
{{ $scheme }}://{{ .Values.secrets.clickhouse.host }}:{{ .Values.secrets.clickhouse.port }}
{{- else -}}
{{ $scheme }}://{{ .Release.Name }}-clickhouse-clickhouse-headless.{{ .Values.clickhouseNamespace | default "clickhouse" }}.svc:{{ .Values.secrets.clickhouse.port }}
{{- end -}}
{{- end -}}

{{/*
Kafka brokers computation
*/}}
{{- define "countly.kafka.brokers" -}}
{{- if .Values.secrets.kafka.brokers -}}
{{ .Values.secrets.kafka.brokers }}
{{- else -}}
["{{ .Release.Name }}-kafka-kafka-bootstrap.{{ .Values.kafkaNamespace | default "kafka" }}.svc:9092"]
{{- end -}}
{{- end -}}

{{/*
MongoDB secret name
*/}}
{{- define "countly.mongodb.secretName" -}}
{{- .Values.secrets.mongodb.existingSecret | default (printf "%s-mongodb" (include "countly.fullname" .)) -}}
{{- end -}}

{{/*
MongoDB connection string computation
Constructs from service DNS if not provided explicitly, matching the ClickHouse/Kafka pattern.
*/}}
{{- define "countly.mongodb.connectionString" -}}
{{- if .Values.secrets.mongodb.connectionString -}}
{{ .Values.secrets.mongodb.connectionString }}
{{- else -}}
{{- $host := .Values.secrets.mongodb.host | default (printf "countly-mongodb-svc.mongodb.svc.cluster.local") -}}
{{- $port := .Values.secrets.mongodb.port | default "27017" -}}
{{- $user := .Values.secrets.mongodb.username | default "app" -}}
{{- $pass := .Values.secrets.mongodb.password -}}
{{- $db := .Values.secrets.mongodb.database | default "admin" -}}
{{- $rs := .Values.secrets.mongodb.replicaSet | default "countly-mongodb" -}}
mongodb://{{ $user }}:{{ $pass }}@{{ $host }}:{{ $port }}/{{ $db }}?replicaSet={{ $rs }}&ssl=false
{{- end -}}
{{- end -}}
