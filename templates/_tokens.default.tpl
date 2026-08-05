{{/*
Tokens with library-supplied defaults that consumers MAY override by
defining the same key under their own tokens:.
*/}}
{{- define "mycrd.defaultTokens" -}}
LOG_LEVEL: "info"
TIMEOUT: "30s"
{{- end -}}
