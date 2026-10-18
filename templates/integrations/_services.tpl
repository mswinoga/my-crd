{{/*
mycrd.integrations.services (callback)

Invoked by crdkit's integration chain.
Dispatcher for the consumer's services (mycrd.values.services): for
each type in mycrd.serviceTypes order, for each service of that type in
alphabetical ID order, calls mycrd.service.add and then `mycrd.serviceType.<type>` with `{ctx, id,
service}`. A disabled service (mycrd.service.enabled) gets neither call.

Interface:
- Params: ctx (see crdkit.integrations.chain).
- Returns: nothing (mutates ctx.model, ctx.tokens and ctx.mycrd via
  mycrd.service.add and the type handlers; records each disabled service
  in `ctx.mycrd.disabled.<ID>`).

Implementation notes:
- Type order matters: handlers of earlier types run first.
- Reads the normalized input: every service has a known `type` and a
  boolean `enabled` (the structural schema pass dropped and reported the
  rest), so this dispatcher records nothing.
- A handler receives the normalized declaration (schema defaults
  applied); per-target fields are still as written.
- Disabled services are recorded in `ctx.mycrd.disabled` (the
  references integration reads it) and skipped.
- Creates the registry (mycrd.service.registry) even when no service is
  dispatched.
- Handlers mutate through the mycrd.service.* helpers and emit no text.
*/}}
{{- define "mycrd.integrations.services" -}}
{{- $ctx := . -}}
{{- include "mycrd.service.registry" $ctx -}}
{{- $services := (include "mycrd.values.services" (dict "ctx" $ctx) | fromYaml).value -}}
{{- range $id := sortAlpha (keys $services) -}}
  {{- $service := index $services $id -}}
  {{- if not (include "mycrd.service.enabled" (dict "id" $id "service" $service)) -}}
    {{- $_ := set $ctx.mycrd.disabled (toString $id) true -}}
  {{- end -}}
{{- end -}}
{{- range $type := (include "mycrd.serviceTypes" . | fromYaml).value -}}
  {{- range $id := sortAlpha (keys $services) -}}
    {{- $service := index $services $id -}}
    {{- if and (eq (get $service "type" | toString) $type) (include "mycrd.service.enabled" (dict "id" $id "service" $service)) -}}
      {{- include "mycrd.service.add" (dict "ctx" $ctx "id" $id) -}}
      {{- include (printf "mycrd.serviceType.%s" $type) (dict "ctx" $ctx "id" $id "service" $service) -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- end -}}
