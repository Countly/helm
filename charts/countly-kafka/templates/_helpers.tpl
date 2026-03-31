{{/*
Expand the name of the chart.
*/}}
{{- define "countly-kafka.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "countly-kafka.fullname" -}}
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
{{- define "countly-kafka.labels" -}}
helm.sh/chart: {{ include "countly-kafka.chart" . }}
{{ include "countly-kafka.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Chart label
*/}}
{{- define "countly-kafka.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "countly-kafka.selectorLabels" -}}
app.kubernetes.io/name: {{ include "countly-kafka.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Kafka bootstrap servers computation
*/}}
{{- define "countly-kafka.bootstrapServers" -}}
{{- if .Values.kafkaConnect.bootstrapServers -}}
{{ .Values.kafkaConnect.bootstrapServers }}
{{- else -}}
{{ include "countly-kafka.fullname" . }}-kafka-bootstrap:9092
{{- end -}}
{{- end -}}

{{/*
KafkaConnect cluster name
*/}}
{{- define "countly-kafka.connectName" -}}
{{- .Values.kafkaConnect.name | default (printf "%s-connect" (include "countly-kafka.fullname" .)) -}}
{{- end -}}

{{/*
ClickHouse Connect host computation
*/}}
{{- define "countly-kafka.clickhouseHost" -}}
{{- if .Values.kafkaConnect.clickhouse.host -}}
{{ .Values.kafkaConnect.clickhouse.host }}
{{- else -}}
countly-clickhouse-clickhouse-headless.{{ .Values.clickhouseNamespace | default "clickhouse" }}.svc.cluster.local
{{- end -}}
{{- end -}}

{{/*
ArgoCD sync-wave annotation (only when argocd.enabled).
Usage: {{- include "countly-kafka.syncWave" (dict "wave" "5" "root" .) | nindent 4 }}
*/}}
{{- define "countly-kafka.syncWave" -}}
{{- if .root.Values.argocd.enabled }}
argocd.argoproj.io/sync-wave: {{ .wave | quote }}
{{- end }}
{{- end -}}

{{/*
ClickHouse Connect secret name
*/}}
{{- define "countly-kafka.clickhouseSecretName" -}}
{{- if .Values.kafkaConnect.clickhouse.existingSecret -}}
{{ .Values.kafkaConnect.clickhouse.existingSecret }}
{{- else -}}
{{ .Values.kafkaConnect.clickhouse.secretName }}
{{- end -}}
{{- end -}}

{{/*
Resolve the Kafka Connect image based on the selected source mode.
*/}}
{{- define "countly-kafka.connectImage" -}}
{{- $mode := .Values.global.imageSource.mode | default "direct" -}}
{{- if eq $mode "gcpArtifactRegistry" -}}
{{- $prefix := required "global.imageSource.gcpArtifactRegistry.repositoryPrefix is required when global.imageSource.mode is gcpArtifactRegistry" .Values.global.imageSource.gcpArtifactRegistry.repositoryPrefix -}}
{{- printf "%s/%s" ($prefix | trimSuffix "/") .Values.kafkaConnect.artifactImage -}}
{{- else -}}
{{- .Values.kafkaConnect.image -}}
{{- end -}}
{{- end -}}

{{/*
Resolve the first configured imagePullSecret name.
*/}}
{{- define "countly-kafka.imagePullSecretName" -}}
{{- $pullSecrets := .Values.global.imagePullSecrets | default list -}}
{{- if gt (len $pullSecrets) 0 -}}
{{- (index $pullSecrets 0).name -}}
{{- end -}}
{{- end -}}
