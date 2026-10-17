{{/*
Scope: internal (chain entry, not called directly by consumers)

Interface:
- Params: ctx (see crdkit.integrations.chain).
- Returns: nothing (mutates ctx.model in place).
- Writes the rendered CR's `spec.services`: every EXPORTED token (raw
  `targetContainer` of main/side-car/both), grouped by its `service`
  annotation:
  `spec.services.<ID>: {type: <service type>, environment: {<NAME>:
  {value: "@<NAME>@", targetContainer: <tc>}}}`.

Implementation notes:
- ALWAYS last in the chain, so tokens added by any earlier integration
  are included.
- `value` holds a `@<NAME>@` marker, resolved by crdkit.render's single
  substitution pass — this integration never resolves tokens itself.
- Reads the RAW declaration's annotations, not resolved values: they are
  static metadata, never target-escalated.
- Tokens are visited in alphabetical name order, so diagnostics are
  deterministic.
- An exported token without a `service` annotation, or whose service is
  not under `Values.services`, records an ERROR and is skipped.
  (Reachable only through a token added with crdkit.token.add that
  omits `{service: <ID>}`.)
- A service without exported tokens does not appear in the output.
- Reads `Values.services` through `toYaml | fromYaml` (plain maps); a
  non-map service entry yields an empty `type` (mycrd.serviceTokens
  already warned).
*/}}
{{- define "mycrd.integrations.serviceOutput" -}}
{{- $ctx := . -}}
{{- $diag := $ctx.diag -}}
{{- $exported := list "main" "side-car" "both" -}}
{{- $services := ($ctx.root.Values | toYaml | fromYaml).services | default dict -}}
{{- if not (kindIs "map" $services) -}}
  {{- $services = dict -}}
{{- end -}}
{{- range $name := sortAlpha (keys $ctx.tokens) -}}
  {{- $decl := index $ctx.tokens $name -}}
  {{- $tc := "" -}}
  {{- if kindIs "map" $decl -}}
    {{- $tc = get $decl "targetContainer" | default "" -}}
  {{- end -}}
  {{- if has $tc $exported -}}
    {{- $svc := get $decl "service" | default "" -}}
    {{- if not $svc -}}
      {{- $_ := set $diag "errors" (append $diag.errors (printf "token '%s' is exported (targetContainer '%s') but has no service — skipped" $name $tc)) -}}
    {{- else if not (hasKey $services (toString $svc)) -}}
      {{- $_ := set $diag "errors" (append $diag.errors (printf "token '%s' belongs to service '%s', which is not declared under services — skipped" $name $svc)) -}}
    {{- else -}}
      {{- $owner := index $services (toString $svc) -}}
      {{- $type := "" -}}
      {{- if kindIs "map" $owner -}}
        {{- $type = get $owner "type" -}}
      {{- end -}}
      {{- include "crdkit.dictMerge" (list $ctx.model "spec" "services" (toString $svc) (dict
            "type" $type
            "environment" (dict $name (dict "value" (printf "@%s@" $name) "targetContainer" $tc)))) -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- end -}}
