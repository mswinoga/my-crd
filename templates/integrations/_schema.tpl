{{/*
mycrd.integrations.schema (callback)

Invoked by crdkit's integration chain.
Value pass: checks every per-target value of the normalized input
(`ctx.mycrd.input`) against `ctx.mycrd.schema` for the render target
(crdkit.schema.validateValues).

Interface:
- Params: ctx (see crdkit.integrations.chain).
- Returns: nothing (records into ctx.diag; marks `ctx.mycrd.validated`).

Implementation notes:
- Always LAST in mycrd.render's chain: per-target values may reference
  tokens a type handler generates.
- `ctx.mycrd.validated` is the `seen` dict shared with every other
  per-target check, so a `(path, target)` pair is reported once.
*/}}
{{- define "mycrd.integrations.schema" -}}
{{- include "mycrd.service.registry" . -}}
{{- include "crdkit.schema.validateValues" (dict "ctx" . "schema" .mycrd.schema "values" .mycrd.input "seen" .mycrd.validated) -}}
{{- end -}}
