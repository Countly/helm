{{/*
Expand the name of the chart.
*/}}
{{- define "countly-migration.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "countly-migration.fullname" -}}
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
{{- define "countly-migration.labels" -}}
helm.sh/chart: {{ include "countly-migration.chart" . }}
{{ include "countly-migration.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Chart label
*/}}
{{- define "countly-migration.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "countly-migration.selectorLabels" -}}
app.kubernetes.io/name: {{ include "countly-migration.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Service account name
*/}}
{{- define "countly-migration.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "countly-migration.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
ArgoCD sync-wave annotation (only when argocd.enabled).
Usage: include "countly-migration.syncWave" (dict "wave" "0" "root" .)
*/}}
{{- define "countly-migration.syncWave" -}}
{{- if ((.root.Values.argocd).enabled) }}
argocd.argoproj.io/sync-wave: {{ .wave | quote }}
{{- end }}
{{- end -}}

{{/*
Secret name resolution across three modes.
*/}}
{{- define "countly-migration.secretName" -}}
{{- if eq (.Values.secrets.mode | default "values") "existingSecret" }}
{{- required "secrets.existingSecret.name is required when secrets.mode=existingSecret" .Values.secrets.existingSecret.name }}
{{- else }}
{{- include "countly-migration.fullname" . }}
{{- end }}
{{- end }}

{{/*
MongoDB URI computation.
External mode: use provided URI directly.
Bundled mode: construct from sibling countly-mongodb chart DNS.
*/}}
{{- define "countly-migration.mongoUri" -}}
{{- $bs := .Values.backingServices.mongodb -}}
{{- if eq ($bs.mode | default "bundled") "external" -}}
{{- required "backingServices.mongodb.uri is required when mode=external" $bs.uri -}}
{{- else -}}
{{- $prefix := $bs.releaseName | default "countly" -}}
{{- $host := $bs.host | default (printf "%s-mongodb-svc.%s.svc.cluster.local" $prefix ($bs.namespace | default "mongodb")) -}}
{{- $port := $bs.port | default "27017" -}}
{{- $user := $bs.username | default "app" -}}
{{- $pass := required "backingServices.mongodb.password is required when mode=bundled" $bs.password -}}
{{- $db := $bs.database | default "admin" -}}
{{- $rs := $bs.replicaSet | default (printf "%s-mongodb" $prefix) -}}
mongodb://{{ $user }}:{{ $pass }}@{{ $host }}:{{ $port }}/{{ $db }}?replicaSet={{ $rs }}&ssl=false
{{- end -}}
{{- end -}}

{{/*
ClickHouse URL computation.
External mode: use provided URL directly.
Bundled mode: construct from sibling countly-clickhouse chart DNS.
*/}}
{{- define "countly-migration.clickhouseUrl" -}}
{{- $bs := .Values.backingServices.clickhouse -}}
{{- if eq ($bs.mode | default "bundled") "external" -}}
{{- required "backingServices.clickhouse.url is required when mode=external" $bs.url -}}
{{- else -}}
{{- $prefix := $bs.releaseName | default "countly" -}}
{{- $host := $bs.host | default (printf "%s-clickhouse-clickhouse-headless.%s.svc" $prefix ($bs.namespace | default "clickhouse")) -}}
{{- $port := $bs.port | default "8123" -}}
{{- $tls := $bs.tls | default "false" -}}
{{- $scheme := ternary "https" "http" (eq (toString $tls) "true") -}}
{{- $scheme }}://{{ $host }}:{{ $port }}
{{- end -}}
{{- end -}}

{{/*
Redis URL computation.
If backingServices.redis.url is set, use it.
If redis subchart is enabled, auto-wire to the subchart service.
*/}}
{{- define "countly-migration.redisUrl" -}}
{{- if .Values.backingServices.redis.url -}}
{{- .Values.backingServices.redis.url -}}
{{- else if .Values.redis.enabled -}}
redis://{{ include "countly-migration.fullname" . }}-redis-master:6379
{{- end -}}
{{- end -}}

{{/*
Image reference with tag defaulting to "latest".
*/}}
{{- define "countly-migration.image" -}}
{{- $tag := .Values.image.tag | default "latest" -}}
{{ .Values.image.repository }}:{{ $tag }}
{{- end }}
