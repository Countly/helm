{{/*
Expand the name of the chart.
*/}}
{{- define "countly-argocd.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "countly-argocd.fullname" -}}
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
{{- define "countly-argocd.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
app.kubernetes.io/name: {{ include "countly-argocd.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
ArgoCD project name — unique per release to prevent multi-tenant collisions.
*/}}
{{- define "countly-argocd.projectName" -}}
{{- .Values.project | default (include "countly-argocd.fullname" .) }}
{{- end -}}

{{/*
Sync policy block — reused by all Application templates.
Includes retry policy for resilience at scale (100+ customers = 600+ Applications).
*/}}
{{- define "countly-argocd.syncPolicy" -}}
syncPolicy:
  {{- if .Values.syncPolicy.automated }}
  automated:
    prune: {{ .Values.syncPolicy.prune }}
    selfHeal: {{ .Values.syncPolicy.selfHeal }}
  {{- end }}
  syncOptions:
    - CreateNamespace=true
    - ServerSideApply=true
    - RespectIgnoreDifferences=true
  retry:
    limit: {{ .Values.syncPolicy.retry.limit }}
    backoff:
      duration: {{ .Values.syncPolicy.retry.backoff.duration }}
      factor: {{ .Values.syncPolicy.retry.backoff.factor }}
      maxDuration: {{ .Values.syncPolicy.retry.backoff.maxDuration }}
{{- end -}}
