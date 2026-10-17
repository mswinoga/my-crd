{{/*
Scope: internal

Interface:
- Params: consumer's root context (`.` — not a `ctx` dict; called
  before crdkit builds one).
- Returns: YAML dict of locked token declarations.
- Tokens reserved by this library — a consumer defining the same key
  under their own `tokens:` has it discarded, with a WARNING recorded
  by crdkit.tokens.merge.internal.

Implementation notes:
- Not re-enforced after the integration chain runs — the chain is
  trusted, first-party code, not the protected boundary.
- ENV is quoted deliberately: an unquoted, possibly-empty scalar here
  would render as YAML `null` rather than `""`, breaking
  crdkit.tokens.substitute's `replace` call downstream.
*/}}
{{- define "mycrd.systemTokens" -}}
LIBRARY_VERSION: {{ include "crdkit.dependencyVersion" (dict "name" "my-crd" "context" .) }}
ENV: {{ include "mycrd.deriveEnv" .Values.target | quote }}
API_GROUP: "platform.company.io"
{{- end -}}
