{{/*
Generate scheduling spec (nodeSelector, tolerations, affinity, topologySpreadConstraints)
Arguments: dict with keys:
  - "values": component values (e.g., .Values.api)
  - "global": .Values.global
  - "component": component name string
  - "fullname": release fullname
  - "extraAffinity": optional additional affinity rules
*/}}
{{- define "countly.scheduling" -}}
{{- $values := .values -}}
{{- $global := .global -}}
{{- $component := .component -}}
{{- $fullname := .fullname -}}
{{- $scheduling := $values.scheduling | default dict -}}
{{- $globalScheduling := $global.scheduling | default dict -}}
{{- /* Merge nodeSelector */ -}}
{{- $nodeSelector := merge ($scheduling.nodeSelector | default dict) ($globalScheduling.nodeSelector | default dict) -}}
{{- if $nodeSelector }}
nodeSelector:
  {{- toYaml $nodeSelector | nindent 2 }}
{{- end }}
{{- /* Merge tolerations */ -}}
{{- $tolerations := concat ($globalScheduling.tolerations | default list) ($scheduling.tolerations | default list) -}}
{{- if $tolerations }}
tolerations:
  {{- toYaml $tolerations | nindent 2 }}
{{- end }}
{{- /* Affinity: user-provided overrides everything, otherwise generate anti-affinity */ -}}
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
            app.kubernetes.io/name: {{ $fullname }}
            app.kubernetes.io/component: {{ $component }}
        topologyKey: {{ $topologyKey }}
    {{- else }}
    preferredDuringSchedulingIgnoredDuringExecution:
      - weight: {{ $weight }}
        podAffinityTerm:
          labelSelector:
            matchLabels:
              app.kubernetes.io/name: {{ $fullname }}
              app.kubernetes.io/component: {{ $component }}
          topologyKey: {{ $topologyKey }}
    {{- end }}
  {{- if .extraAffinity }}
  {{- toYaml .extraAffinity | nindent 2 }}
  {{- end }}
{{- else if .extraAffinity }}
affinity:
  {{- toYaml .extraAffinity | nindent 2 }}
{{- end }}
{{- end }}
{{- /* Topology spread constraints */ -}}
{{- if $scheduling.topologySpreadConstraints }}
topologySpreadConstraints:
  {{- toYaml $scheduling.topologySpreadConstraints | nindent 2 }}
{{- end }}
{{- end -}}
