{{/*
Thin, product-specific wrapper around crdkit.render. This is the only
entry point consumers call: `{{ include "mycrd.render" . }}`, always
passing THEIR root context (per spec, never treat this as a normal
subchart with values nested under .Values.myCrd.*).

`apiVersion`/`kind` are NOT hardcoded here — crdkit.render no longer
accepts them as params at all (crdkit has zero knowledge of any
specific CRD, see crdkit's CLAUDE.md). Instead they're set on
ctx.model by `mycrd.integration.preamble` (templates/_integrations.tpl),
which is always FIRST in the chain below, and crdkit.render reads them
back from there — the exact same mechanism "labels" already uses, not
a special case. Every other thing crdkit.render needs that it can't
know on its own — system/default tokens, the ordered integration chain,
and this library's own target-escalation taxonomy ("parentTargetTemplate", see
templates/_target.tpl) — is still supplied explicitly, so crdkit itself
never has to know this library's template names or its env/family/tier
conventions.
*/}}
{{- define "mycrd.render" -}}
{{- include "crdkit.render" (dict
      "context" .
      "tokens" .Values.tokens
      "target" .Values.target
      "system" (include "mycrd.systemTokens" . | fromYaml)
      "defaults" (include "mycrd.defaultTokens" . | fromYaml)
      "parentTargetTemplate" "mycrd.parentTarget"
      "chain" (list "mycrd.integration.preamble" "mycrd.integration.demo")
    ) -}}
{{- end -}}
