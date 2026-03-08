{{/*
Generate scheduling spec (nodeSelector, tolerations, affinity, topologySpreadConstraints)
Arguments: dict with keys:
  - "values": component values (e.g., .Values.prometheus)
  - "global": .Values.global
  - "component": component name string
  - "fullname": release fullname
*/}}
{{- define "obs.scheduling" -}}
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
{{- end }}
{{- /* Topology spread constraints */ -}}
{{- if $scheduling.topologySpreadConstraints }}
topologySpreadConstraints:
  {{- toYaml $scheduling.topologySpreadConstraints | nindent 2 }}
{{- end }}
{{- end -}}
