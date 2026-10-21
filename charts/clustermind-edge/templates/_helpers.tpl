{{/*
Expand the name of the chart.
*/}}
{{- define "clustermind-edge.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "clustermind-edge.fullname" -}}
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
{{- define "clustermind-edge.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "clustermind-edge.labels" -}}
helm.sh/chart: {{ include "clustermind-edge.chart" . }}
{{ include "clustermind-edge.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "clustermind-edge.selectorLabels" -}}
app.kubernetes.io/name: {{ include "clustermind-edge.fullname" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Agent selector labels (for the regular bot StatefulSet)
*/}}
{{- define "clustermind-edge.agentSelectorLabels" -}}
{{ include "clustermind-edge.selectorLabels" . }}
app.kubernetes.io/component: agent
{{- end }}

{{/*
Super-agent selector labels
*/}}
{{- define "clustermind-edge.superAgentSelectorLabels" -}}
app.kubernetes.io/name: {{ include "clustermind-edge.fullname" . }}-super-agent
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: super-agent
{{- end }}

{{/*
Super-agent labels
*/}}
{{- define "clustermind-edge.superAgentLabels" -}}
helm.sh/chart: {{ include "clustermind-edge.chart" . }}
{{ include "clustermind-edge.superAgentSelectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Create the name of the service account to use for the regular agent.
*/}}
{{- define "clustermind-edge.serviceAccountName" -}}
{{- include "clustermind-edge.fullname" . }}
{{- end }}

{{/*
Create the name of the service account for the super-agent.
*/}}
{{- define "clustermind-edge.superAgentServiceAccountName" -}}
{{- printf "%s-super-agent" (include "clustermind-edge.fullname" .) }}
{{- end }}

{{/*
Construct the full image reference.
*/}}
{{- define "clustermind-edge.image" -}}
{{- $tag := .Values.image.tag | default .Chart.AppVersion -}}
{{- printf "%s/%s:%s" .Values.global.imageRegistry .Values.image.repository $tag -}}
{{- end }}

{{/*
Determine the secret name for Anthropic API key.
*/}}
{{- define "clustermind-edge.anthropicSecretName" -}}
{{- if .Values.anthropic.existingSecret }}
{{- .Values.anthropic.existingSecret }}
{{- else }}
{{- printf "%s-secrets" (include "clustermind-edge.fullname" .) }}
{{- end }}
{{- end }}

{{/*
Determine the secret name for Slack credentials.
*/}}
{{- define "clustermind-edge.slackSecretName" -}}
{{- if .Values.slack.existingSecret }}
{{- .Values.slack.existingSecret }}
{{- else }}
{{- printf "%s-secrets" (include "clustermind-edge.fullname" .) }}
{{- end }}
{{- end }}

{{/*
Determine the secret name for control plane credentials.
*/}}
{{- define "clustermind-edge.controlPlaneSecretName" -}}
{{- if .Values.controlPlane.existingSecret }}
{{- .Values.controlPlane.existingSecret }}
{{- else }}
{{- printf "%s-secrets" (include "clustermind-edge.fullname" .) }}
{{- end }}
{{- end }}

{{/*
The key that holds the agent token. The Secret the chart creates always uses
CLUSTER_API_KEY; an existing Secret uses controlPlane.existingSecretKey.
*/}}
{{- define "clustermind-edge.controlPlaneSecretKey" -}}
{{- if .Values.controlPlane.existingSecret }}
{{- .Values.controlPlane.existingSecretKey | default "CLUSTER_API_KEY" }}
{{- else }}
{{- "CLUSTER_API_KEY" }}
{{- end }}
{{- end }}

{{/*
Stop the install early, with a message, on mistakes the agent would otherwise only
report by crash-looping.
*/}}
{{- define "clustermind-edge.validate" -}}
{{- if eq .Release.Namespace "default" }}
{{- fail "clustermind-edge needs its own namespace, not \"default\". Install it with: --namespace clustermind --create-namespace" }}
{{- end }}
{{- if and .Values.controlPlane.url (not (or .Values.controlPlane.clusterApiKey .Values.controlPlane.existingSecret)) }}
{{- fail "Set controlPlane.existingSecret (or controlPlane.clusterApiKey) to the agent token from the ClusterMind dashboard. Without it the agent exits at startup." }}
{{- end }}
{{- if and (not .Values.controlPlane.url) (not (or .Values.slack.botToken .Values.slack.existingSecret)) }}
{{- fail "Set controlPlane.url and its agent token, or the slack values for direct Slack mode." }}
{{- end }}
{{- /*
With no storageClass set, the Redis volume binds only if the cluster has a default
StorageClass, and new EKS clusters have none. lookup sees the cluster only during
install and upgrade; helm template and helm lint return nothing and skip the check.
*/}}
{{- if and .Values.redis.enabled .Values.redis.persistence.enabled (not .Values.redis.persistence.storageClass) }}
{{- $classes := lookup "storage.k8s.io/v1" "StorageClass" "" "" }}
{{- if $classes }}
{{- $hasDefault := false }}
{{- range ($classes.items | default list) }}
{{- $annotations := .metadata.annotations | default dict }}
{{- if or (eq (toString (index $annotations "storageclass.kubernetes.io/is-default-class")) "true") (eq (toString (index $annotations "storageclass.beta.kubernetes.io/is-default-class")) "true") }}
{{- $hasDefault = true }}
{{- end }}
{{- end }}
{{- if not $hasDefault }}
{{- fail "This cluster has no default StorageClass, so the Redis volume would never bind. Set redis.persistence.storageClass (for example gp3 on EKS), or set redis.persistence.enabled=false to keep Redis state in memory only." }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Whether we need to create a Secret resource.
Returns "true" if any credentials are provided directly (not via existingSecret).
*/}}
{{- define "clustermind-edge.createSecret" -}}
{{- if or (and .Values.anthropic.apiKey (not .Values.anthropic.existingSecret)) (and .Values.slack.botToken (not .Values.slack.existingSecret)) (and .Values.controlPlane.clusterApiKey (not .Values.controlPlane.existingSecret)) -}}
true
{{- end -}}
{{- end }}

{{/*
Annotations - adds a warning if image tag is "latest".
*/}}
{{- define "clustermind-edge.annotations" -}}
{{- if eq ((.Values.image.tag | default .Chart.AppVersion) | toString) "latest" }}
clustermind.ai/warning: "Using the 'latest' tag - pin a released version (vX.Y.Z) instead"
{{- end }}
{{- end }}
