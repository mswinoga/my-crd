{{/*
Scope: internal

Interface:
- Params: none.
- Returns: YAML dict of default token declarations.
- Tokens with library-supplied defaults; consumers MAY override by
  defining the same key under their own `tokens:`.
*/}}
{{- define "mycrd.defaultTokens" -}}
LOG_LEVEL: "info"
TIMEOUT: "30s"
{{- end -}}
