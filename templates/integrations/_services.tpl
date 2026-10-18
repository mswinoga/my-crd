{{/*
mycrd.integrations.services (callback)

Invoked by crdkit's integration chain.
Dispatcher for the consumer's services (mycrd.values.services): for each type in mycrd.serviceTypes
order, for each service of that type in alphabetical ID order, calls
mycrd.service.add and then `mycrd.serviceType.<type>` with `{ctx, id,
service}`. A disabled service (mycrd.service.enabled) gets neither call.

Interface:
- Params: ctx (see crdkit.integrations.chain).
- Returns: nothing (mutates ctx.model, ctx.tokens and ctx.mycrd via
  mycrd.service.add and the type handlers; records each disabled service
  in `ctx.mycrd.disabled.<ID>`).

Implementation notes:
- Type order matters: handlers of earlier types run first.
- Services with a missing/unknown type are skipped without a diagnostic;
  mycrd.serviceTokens already reported them.
- Disabled services are recorded in `ctx.mycrd.disabled` whatever their
  type (the references integration reads it) and are skipped without a
  diagnostic; a non-boolean `enabled` counts as enabled and was reported
  by mycrd.serviceTokens, so this dispatcher stays silent.
- Creates the registry (mycrd.service.registry) even when no service is
  dispatched.
- Handlers mutate through the mycrd.service.* helpers and emit no text.
*/}}
{{- define "mycrd.integrations.services" -}}
{{- $ctx := . -}}
{{- include "mycrd.service.registry" $ctx -}}
{{- $services := (include "mycrd.values.services" (dict "root" $ctx.root) | fromYaml).value -}}
{{- range $id := sortAlpha (keys $services) -}}
  {{- $service := index $services $id -}}
  {{- if and (kindIs "map" $service) (not (include "mycrd.service.enabled" (dict "id" $id "service" $service))) -}}
    {{- $_ := set $ctx.mycrd.disabled (toString $id) true -}}
  {{- end -}}
{{- end -}}
{{- range $type := (include "mycrd.serviceTypes" . | fromYaml).value -}}
  {{- range $id := sortAlpha (keys $services) -}}
    {{- $service := index $services $id -}}
    {{- if and (kindIs "map" $service) (eq (get $service "type" | toString) $type) (include "mycrd.service.enabled" (dict "id" $id "service" $service)) -}}
      {{- include "mycrd.service.add" (dict "ctx" $ctx "id" $id) -}}
      {{- include (printf "mycrd.serviceType.%s" $type) (dict "ctx" $ctx "id" $id "service" $service) -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- end -}}
