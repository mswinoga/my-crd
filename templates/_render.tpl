{{/*
mycrd.render (public)

The only entry point consumers call: `{{ include "mycrd.render" . }}`,
always with THEIR root context (never nested under .Values.myCrd.*).

Interface:
- Params: none (uses `.` directly).
- Returns: the rendered CR as YAML text (see crdkit.render).

Implementation notes:
- Thin wrapper supplying crdkit.render everything it can't know itself:
  system/default tokens, the integration chain (mycrd.integrations.*,
  preamble always first), this library's own target-escalation
  taxonomy (mycrd.parentTarget, templates/_target.tpl), the annotation
  names it owns (service, targetContainer) and a fresh diagnostics seed.
- The `diag` dict is created here, first recorded into by
  mycrd.serviceTokens (pre-render), then seeded into crdkit.render, which
  appends to it and emits everything.
- tokens/system/defaults come from mycrd.serviceTokens
  (templates/_services.tpl).
- apiVersion/kind aren't passed here — mycrd.integrations.preamble sets
  them on ctx.model, same mechanism as labels.
*/}}
{{- define "mycrd.render" -}}
{{- $diag := dict "errors" (list) "warnings" (list) -}}
{{- $mode := include "mycrd.renderMode" (dict "context" . "diag" $diag) -}}
{{- $prepared := include "mycrd.serviceTokens" (dict
      "context" .
      "diag" $diag
      "system" (include "mycrd.systemTokens" . | fromYaml)
      "defaults" (include "mycrd.defaultTokens" . | fromYaml)
    ) | fromYaml -}}
{{- $output := include "crdkit.render" (dict
      "context" .
      "tokens" $prepared.tokens
      "target" .Values.target
      "system" $prepared.system
      "defaults" $prepared.defaults
      "parentTargetTemplate" "mycrd.parentTarget"
      "annotations" (include "mycrd.annotationNames" . | fromYaml).value
      "diag" $diag
      "chain" (list "mycrd.integrations.preamble" "mycrd.integrations.services" "mycrd.integrations.references")
    ) -}}
{{- $output -}}
{{- end -}}

{{/*
mycrd.renderMode (internal)

Resolves the consumer's `renderMode` values key to the mode
mycrd.render runs in: `validate` or `deploy`. An absent key means
`deploy`; any other value records an ERROR and also means `deploy`, so
the typo aborts a deployment instead of passing silently.

Interface:
- Params (dict): { "context": <root $>, "diag": <diag dict, mutated> }
- Returns: `validate` or `deploy` (bare string).

Implementation notes:
- Reads `.Values` through `toYaml | fromYaml` (plain maps).
- Called before any other diagnostic is recorded, so the ERROR is the
  first one listed.
*/}}
{{- define "mycrd.renderMode" -}}
{{- $values := .context.Values | toYaml | fromYaml -}}
{{- $mode := "deploy" -}}
{{- if hasKey $values "renderMode" -}}
  {{- if and (kindIs "string" $values.renderMode) (has $values.renderMode (list "validate" "deploy")) -}}
    {{- $mode = $values.renderMode -}}
  {{- else -}}
    {{- $_ := set .diag "errors" (append .diag.errors "values key 'renderMode' must be 'validate' or 'deploy' — rendering in deploy mode") -}}
  {{- end -}}
{{- end -}}
{{- $mode -}}
{{- end -}}
