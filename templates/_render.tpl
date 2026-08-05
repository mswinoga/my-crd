{{/*
Thin, product-specific wrapper around crdkit.render. This is the only
entry point consumers call: `{{ include "mycrd.render" . }}`, always
passing THEIR root context (per spec, never treat this as a normal
subchart with values nested under .Values.myCrd.*).

Everything crdkit.render needs that it can't know on its own —
system/default tokens, the CR's apiVersion/kind, and the ordered
integration chain — is supplied here explicitly, so crdkit itself never
has to know this library's template names.
*/}}
{{- define "mycrd.render" -}}
{{- include "crdkit.render" (dict
      "context" .
      "tokens" .Values.tokens
      "target" .Values.target
      "system" (include "mycrd.systemTokens" . | fromYaml)
      "defaults" (include "mycrd.defaultTokens" . | fromYaml)
      "apiVersion" "platform.company.io/v1"
      "kind" "SomeCR"
      "chain" (list "mycrd.integration.demo")
    ) -}}
{{- end -}}
