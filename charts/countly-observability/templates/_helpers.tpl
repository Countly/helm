{{/*
Expand the name of the chart.
*/}}
{{- define "obs.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "obs.fullname" -}}
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
{{- define "obs.labels" -}}
helm.sh/chart: {{ include "obs.chart" . }}
{{ include "obs.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Chart label
*/}}
{{- define "obs.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "obs.selectorLabels" -}}
app.kubernetes.io/name: {{ include "obs.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Component labels — adds app.kubernetes.io/component
*/}}
{{- define "obs.componentLabels" -}}
{{ include "obs.labels" . }}
app.kubernetes.io/component: {{ .component }}
{{- end }}

{{/*
Component selector labels
*/}}
{{- define "obs.componentSelectorLabels" -}}
{{ include "obs.selectorLabels" . }}
app.kubernetes.io/component: {{ .component }}
{{- end }}

{{/* ============================================================
    DEPLOYMENT CONDITIONALS
    ============================================================ */}}

{{- define "obs.deployPrometheus" -}}
{{- if and .Values.metrics.enabled (ne .Values.mode "external") }}true{{- end }}
{{- end }}

{{- define "obs.deployLoki" -}}
{{- if and .Values.logs.enabled (ne .Values.mode "external") }}true{{- end }}
{{- end }}

{{- define "obs.deployTempo" -}}
{{- if and .Values.traces.enabled (ne .Values.mode "external") }}true{{- end }}
{{- end }}

{{- define "obs.deployPyroscope" -}}
{{- if and .Values.profiling.enabled (ne .Values.mode "external") }}true{{- end }}
{{- end }}

{{- define "obs.deployGrafana" -}}
{{- if and .Values.grafana.enabled (eq .Values.mode "full") }}true{{- end }}
{{- end }}

{{- define "obs.deployAlloy" -}}
{{- if .Values.logs.enabled }}true{{- end }}
{{- end }}

{{- define "obs.deployAlloyOtlp" -}}
{{- if or .Values.traces.enabled .Values.profiling.enabled }}true{{- end }}
{{- end }}

{{- define "obs.deployAlloyMetrics" -}}
{{- if .Values.metrics.enabled }}true{{- end }}
{{- end }}

{{- define "obs.deployKSM" -}}
{{- if and .Values.metrics.enabled .Values.kubeStateMetrics.enabled }}true{{- end }}
{{- end }}

{{- define "obs.deployNodeExporter" -}}
{{- if and .Values.metrics.enabled .Values.nodeExporter.enabled }}true{{- end }}
{{- end }}

{{/* ============================================================
    AUTO-WIRING URL HELPERS
    ============================================================ */}}

{{/*
Prometheus remote write URL
*/}}
{{- define "obs.prometheus.remoteWriteUrl" -}}
{{- if eq .Values.mode "external" -}}
{{ .Values.prometheus.external.remoteWriteUrl }}
{{- else -}}
http://{{ include "obs.fullname" . }}-prometheus.{{ .Release.Namespace }}.svc.cluster.local:9090/api/v1/write
{{- end -}}
{{- end }}

{{/*
Prometheus query URL (in-cluster only)
*/}}
{{- define "obs.prometheus.url" -}}
http://{{ include "obs.fullname" . }}-prometheus.{{ .Release.Namespace }}.svc.cluster.local:9090
{{- end }}

{{/*
Loki push URL
*/}}
{{- define "obs.loki.pushUrl" -}}
{{- if eq .Values.mode "external" -}}
{{ .Values.loki.external.pushUrl }}
{{- else -}}
http://{{ include "obs.fullname" . }}-loki.{{ .Release.Namespace }}.svc.cluster.local:3100/loki/api/v1/push
{{- end -}}
{{- end }}

{{/*
Loki query URL (in-cluster only)
*/}}
{{- define "obs.loki.url" -}}
http://{{ include "obs.fullname" . }}-loki.{{ .Release.Namespace }}.svc.cluster.local:3100
{{- end }}

{{/*
Tempo OTLP gRPC endpoint
*/}}
{{- define "obs.tempo.otlpGrpcEndpoint" -}}
{{- if eq .Values.mode "external" -}}
{{ .Values.tempo.external.otlpGrpcEndpoint }}
{{- else -}}
{{ include "obs.fullname" . }}-tempo.{{ .Release.Namespace }}.svc.cluster.local:4317
{{- end -}}
{{- end }}

{{/*
Tempo HTTP URL (in-cluster only)
*/}}
{{- define "obs.tempo.httpUrl" -}}
http://{{ include "obs.fullname" . }}-tempo.{{ .Release.Namespace }}.svc.cluster.local:3200
{{- end }}

{{/*
Tempo gRPC URL (in-cluster only, for streaming search)
*/}}
{{- define "obs.tempo.grpcUrl" -}}
{{ include "obs.fullname" . }}-tempo.{{ .Release.Namespace }}.svc.cluster.local:9095
{{- end }}

{{/*
Pyroscope URL
*/}}
{{- define "obs.pyroscope.url" -}}
{{- if eq .Values.mode "external" -}}
{{ .Values.pyroscope.external.ingestUrl }}
{{- else -}}
http://{{ include "obs.fullname" . }}-pyroscope.{{ .Release.Namespace }}.svc.cluster.local:4040
{{- end -}}
{{- end }}

{{/*
Alloy OTLP endpoint (points to alloy-otlp Deployment)
*/}}
{{- define "obs.alloy.otlpEndpoint" -}}
http://{{ include "obs.fullname" . }}-alloy-otlp.{{ .Release.Namespace }}.svc.cluster.local:4318
{{- end }}

{{/*
Alloy Pyroscope push endpoint (points to alloy-otlp Deployment)
*/}}
{{- define "obs.alloy.pyroscopeEndpoint" -}}
http://{{ include "obs.fullname" . }}-alloy-otlp.{{ .Release.Namespace }}.svc.cluster.local:9999
{{- end }}

{{/*
Image helper — prepends global registry if set
*/}}
{{- define "obs.image" -}}
{{- $registry := .global.imageRegistry | default "" -}}
{{- if $registry -}}
{{ $registry }}/{{ .image.repository }}:{{ .image.tag }}
{{- else -}}
{{ .image.repository }}:{{ .image.tag }}
{{- end -}}
{{- end }}

{{/*
Storage class helper — component > global fallback
*/}}
{{- define "obs.storageClass" -}}
{{- $sc := .componentSC | default .globalSC -}}
{{- if $sc }}
storageClassName: {{ $sc }}
{{- end }}
{{- end }}

{{/* ============================================================
    OBJECT STORAGE HELPERS
    ============================================================ */}}

{{/*
Returns "true" if backend is an object storage provider (not filesystem/local).
Args: dict "backend" <value> "default" <default>
*/}}
{{- define "obs.usesObjectStorage" -}}
{{- $b := .backend | default .default -}}
{{- if and (ne $b "filesystem") (ne $b "local") }}true{{- end }}
{{- end }}

{{/*
Returns "true" when backend is object storage AND existingSecret is set.
Args: dict "storage" <storage-values> "default" <default>
*/}}
{{- define "obs.shouldMountCredentialSecret" -}}
{{- $b := .storage.backend | default .default -}}
{{- if and (include "obs.usesObjectStorage" (dict "backend" $b "default" .default)) .storage.existingSecret }}true{{- end }}
{{- end }}

{{/*
Validation helper — calls fail() on invalid storage config.
Args: dict "component" <name> "storage" <storage-values> "default" <default> "allowed" <list>
*/}}
{{- define "obs.storageValidation" -}}
{{- $b := .storage.backend | default .default -}}
{{- if not (has $b .allowed) -}}
{{- fail (printf "%s.storage.backend must be one of: %s (got: %s)" .component (join ", " .allowed) $b) -}}
{{- end -}}
{{- if and (include "obs.usesObjectStorage" (dict "backend" $b "default" .default)) (not .storage.bucket) -}}
{{- fail (printf "%s.storage.bucket is required when using object storage (backend: %s)" .component $b) -}}
{{- end -}}
{{- if and (eq $b "s3") .storage.forcePathStyle (not .storage.endpoint) -}}
{{- fail (printf "%s.storage.forcePathStyle requires storage.endpoint (used for S3-compatible endpoints like MinIO)" .component) -}}
{{- end -}}
{{- end }}
