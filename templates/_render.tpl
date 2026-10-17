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
- crdkit appends to the seeded `diag` dict and emits it; this library's
  own pre-render steps record into the same dict.
- apiVersion/kind aren't passed here — mycrd.integrations.preamble sets
  them on ctx.model, same mechanism as labels.
*/}}
{{- define "mycrd.render" -}}
{{- include "crdkit.render" (dict
      "context" .
      "tokens" .Values.tokens
      "target" .Values.target
      "system" (include "mycrd.systemTokens" . | fromYaml)
      "defaults" (include "mycrd.defaultTokens" . | fromYaml)
      "parentTargetTemplate" "mycrd.parentTarget"
      "annotations" (list "service" "targetContainer")
      "diag" (dict "errors" (list) "warnings" (list))
      "chain" (list "mycrd.integrations.preamble" "mycrd.integrations.demo" "mycrd.integrations.variables")
    ) -}}
{{- end -}}
