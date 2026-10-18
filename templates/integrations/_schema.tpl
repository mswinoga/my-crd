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
- Disabled services (`ctx.mycrd.disabled`) are left out of the checked
  values.
- An `environment` variable is checked as the token it became: its
  declaration is replaced by the marker `@<NAME>@`, so the value checked
  is the token's (library values and generated values included) and a
  resolution problem is reported once, by the token. A variable whose
  token belongs to another service (a name collision) is left out.
- `ctx.mycrd.validated` is the `seen` dict shared with every other
  per-target check, so a `(path, target)` pair is reported once.
*/}}
{{- define "mycrd.integrations.schema" -}}
{{- $ctx := . -}}
{{- include "mycrd.service.registry" $ctx -}}
{{- $values := deepCopy ($ctx.mycrd.input | default dict) -}}
{{- $services := (include "mycrd.values.services" (dict "ctx" $ctx) | fromYaml).value -}}
{{- $checked := dict -}}
{{- range $id, $service := $services -}}
  {{- if not (hasKey $ctx.mycrd.disabled (toString $id)) -}}
    {{- $env := dict -}}
    {{- range $name, $_ := (get $service "environment" | default dict) -}}
      {{- $decl := get $ctx.tokens $name -}}
      {{- if and (kindIs "map" $decl) (eq (get $decl "service" | default "" | toString) (toString $id)) -}}
        {{- $_ := set $env $name (printf "@%s@" $name) -}}
      {{- end -}}
    {{- end -}}
    {{- $copy := deepCopy $service -}}
    {{- if hasKey $copy "environment" -}}
      {{- $_ := set $copy "environment" $env -}}
    {{- end -}}
    {{- $_ := set $checked $id $copy -}}
  {{- end -}}
{{- end -}}
{{- if kindIs "map" (get $values "application") -}}
  {{- $_ := set $values.application "services" $checked -}}
{{- end -}}
{{- include "crdkit.schema.validateValues" (dict "ctx" $ctx "schema" $ctx.mycrd.schema "values" $values "seen" $ctx.mycrd.validated) -}}
{{- end -}}
