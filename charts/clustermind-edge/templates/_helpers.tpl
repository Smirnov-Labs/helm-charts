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
clustermind.ai/warning: "Using 'latest' tag - pin to a specific SHA for production"
{{- end }}
{{- end }}
