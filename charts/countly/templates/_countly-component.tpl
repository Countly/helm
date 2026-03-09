{{/*
Countly Component Macro
Renders Deployment + Service + HPA + PDB for a Countly microservice.
Arguments (dict):
  - "root": the root context (.)
  - "component": component name (api, frontend, ingestor, aggregator, jobserver)
  - "values": component-specific values (e.g., .Values.api)
  - "configmaps": list of configmap names to mount as envFrom
  - "secrets": list of secret names to mount as envFrom
  - "extraAffinity": optional extra affinity rules (e.g., podAffinity for frontend)
*/}}
{{- define "countly.component.deployment" -}}
{{- $root := .root -}}
{{- $component := .component -}}
{{- $values := .values -}}
{{- $fullname := include "countly.fullname" $root -}}
{{- if $values.enabled }}
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ $fullname }}-{{ $component }}
  labels:
    {{- include "countly.labels" $root | nindent 4 }}
    app.kubernetes.io/component: {{ $component }}
spec:
  {{- if not $values.hpa.enabled }}
  replicas: {{ $values.replicaCount }}
  {{- end }}
  selector:
    matchLabels:
      {{- include "countly.selectorLabels" $root | nindent 6 }}
      app.kubernetes.io/component: {{ $component }}
  template:
    metadata:
      annotations:
        checksum/config-common: {{ include (print $root.Template.BasePath "/configmap-common.yaml") $root | sha256sum }}
        checksum/config-component: {{ include (print $root.Template.BasePath "/configmap-" $component ".yaml") $root | sha256sum }}
        checksum/config-clickhouse: {{ include (print $root.Template.BasePath "/configmap-clickhouse.yaml") $root | sha256sum }}
        checksum/config-kafka: {{ include (print $root.Template.BasePath "/configmap-kafka.yaml") $root | sha256sum }}
        checksum/config-otel: {{ include (print $root.Template.BasePath "/configmap-otel.yaml") $root | sha256sum }}
        {{- if $root.Values.secrets.rotationId }}
        countly.io/rotation-id: {{ $root.Values.secrets.rotationId | quote }}
        {{- end }}
      labels:
        {{- include "countly.selectorLabels" $root | nindent 8 }}
        app.kubernetes.io/component: {{ $component }}
    spec:
      serviceAccountName: {{ include "countly.serviceAccountName" $root }}
      terminationGracePeriodSeconds: {{ $values.terminationGracePeriodSeconds | default 30 }}
      automountServiceAccountToken: false
      securityContext:
        runAsNonRoot: true
        runAsUser: 1001
        fsGroup: 1001
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: {{ $component }}
          image: "{{ if $root.Values.global.imageRegistry }}{{ $root.Values.global.imageRegistry }}/{{ end }}{{ $root.Values.image.repository }}:{{ $root.Values.image.tag }}"
          imagePullPolicy: {{ $root.Values.image.pullPolicy }}
          securityContext:
            runAsNonRoot: true
            allowPrivilegeEscalation: false
            capabilities:
              drop:
                - ALL
            readOnlyRootFilesystem: false
            seccompProfile:
              type: RuntimeDefault
          {{- if $values.command }}
          args:
            {{- toYaml $values.command | nindent 12 }}
          {{- end }}
          {{- if $values.port }}
          ports:
            - name: http
              containerPort: {{ $values.port }}
              protocol: TCP
          {{- end }}
          {{- if $values.healthCheck }}
          startupProbe:
            httpGet:
              path: {{ $values.healthCheck.path }}
              port: http
            initialDelaySeconds: {{ $values.healthCheck.initialDelaySeconds | default 30 }}
            periodSeconds: 10
            failureThreshold: 30
            timeoutSeconds: {{ $values.healthCheck.timeoutSeconds | default 5 }}
          livenessProbe:
            httpGet:
              path: {{ $values.healthCheck.path }}
              port: http
            periodSeconds: {{ $values.healthCheck.periodSeconds | default 30 }}
            timeoutSeconds: {{ $values.healthCheck.timeoutSeconds | default 5 }}
          readinessProbe:
            httpGet:
              path: {{ $values.healthCheck.path }}
              port: http
            periodSeconds: {{ $values.healthCheck.periodSeconds | default 30 }}
            timeoutSeconds: {{ $values.healthCheck.timeoutSeconds | default 5 }}
          {{- end }}
          resources:
            {{- toYaml $values.resources | nindent 12 }}
          envFrom:
            - configMapRef:
                name: {{ $fullname }}-config-common
            - configMapRef:
                name: {{ $fullname }}-config-{{ $component }}
            - configMapRef:
                name: {{ $fullname }}-config-clickhouse
            - configMapRef:
                name: {{ $fullname }}-config-kafka
            - configMapRef:
                name: {{ $fullname }}-config-otel
            {{- if not $root.Values.secrets.common.existingSecret }}
            - secretRef:
                name: {{ $fullname }}-common
            {{- else }}
            - secretRef:
                name: {{ $root.Values.secrets.common.existingSecret }}
            {{- end }}
            {{- if not $root.Values.secrets.clickhouse.existingSecret }}
            - secretRef:
                name: {{ $fullname }}-clickhouse
            {{- else }}
            - secretRef:
                name: {{ $root.Values.secrets.clickhouse.existingSecret }}
            {{- end }}
            {{- if not $root.Values.secrets.kafka.existingSecret }}
            - secretRef:
                name: {{ $fullname }}-kafka
            {{- else }}
            - secretRef:
                name: {{ $root.Values.secrets.kafka.existingSecret }}
            {{- end }}
            {{- if $values.extraEnvFrom }}
            {{- range $values.extraEnvFrom }}
            - {{ toYaml . | nindent 14 }}
            {{- end }}
            {{- end }}
          env:
            - name: COUNTLY_CONFIG__MONGODB
              valueFrom:
                secretKeyRef:
                  name: {{ include "countly.mongodb.secretName" $root }}
                  key: {{ $root.Values.secrets.mongodb.key }}
            - name: OTEL_SERVICE_NAME
              value: "countly-{{ $component }}"
            - name: OTEL_RESOURCE_ATTRIBUTES
              value: "service.name=countly-{{ $component }},service.namespace={{ $root.Release.Namespace }},deployment.environment={{ $root.Values.global.profile | default "production" }}"
            {{- if $values.extraEnv }}
            {{- toYaml $values.extraEnv | nindent 12 }}
            {{- end }}
          volumeMounts:
            - name: tmp
              mountPath: /tmp
            - name: logs
              mountPath: /opt/countly/log
      volumes:
        - name: tmp
          emptyDir: {}
        - name: logs
          emptyDir: {}
      {{- include "countly.scheduling" (dict "values" $values "global" $root.Values.global "component" $component "fullname" (include "countly.name" $root) "extraAffinity" (.extraAffinity | default dict)) | nindent 6 }}
      {{- with $root.Values.global.imagePullSecrets }}
      imagePullSecrets:
        {{- toYaml . | nindent 8 }}
      {{- end }}
{{- end }}
{{- end -}}

{{/*
Service for a Countly component
*/}}
{{- define "countly.component.service" -}}
{{- $root := .root -}}
{{- $component := .component -}}
{{- $values := .values -}}
{{- $fullname := include "countly.fullname" $root -}}
{{- if and $values.enabled $values.port }}
apiVersion: v1
kind: Service
metadata:
  name: {{ $fullname }}-{{ $component }}
  labels:
    {{- include "countly.labels" $root | nindent 4 }}
    app.kubernetes.io/component: {{ $component }}
spec:
  type: ClusterIP
  ports:
    - port: {{ $values.port }}
      targetPort: http
      protocol: TCP
      name: http
  selector:
    {{- include "countly.selectorLabels" $root | nindent 4 }}
    app.kubernetes.io/component: {{ $component }}
{{- end }}
{{- end -}}

{{/*
HPA for a Countly component
*/}}
{{- define "countly.component.hpa" -}}
{{- $root := .root -}}
{{- $component := .component -}}
{{- $values := .values -}}
{{- $fullname := include "countly.fullname" $root -}}
{{- if and $values.enabled $values.hpa.enabled }}
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: {{ $fullname }}-{{ $component }}
  labels:
    {{- include "countly.labels" $root | nindent 4 }}
    app.kubernetes.io/component: {{ $component }}
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: {{ $fullname }}-{{ $component }}
  minReplicas: {{ $values.hpa.minReplicas }}
  maxReplicas: {{ $values.hpa.maxReplicas }}
  metrics:
    {{- if $values.hpa.metrics.cpu }}
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: {{ $values.hpa.metrics.cpu.averageUtilization }}
    {{- end }}
    {{- if $values.hpa.metrics.memory }}
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: {{ $values.hpa.metrics.memory.averageUtilization }}
    {{- end }}
  {{- if $values.hpa.behavior }}
  behavior:
    {{- toYaml $values.hpa.behavior | nindent 4 }}
  {{- end }}
{{- end }}
{{- end -}}

{{/*
PDB for a Countly component
*/}}
{{- define "countly.component.pdb" -}}
{{- $root := .root -}}
{{- $component := .component -}}
{{- $values := .values -}}
{{- $fullname := include "countly.fullname" $root -}}
{{- if and $values.enabled $values.pdb.enabled }}
{{- if not (or $values.pdb.minAvailable $values.pdb.maxUnavailable) }}
{{- fail (printf "PDB for %s is enabled but neither minAvailable nor maxUnavailable is set" $component) }}
{{- end }}
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: {{ $fullname }}-{{ $component }}
  labels:
    {{- include "countly.labels" $root | nindent 4 }}
    app.kubernetes.io/component: {{ $component }}
spec:
  {{- if $values.pdb.minAvailable }}
  minAvailable: {{ $values.pdb.minAvailable }}
  {{- end }}
  {{- if $values.pdb.maxUnavailable }}
  maxUnavailable: {{ $values.pdb.maxUnavailable }}
  {{- end }}
  selector:
    matchLabels:
      {{- include "countly.selectorLabels" $root | nindent 6 }}
      app.kubernetes.io/component: {{ $component }}
{{- end }}
{{- end -}}
