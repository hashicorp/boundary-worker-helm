{{/*
Expand the name of the chart.
*/}}
{{- define "boundary.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "boundary.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "boundary.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "boundary.labels" -}}
helm.sh/chart: {{ include "boundary.chart" . }}
{{ include "boundary.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "boundary.selectorLabels" -}}
app.kubernetes.io/name: {{ include "boundary.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Worker selector labels
*/}}
{{- define "boundary.worker.selectorLabels" -}}
{{ include "boundary.selectorLabels" . }}
app.kubernetes.io/component: worker
{{- end }}

{{/*
Get the worker proxy service name
*/}}
{{- define "boundary.worker.proxy.serviceName" -}}
{{- printf "%s-proxy" (include "boundary.fullname" .) }}
{{- end }}

{{/*
Get the worker ops service name
*/}}
{{- define "boundary.worker.ops.serviceName" -}}
{{- printf "%s-ops" (include "boundary.fullname" .) }}
{{- end }}

{{/*
Get the worker ConfigMap name
*/}}
{{- define "boundary.worker.configmapName" -}}
{{- printf "%s-config" (include "boundary.fullname" .) }}
{{- end }}

{{/*
Get the worker Deployment name
*/}}
{{- define "boundary.worker.deploymentName" -}}
{{- printf "%s-deployment" (include "boundary.fullname" .) }}
{{- end }}

{{/*
Get the worker recording PVC name
*/}}
{{- define "boundary.worker.recordingPvcName" -}}
{{- printf "%s-recording-storage" (include "boundary.fullname" .) }}
{{- end }}

{{/*
Get the worker auth storage PVC name
*/}}
{{- define "boundary.worker.authStoragePvcName" -}}
{{- printf "%s-auth-storage" (include "boundary.fullname" .) }}
{{- end }}

{{/*
Secure pod security context for test pods
*/}}
{{- define "boundary.test.podSecurityContext" -}}
runAsNonRoot: true
runAsUser: 65534
runAsGroup: 65534
fsGroup: 65534
seccompProfile:
  type: RuntimeDefault
{{- end }}

{{/*
Secure container security context for test pods
*/}}
{{- define "boundary.test.containerSecurityContext" -}}
allowPrivilegeEscalation: false
runAsNonRoot: true
runAsUser: 65534
runAsGroup: 65534
readOnlyRootFilesystem: true
capabilities:
  drop:
    - ALL
{{- end }}

{{/*
Resource limits and requests for test pods
*/}}
{{- define "boundary.test.resources" -}}
requests:
  cpu: 100m
  memory: 128Mi
limits:
  cpu: 200m
  memory: 256Mi
{{- end }}