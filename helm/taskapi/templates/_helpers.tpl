{{/*
Helpers: small named templates reused by every file. "include" calls them.
*/}}

{{/* Base name for all resources: the release name, e.g. "taskapi". */}}
{{- define "taskapi.fullname" -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Standard Kubernetes labels (https://kubernetes.io/docs/concepts/overview/working-with-objects/common-labels/) */}}
{{- define "taskapi.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ include "taskapi.imageTag" . | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: taskapi
{{- end -}}

{{/* Labels used to SELECT the API pods. Must never change after the first install. */}}
{{- define "taskapi.selectorLabels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: api
{{- end -}}

{{- define "taskapi.imageTag" -}}
{{- .Values.image.tag | default .Chart.AppVersion -}}
{{- end -}}

{{- define "taskapi.image" -}}
{{ .Values.image.repository }}:{{ include "taskapi.imageTag" . }}
{{- end -}}

{{- define "taskapi.dbSecretName" -}}
{{- .Values.database.existingSecret | default (printf "%s-db" (include "taskapi.fullname" .)) -}}
{{- end -}}

{{/* Database host: the in-cluster StatefulSet's FQDN (trailing dot, see Step 3.8 E), or an external host. */}}
{{- define "taskapi.dbHost" -}}
{{- if .Values.postgres.enabled -}}
{{ include "taskapi.fullname" . }}-postgres.{{ .Release.Namespace }}.svc.cluster.local.
{{- else -}}
{{ required "database.externalHost is required when postgres.enabled=false" .Values.database.externalHost }}
{{- end -}}
{{- end -}}

{{/* Env vars every app container needs to reach the database (API + migration Job). */}}
{{- define "taskapi.dbEnv" -}}
- name: POSTGRES_DB
  value: {{ .Values.database.name | quote }}
- name: POSTGRES_USER
  value: {{ .Values.database.user | quote }}
- name: DB_HOST
  value: {{ include "taskapi.dbHost" . | quote }}
- name: DB_PORT
  value: {{ .Values.database.port | quote }}
- name: DB_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ include "taskapi.dbSecretName" . }}
      key: password
- name: APP_DATABASE_URL
  value: "postgresql+psycopg://$(POSTGRES_USER):$(DB_PASSWORD)@$(DB_HOST):$(DB_PORT)/$(POSTGRES_DB)"
{{- end -}}

{{/* Container security settings required by the "restricted" Pod Security Standard. */}}
{{- define "taskapi.containerSecurity" -}}
allowPrivilegeEscalation: false
capabilities:
  drop: ["ALL"]
{{- end -}}
