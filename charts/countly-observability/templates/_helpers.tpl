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
{{- if or .Values.logs.enabled .Values.traces.enabled .Values.profiling.enabled }}true{{- end }}
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
Alloy OTLP endpoint (always in-cluster)
*/}}
{{- define "obs.alloy.otlpEndpoint" -}}
http://{{ include "obs.fullname" . }}-alloy.{{ .Release.Namespace }}.svc.cluster.local:4318
{{- end }}

{{/*
Alloy Pyroscope push endpoint (always in-cluster)
*/}}
{{- define "obs.alloy.pyroscopeEndpoint" -}}
http://{{ include "obs.fullname" . }}-alloy.{{ .Release.Namespace }}.svc.cluster.local:9999
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
