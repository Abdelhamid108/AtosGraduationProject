{{/*
Expand the name of the chart.
*/}}
{{- define "petclinic.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "petclinic.fullname" -}}
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
{{- define "petclinic.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "petclinic.labels" -}}
helm.sh/chart: {{ include "petclinic.chart" . }}
{{ include "petclinic.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "petclinic.selectorLabels" -}}
app.kubernetes.io/name: {{ include "petclinic.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "petclinic.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "petclinic.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Fully-qualified name for the MySQL StatefulSet and its Service.
*/}}
{{- define "petclinic.mysql.fullname" -}}
{{- printf "%s-mysql" (include "petclinic.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Selector labels for the MySQL StatefulSet pods.
*/}}
{{- define "petclinic.mysql.selectorLabels" -}}
app.kubernetes.io/name: {{ include "petclinic.name" . }}-mysql
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Name of the Secret that holds MySQL credentials.
Uses an existing Secret when mysql.auth.existingSecret is set.
*/}}
{{- define "petclinic.mysql.secretName" -}}
{{- if .Values.mysql.auth.existingSecret }}
{{- .Values.mysql.auth.existingSecret }}
{{- else }}
{{- include "petclinic.mysql.fullname" . }}
{{- end }}
{{- end }}

{{/*
JDBC URL for the application to reach MySQL inside the cluster.
*/}}
{{- define "petclinic.mysql.jdbcUrl" -}}
{{- printf "jdbc:mysql://%s:3306/%s" (include "petclinic.mysql.fullname" .) .Values.mysql.auth.database }}
{{- end }}
