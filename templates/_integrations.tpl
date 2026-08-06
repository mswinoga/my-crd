{{/*
Scope: internal (chain entry, not called directly by consumers)

Interface:
- Params: ctx (see crdkit.integrations.chain).
- Returns: nothing (mutates ctx.model in place).
- Placeholder integration proving the chain mechanism end-to-end. Real
  integrations (database, cos, messaging, outbound http, ...) land here
  the same way as this library grows.

Implementation notes:
- Every integration owns its own ctx.model field(s) via
  crdkit.dictMerge/listExtend — `(list .model "<key1>" ... <value>)` —
  which creates every missing intermediate level itself; don't assume
  an earlier chain entry already created part of the path.
*/}}
{{- define "mycrd.integration.demo" -}}
{{- include "crdkit.dictMerge" (list .model "metadata" "labels" (dict "platform.company.io/integration-demo" "true")) -}}
{{- include "crdkit.integrations.chain" . -}}
{{- end -}}
