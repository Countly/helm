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
ClickHouse URL computation.
Reads from backingServices.clickhouse; falls back to in-cluster DNS.
*/}}
{{- define "countly.clickhouse.url" -}}
{{- $bs := (.Values.backingServices).clickhouse | default dict -}}
{{- $host := $bs.host -}}
{{- $port := $bs.port | default "8123" -}}
{{- $tls := $bs.tls | default "false" -}}
{{- $scheme := ternary "https" "http" (eq (toString $tls) "true") -}}
{{- if $host -}}
{{ $scheme }}://{{ $host }}:{{ $port }}
{{- else -}}
{{ $scheme }}://{{ .Release.Name }}-clickhouse-clickhouse-headless.{{ .Values.clickhouseNamespace | default "clickhouse" }}.svc:{{ $port }}
{{- end -}}
{{- end -}}

{{/*
Kafka brokers computation.
Reads from backingServices.kafka; falls back to in-cluster DNS.
*/}}
{{- define "countly.kafka.brokers" -}}
{{- $bs := (.Values.backingServices).kafka | default dict -}}
{{- $brokers := $bs.brokers -}}
{{- if $brokers -}}
{{ $brokers }}
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
Resolve the effective hostname.
*/}}
{{- define "countly.hostname" -}}
{{- .Values.ingress.hostname | default "countly.example.com" -}}
{{- end -}}

{{/*
TLS mode resolution.
Returns: letsencrypt, existingSecret, selfSigned, or http.
*/}}
{{- define "countly.tls.mode" -}}
{{- ((.Values.ingress).tls).mode | default "http" -}}
{{- end -}}

{{/*
Effective TLS secret name.
*/}}
{{- define "countly.tls.secretName" -}}
{{- ((.Values.ingress).tls).secretName | default (printf "%s-tls" (include "countly.fullname" .)) -}}
{{- end -}}

{{/*
Escape MongoDB URI user-info values safely.
urlquery handles reserved characters but encodes spaces as "+", which is
query-style encoding. Replace "+" with "%20" so the result is safe in URI
user-info segments too.
*/}}
{{- define "countly.mongodb.escapeUserInfo" -}}
{{- . | urlquery | replace "+" "%20" -}}
{{- end -}}

{{/*
MongoDB connection string computation.
Reads from backingServices.mongodb; constructs from service DNS if not provided.
*/}}
{{- define "countly.mongodb.connectionString" -}}
{{- $bs := (.Values.backingServices).mongodb | default dict -}}
{{- $connStr := $bs.connectionString -}}
{{- if $connStr -}}
{{- $connStr -}}
{{- else -}}
{{- $pass := $bs.password | default .Values.secrets.mongodb.password -}}
{{- if not $pass -}}
{{- fail "MongoDB password is required. Set backingServices.mongodb.password or secrets.mongodb.password." -}}
{{- end -}}
{{- $host := $bs.host | default (printf "%s-mongodb-svc.%s.svc.cluster.local" .Release.Name (.Values.mongodbNamespace | default "mongodb")) -}}
{{- $port := $bs.port | default "27017" -}}
{{- $user := $bs.username | default "app" -}}
{{- $db := $bs.database | default "admin" -}}
{{- $rs := $bs.replicaSet | default (printf "%s-mongodb" .Release.Name) -}}
mongodb://{{ include "countly.mongodb.escapeUserInfo" $user }}:{{ include "countly.mongodb.escapeUserInfo" $pass }}@{{ $host }}:{{ $port }}/{{ $db }}?replicaSet={{ $rs }}&ssl=false
{{- end -}}
{{- end -}}

{{/*
MongoDB connection string computation using an explicit password value.
Used by ExternalSecret templates where the password may come from the secret backend.
*/}}
{{- define "countly.mongodb.connectionStringWithPassword" -}}
{{- $root := .root -}}
{{- $pass := .password -}}
{{- $bs := ($root.Values.backingServices).mongodb | default dict -}}
{{- $connStr := $bs.connectionString -}}
{{- if $connStr -}}
{{- $connStr -}}
{{- else -}}
{{- if not $pass -}}
{{- fail "MongoDB password is required. Set backingServices.mongodb.password, secrets.mongodb.password, or secrets.externalSecret.remoteRefs.mongodb.password." -}}
{{- end -}}
{{- $host := $bs.host | default (printf "%s-mongodb-svc.%s.svc.cluster.local" $root.Release.Name ($root.Values.mongodbNamespace | default "mongodb")) -}}
{{- $port := $bs.port | default "27017" -}}
{{- $user := $bs.username | default "app" -}}
{{- $db := $bs.database | default "admin" -}}
{{- $rs := $bs.replicaSet | default (printf "%s-mongodb" $root.Release.Name) -}}
mongodb://{{ include "countly.mongodb.escapeUserInfo" $user }}:{{ $pass }}@{{ $host }}:{{ $port }}/{{ $db }}?replicaSet={{ $rs }}&ssl=false
{{- end -}}
{{- end -}}

{{/*
Kafka Connect API URL computation.
Reads from backingServices.kafka.connectApiUrl; falls back to in-cluster DNS.
*/}}
{{- define "countly.kafka.connectApiUrl" -}}
{{- $bs := (.Values.backingServices).kafka | default dict -}}
{{- if $bs.connectApiUrl -}}
{{ $bs.connectApiUrl }}
{{- else -}}
http://{{ .Values.config.kafka.COUNTLY_CONFIG__KAFKA_CONNECTCONSUMERGROUPID | default "connect-ch" }}-connect-api.{{ .Values.kafkaNamespace | default "kafka" }}.svc.cluster.local:8083
{{- end -}}
{{- end -}}

{{/*
Validate backing service configuration.
Called from NOTES.txt to surface errors during install.
*/}}
{{- define "countly.validateBackingServices" -}}
{{- $bs := .Values.backingServices | default dict -}}
{{- if eq (($bs.mongodb | default dict).mode | default "bundled") "external" -}}
  {{- $connStr := ($bs.mongodb).connectionString -}}
  {{- $host := ($bs.mongodb).host -}}
  {{- $existingSecret := ($bs.mongodb).existingSecret -}}
  {{- if not (or $connStr $host $existingSecret) -}}
    {{- fail "backingServices.mongodb.mode is 'external' but no host, connectionString, or existingSecret provided" -}}
  {{- end -}}
{{- end -}}
{{- if eq (($bs.clickhouse | default dict).mode | default "bundled") "external" -}}
  {{- $host := ($bs.clickhouse).host -}}
  {{- $existingSecret := ($bs.clickhouse).existingSecret -}}
  {{- if not (or $host $existingSecret) -}}
    {{- fail "backingServices.clickhouse.mode is 'external' but no host or existingSecret provided" -}}
  {{- end -}}
{{- end -}}
{{- if eq (($bs.kafka | default dict).mode | default "bundled") "external" -}}
  {{- $brokers := ($bs.kafka).brokers -}}
  {{- $existingSecret := ($bs.kafka).existingSecret -}}
  {{- if not (or $brokers $existingSecret) -}}
    {{- fail "backingServices.kafka.mode is 'external' but no brokers or existingSecret provided" -}}
  {{- end -}}
{{- end -}}
{{- end -}}

{{/*
ArgoCD sync-wave annotation (only when argocd.enabled).
*/}}
{{- define "countly.syncWave" -}}
{{- if .root.Values.argocd.enabled }}
argocd.argoproj.io/sync-wave: {{ .wave | quote }}
{{- end }}
{{- end -}}

{{/*
Resolve the first configured imagePullSecret name.
*/}}
{{- define "countly.imagePullSecretName" -}}
{{- $pullSecrets := .Values.global.imagePullSecrets | default list -}}
{{- if gt (len $pullSecrets) 0 -}}
{{- (index $pullSecrets 0).name -}}
{{- end -}}
{{- end -}}
