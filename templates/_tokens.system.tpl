{{/*
mycrd.systemTokens (internal)

Tokens reserved by this library — a consumer variable of the same name
never changes the value: mycrd.serviceTokens drops its value keys with a
WARNING and applies only its policy-approved annotations.

Interface:
- Params: consumer's root context (`.` — not a `ctx` dict; called
  before crdkit builds one).
- Returns: YAML dict of locked token declarations.

Implementation notes:
- Not re-enforced after the integration chain runs — the chain is
  trusted, first-party code, not the protected boundary.
- `COS_BUCKET_PATH` and `COS_TOKEN` are library templates (example,
  used by mycrd.serviceType.cos): their relative markers bind to the
  service that uses them (mycrd.templates); `COS_TOKEN` chains
  `COS_BUCKET_PATH`.
- ENV is quoted deliberately: an unquoted, possibly-empty scalar here
  would render as YAML `null` rather than `""`, breaking
  crdkit.tokens.substitute's `replace` call downstream.
*/}}
{{- define "mycrd.systemTokens" -}}
LIBRARY_VERSION: {{ include "crdkit.dependencyVersion" (dict "name" "my-crd" "context" .) | quote }}
ENV: {{ include "mycrd.deriveEnv" .Values.target | quote }}
API_GROUP: "platform.company.io"
COS_BUCKET_PATH: "@.instance@/@.bucket@"
COS_TOKEN: "secret://objsto/@COS_BUCKET_PATH@/token"
{{- end -}}
