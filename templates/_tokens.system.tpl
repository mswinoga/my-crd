{{/*
Tokens that are reserved by this library and cannot be overridden by
consumers. If a consumer's tokens: map defines one of these keys, their
value is discarded — this dict is passed into crdkit.render as "system",
merged in last, unconditionally, and a WARNING diagnostic is recorded
for the collision by crdkit.resolveAllTokens (and re-asserted a second
time after the integration chain runs, by crdkit.render).
*/}}
{{- define "mycrd.systemTokens" -}}
LIBRARY_VERSION: {{ include "crdkit.dependencyVersion" (dict "name" "my-crd" "context" .) }}
API_GROUP: "platform.company.io"
{{- end -}}
