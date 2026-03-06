{{/*
Secret lookup-or-create helper.
If an existing secret exists in the cluster and the value is not explicitly set,
preserve the existing secret data on upgrade.
*/}}
{{- define "countly.secret.value" -}}
{{- $secretName := index . "secretName" -}}
{{- $key := index . "key" -}}
{{- $value := index . "value" -}}
{{- $namespace := index . "namespace" -}}
{{- if $value -}}
{{ $value | b64enc }}
{{- else -}}
{{- $existing := lookup "v1" "Secret" $namespace $secretName -}}
{{- if $existing -}}
{{ index $existing.data $key }}
{{- else -}}
{{- fail (printf "Secret '%s' key '%s' has no value and no existing secret found in namespace '%s'. Set the value or create the secret before installing." $secretName $key $namespace) -}}
{{- end -}}
{{- end -}}
{{- end -}}
