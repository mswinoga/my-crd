{{/*
Scope: internal

Interface:
- Params: none.
- Returns: YAML dict of default token declarations.
- Tokens with library-supplied defaults; consumers MAY override the
  value by declaring a variable of the same name under a service's
  `environment` (annotations follow mycrd.annotationPolicy.internal).
*/}}
{{- define "mycrd.defaultTokens" -}}
LOG_LEVEL: "info"
TIMEOUT: "30s"
{{- end -}}
