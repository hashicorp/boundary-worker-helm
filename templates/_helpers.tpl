{{- /*
Copyright IBM Corp. 2026
# SPDX-License-Identifier: MPL-2.0
*/ -}}

{{/*
Expand the name of the chart.
*/}}
{{- define "boundary.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Resolve the effective namespace for namespaced resources.
*/}}
{{- define "boundary.namespace" -}}
{{- default .Release.Namespace .Values.namespace -}}
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
Get proxy service annotations appropriate for the configured service type
*/}}
{{- define "boundary.worker.proxy.annotations" -}}
{{- $annotations := .Values.worker.service.proxy.annotations | default dict -}}
{{- if eq .Values.worker.service.proxy.type "LoadBalancer" -}}
{{- toYaml $annotations -}}
{{- else -}}
{{- $filtered := omit $annotations "service.beta.kubernetes.io/aws-load-balancer-type" "service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled" "service.beta.kubernetes.io/aws-load-balancer-backend-protocol" "service.beta.kubernetes.io/aws-load-balancer-scheme" -}}
{{- if $filtered -}}
{{- toYaml $filtered -}}
{{- end -}}
{{- end -}}
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
Get the worker Secret name
*/}}
{{- define "boundary.worker.secretName" -}}
{{- if .Values.secretRefs.secretName }}
{{- .Values.secretRefs.secretName }}
{{- else }}
{{- printf "%s-secrets" (include "boundary.fullname" .) }}
{{- end }}
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

{{/*
Get the OpenShift Route name for the worker proxy port
*/}}
{{- define "boundary.worker.route.name" -}}
{{- printf "%s-proxy-route" (include "boundary.fullname" .) }}
{{- end }}

{{- define "boundary.worker.ops.route.name" -}}
{{- printf "%s-ops-route" (include "boundary.fullname" .) }}
{{- end }}

{{/*
Get the service account name for the worker
*/}}
{{- define "boundary.worker.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "boundary.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Resolve the HTTP probe scheme from the ops listener TLS setting.
*/}}
{{- define "boundary.worker.probeScheme" -}}
{{- if .Values.tls.ops.disabled -}}
HTTP
{{- else -}}
HTTPS
{{- end -}}
{{- end }}

{{/*
Build the worker image reference.

Repository resolution order (first non-empty wins):
  1. .Values.image.repository  — explicit operator override
  2. openshift.enabled=true    → registry.connect.redhat.com/hashicorp/boundary-enterprise
  3. default                   → hashicorp/boundary-enterprise

Tag resolution:
  - Explicit .Values.image.tag always wins as-is.
  - When tag is empty and openshift.enabled=true, appends "-ubi" to Chart.AppVersion
    because the Red Hat registry uses the "<version>-ubi" tag convention
    (e.g. 1.0.1-ent-ubi) while Docker Hub uses "<version>" (e.g. 1.0.1-ent).
  - When tag is empty and openshift.enabled=false, uses Chart.AppVersion directly.
*/}}
{{- define "boundary.worker.image" -}}
{{- $repo := .Values.image.repository -}}
{{- if not $repo -}}
  {{- if .Values.openshift.enabled -}}
    {{- $repo = "registry.connect.redhat.com/hashicorp/boundary-enterprise" -}}
  {{- else -}}
    {{- $repo = "hashicorp/boundary-enterprise" -}}
  {{- end -}}
{{- end -}}
{{- $tag := .Values.image.tag | trim -}}
{{- if not $tag -}}
  {{- if .Values.openshift.enabled -}}
    {{- $tag = printf "%s-ubi" .Chart.AppVersion -}}
  {{- else -}}
    {{- $tag = .Chart.AppVersion -}}
  {{- end -}}
{{- end -}}
{{- printf "%s:%s" $repo $tag -}}
{{- end }}

{{/*
Returns true when worker config uses the chart-managed env-backed activation token.
Commented lines are ignored.
*/}}
{{- define "boundary.worker.usesEnvActivationToken" -}}
{{- $renderedConfig := tpl ((default "" .Values.worker.config) | toString) . -}}
{{- $configNoComments := regexReplaceAll "(?m)^\\s*#.*$" $renderedConfig "" -}}
{{- if regexMatch "controller_generated_activation_token\\s*=\\s*\"env://BOUNDARY_WORKER_CONTROLLER_GENERATED_ACTIVATION_TOKEN\"" $configNoComments -}}
true
{{- else -}}
false
{{- end -}}
{{- end }}

{{/*
Validate manual Secret existence and required keys.
Runs only when secretRefs.validateExisting=true and secretRefs.secretName is set.
*/}}
{{/*
Validate that the worker config uses the correct env reference when secretRefs.secretName is set.
If the config has controller_generated_activation_token = "env://SOMETHING_ELSE", fail with a helpful message.
*/}}
{{- define "boundary.worker.validateEnvActivationTokenRef" -}}
{{- if .Values.secretRefs.secretName -}}
{{- $renderedConfig := tpl ((default "" .Values.worker.config) | toString) . -}}
{{- $configNoComments := regexReplaceAll "(?m)^\\s*#.*$" $renderedConfig "" -}}
{{- if regexMatch "controller_generated_activation_token\\s*=\\s*\"env://" $configNoComments -}}
{{- if not (regexMatch "controller_generated_activation_token\\s*=\\s*\"env://BOUNDARY_WORKER_CONTROLLER_GENERATED_ACTIVATION_TOKEN\"" $configNoComments) -}}
{{- fail "Invalid worker.config: when secrets are enabled (secretRefs.secretName is set), use \"env://BOUNDARY_WORKER_CONTROLLER_GENERATED_ACTIVATION_TOKEN\" for the controller_generated_activation_token env reference in your worker.config." -}}
{{- end -}}
{{- else if regexMatch "controller_generated_activation_token\\s*=\\s*\"[^\"]+\"" $configNoComments -}}
{{- fail "Invalid worker.config: when secrets are enabled (secretRefs.secretName is set), do not hardcode the activation token directly in worker.config; use env://BOUNDARY_WORKER_CONTROLLER_GENERATED_ACTIVATION_TOKEN instead." -}}
{{- end -}}
{{- end -}}
{{- end }}

{{/*
Validate that worker.config and tls.ops.disabled describe the same ops listener.
The config is rendered first so the check evaluates the effective HCL values.
*/}}
{{- define "boundary.worker.validateConfig" -}}
{{- $renderedConfig := tpl ((default "" .Values.worker.config) | toString) . -}}
{{- $configNoComments := regexReplaceAll "(?m)^\\s*#.*$" $renderedConfig "" -}}
{{- $opsBlock := regexFind "(?s)listener\\s+\"tcp\"\\s*\\{[^}]*purpose\\s*=\\s*\"ops\"[^}]*\\}" $configNoComments -}}
{{- if and (not .Values.tls.ops.disabled) (eq $opsBlock "") -}}
{{- fail "tls.ops.disabled=false but worker.config has no ops listener block. Add a listener with purpose=\"ops\" or set tls.ops.disabled=true." -}}
{{- end -}}
{{- if ne $opsBlock "" -}}
{{- $expectedCertPath := regexQuoteMeta (printf "%s/tls.crt" .Values.tls.mountPath) -}}
{{- $expectedKeyPath := regexQuoteMeta (printf "%s/tls.key" .Values.tls.mountPath) -}}
{{- if and (regexMatch "tls_disable\\s*=\\s*[\"']?true[\"']?" $opsBlock) (not .Values.tls.ops.disabled) -}}
{{- fail "worker.config ops listener has tls_disable=true but tls.ops.disabled=false. Set tls.ops.disabled=true or remove tls_disable from the ops listener." -}}
{{- end -}}
{{- if and (regexMatch "tls_disable\\s*=\\s*[\"']?false[\"']?" $opsBlock) .Values.tls.ops.disabled -}}
{{- fail "worker.config ops listener has tls_disable=false but tls.ops.disabled=true. Set tls.ops.disabled=false or set tls_disable=true in the ops listener." -}}
{{- end -}}
{{- if and .Values.tls.ops.disabled (not (regexMatch "tls_disable\\s*=\\s*[\"']?true[\"']?" $opsBlock)) -}}
{{- fail "tls.ops.disabled=true but the ops listener in worker.config is missing tls_disable=true. Add tls_disable=true to the ops listener." -}}
{{- end -}}
{{- if not .Values.tls.ops.disabled -}}
{{- if not (regexMatch (printf "tls_cert_file\\s*=\\s*[\"']%s[\"']" $expectedCertPath) $opsBlock) -}}
{{- fail (printf "tls.ops.disabled=false but the ops listener in worker.config is missing expected cert path %q. Keep tls_cert_file aligned with tls.mountPath." (printf "%s/tls.crt" .Values.tls.mountPath)) -}}
{{- end -}}
{{- if not (regexMatch (printf "tls_key_file\\s*=\\s*[\"']%s[\"']" $expectedKeyPath) $opsBlock) -}}
{{- fail (printf "tls.ops.disabled=false but the ops listener in worker.config is missing expected key path %q. Keep tls_key_file aligned with tls.mountPath." (printf "%s/tls.key" .Values.tls.mountPath)) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end }}

{{/*
Validate manual Secret existence and required keys.
Runs only when secretRefs.validateExisting=true and secretRefs.secretName is set.
*/}}
{{- define "boundary.worker.validateSecretRefs" -}}
{{- if and .Values.secretRefs.validateExisting .Values.secretRefs.secretName (eq (include "boundary.worker.usesEnvActivationToken" .) "true") }}
{{- $secretName := include "boundary.worker.secretName" . | trim -}}
{{- if eq $secretName "" }}
{{- fail "secretRefs.secretName resolved to empty value" }}
{{- end }}
{{- $secret := lookup "v1" "Secret" .Release.Namespace $secretName -}}
{{- if not $secret }}
{{- fail (printf "Secret %q not found in namespace %q (set secretRefs.secretName or disable secretRefs.validateExisting)" $secretName .Release.Namespace) }}
{{- end }}
{{- $key := .Values.secretRefs.keys.controllerGeneratedActivationToken | trim -}}
{{- if eq $key "" }}
{{- fail "secretRefs.keys.controllerGeneratedActivationToken resolved to empty value" }}
{{- end }}
{{- $data := default dict (get $secret "data") -}}
{{- if not (hasKey $data $key) }}
{{- fail (printf "Secret %q is missing required key %q" $secretName $key) }}
{{- end }}
{{- end }}
{{- end }}
