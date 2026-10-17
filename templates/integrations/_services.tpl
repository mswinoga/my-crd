{{/*
mycrd.integrations.services (internal)

Chain entry, not called directly by consumers.
Dispatcher for `Values.services`: for each type in mycrd.serviceTypes
order, for each service of that type in alphabetical ID order, calls
`mycrd.serviceType.<type>` with `{ctx, id, service}`.

Interface:
- Params: ctx (see crdkit.integrations.chain).
- Returns: nothing (mutates ctx.tokens via the type handlers).

Implementation notes:
- Type order matters: handlers of earlier types run first.
- Services with a missing/unknown type are skipped without a diagnostic;
  mycrd.serviceTokens already reported them.
- Reads `Values.services` through `toYaml | fromYaml` (plain maps).
- Handlers mutate through mycrd.service.addVar and emit no text.
*/}}
{{- define "mycrd.integrations.services" -}}
{{- $ctx := . -}}
{{- $services := ($ctx.root.Values | toYaml | fromYaml).services | default dict -}}
{{- if kindIs "map" $services -}}
  {{- range $type := (include "mycrd.serviceTypes" . | fromYaml).value -}}
    {{- range $id := sortAlpha (keys $services) -}}
      {{- $service := index $services $id -}}
      {{- if and (kindIs "map" $service) (eq (get $service "type" | toString) $type) -}}
        {{- include (printf "mycrd.serviceType.%s" $type) (dict "ctx" $ctx "id" $id "service" $service) -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- end -}}
