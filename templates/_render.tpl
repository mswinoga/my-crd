{{/*
Scope: public

Interface:
- Params: none (uses `.` directly).
- Returns: the rendered CR as YAML text (see crdkit.render).
- The only entry point consumers call: `{{ include "mycrd.render" . }}`,
  always with THEIR root context (never nested under .Values.myCrd.*).

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
{{- $prepared := include "mycrd.serviceTokens" (dict
      "context" .
      "diag" $diag
      "system" (include "mycrd.systemTokens" . | fromYaml)
      "defaults" (include "mycrd.defaultTokens" . | fromYaml)
    ) | fromYaml -}}
{{- include "crdkit.render" (dict
      "context" .
      "tokens" $prepared.tokens
      "target" .Values.target
      "system" $prepared.system
      "defaults" $prepared.defaults
      "parentTargetTemplate" "mycrd.parentTarget"
      "annotations" (include "mycrd.annotationNames" . | fromYaml).value
      "diag" $diag
      "chain" (list "mycrd.integrations.preamble" "mycrd.integrations.services" "mycrd.integrations.serviceOutput")
    ) -}}
{{- end -}}
