{{/*
Expand the name of the chart.
*/}}
{{- define "devops-app.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "devops-app.fullname" -}}
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
Create chart name and version as used by the chart label.
*/}}
{{- define "devops-app.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Target namespace (defaults to Release.Namespace).
*/}}
{{- define "devops-app.namespace" -}}
{{- default .Release.Namespace .Values.namespaceOverride }}
{{- end }}

{{/*
ConfigMap name used by app workloads.
*/}}
{{- define "devops-app.configMapName" -}}
{{- default "app-config" .Values.configMap.name }}
{{- end }}

{{/*
Database secret name used by app workloads.
*/}}
{{- define "devops-app.secretName" -}}
{{- default "db-secrets" .Values.secrets.name }}
{{- end }}

{{/*
Postgres ClusterIP service name.
*/}}
{{- define "devops-app.postgresServiceName" -}}
{{- default "postgres-db" .Values.postgres.service.clusterIP.name }}
{{- end }}

{{/*
Fully qualified postgres host for ConfigMap and connection strings.
*/}}
{{- define "devops-app.postgresHost" -}}
{{- printf "%s.%s.svc.cluster.local" (include "devops-app.postgresServiceName" .) (include "devops-app.namespace" .) }}
{{- end }}

{{/*
Backend service URL for frontend env.
*/}}
{{- define "devops-app.backendUrl" -}}
{{- if .Values.frontend.backendUrl }}
{{- .Values.frontend.backendUrl }}
{{- else }}
{{- printf "http://%s.%s.svc.cluster.local:%v" .Values.backend.name (include "devops-app.namespace" .) .Values.backend.service.port }}
{{- end }}
{{- end }}

{{/*
Common labels (app label preserved for selector compatibility).
*/}}
{{- define "devops-app.labels" -}}
app: {{ .component }}
helm.sh/chart: {{ include "devops-app.chart" .root }}
app.kubernetes.io/name: {{ include "devops-app.name" .root }}
app.kubernetes.io/instance: {{ .root.Release.Name }}
app.kubernetes.io/managed-by: {{ .root.Release.Service }}
{{- end }}

{{/*
Selector labels matching flat manifests (app: <component>).
*/}}
{{- define "devops-app.selectorLabels" -}}
app: {{ .component }}
{{- end }}
