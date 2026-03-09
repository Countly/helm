{{/*
Expand the name of the chart.
*/}}
{{- define "countly-clickhouse.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "countly-clickhouse.fullname" -}}
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
{{- define "countly-clickhouse.labels" -}}
helm.sh/chart: {{ include "countly-clickhouse.chart" . }}
{{ include "countly-clickhouse.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Chart label
*/}}
{{- define "countly-clickhouse.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "countly-clickhouse.selectorLabels" -}}
app.kubernetes.io/name: {{ include "countly-clickhouse.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Scheduling helper for ClickHouse components
Arguments: dict with keys:
  - "values": component values (server or keeper)
  - "global": .Values.global
  - "component": component name string
  - "fullname": release fullname
*/}}
{{- define "countly-clickhouse.scheduling" -}}
{{- $values := .values -}}
{{- $global := .global -}}
{{- $component := .component -}}
{{- $scheduling := $values.scheduling | default dict -}}
{{- $globalScheduling := $global.scheduling | default dict -}}
{{- $nodeSelector := merge ($scheduling.nodeSelector | default dict) ($globalScheduling.nodeSelector | default dict) -}}
{{- if $nodeSelector }}
nodeSelector:
  {{- toYaml $nodeSelector | nindent 2 }}
{{- end }}
{{- $tolerations := concat ($globalScheduling.tolerations | default list) ($scheduling.tolerations | default list) -}}
{{- if $tolerations }}
tolerations:
  {{- toYaml $tolerations | nindent 2 }}
{{- end }}
{{- if $scheduling.affinity }}
affinity:
  {{- toYaml $scheduling.affinity | nindent 2 }}
{{- else }}
{{- $antiAffinity := $scheduling.antiAffinity | default dict -}}
{{- if (and (hasKey $antiAffinity "enabled") $antiAffinity.enabled) }}
affinity:
  podAntiAffinity:
    {{- $type := $antiAffinity.type | default "preferred" -}}
    {{- $topologyKey := $antiAffinity.topologyKey | default "kubernetes.io/hostname" -}}
    {{- $weight := $antiAffinity.weight | default 100 -}}
    {{- if eq $type "required" }}
    requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchLabels:
            clickhouse.com/role: {{ $component }}
        topologyKey: {{ $topologyKey }}
    {{- else }}
    preferredDuringSchedulingIgnoredDuringExecution:
      - weight: {{ $weight }}
        podAffinityTerm:
          labelSelector:
            matchLabels:
              clickhouse.com/role: {{ $component }}
          topologyKey: {{ $topologyKey }}
    {{- end }}
{{- end }}
{{- end }}
{{- if $scheduling.topologySpreadConstraints }}
topologySpreadConstraints:
  {{- toYaml $scheduling.topologySpreadConstraints | nindent 2 }}
{{- end }}
{{- end -}}

{{/*
Password secret name for ClickHouse default user
*/}}
{{- define "countly-clickhouse.passwordSecretName" -}}
{{- if .Values.auth.defaultUserPassword.existingSecret -}}
{{ .Values.auth.defaultUserPassword.existingSecret }}
{{- else -}}
{{ .Values.auth.defaultUserPassword.secretName }}
{{- end -}}
{{- end -}}
