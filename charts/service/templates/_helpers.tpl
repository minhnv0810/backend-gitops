{{- define "service.name" -}}
{{- .Values.nameOverride | default .Chart.Name -}}
{{- end -}}

{{- define "service.fullname" -}}
{{- include "service.name" . -}}
{{- end -}}

{{- define "service.labels" -}}
app.kubernetes.io/name: {{ include "service.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "service.selectorLabels" -}}
app.kubernetes.io/name: {{ include "service.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
