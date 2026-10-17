{{/*
Scope: internal (called by mycrd.integrations.services)

Interface:
- Params (dict): { "ctx": <chain ctx>, "id": <service ID>, "service":
  <the service declaration; reads `greeting`> }
- Returns: nothing (mutates ctx.tokens through mycrd.service.addVar).
- Proof-of-mechanism handler for `type: demo`: generates the variable
  `<ID>_GREETING` (ID upper-cased, '-' replaced by '_') with the value of
  `service.greeting`, exported to the main container.

Implementation notes:
- Generated values have the lowest priority, so
  `services.<ID>.environment.<ID>_GREETING` overrides it.
- A service without `greeting` generates nothing.
- Real service types follow this shape: one `mycrd.serviceType.<type>`
  define in templates/serviceTypes/_<type>.tpl, listed in
  mycrd.serviceTypes.
*/}}
{{- define "mycrd.serviceType.demo" -}}
{{- if hasKey .service "greeting" -}}
  {{- include "mycrd.service.addVar" (dict
        "ctx" .ctx
        "id" .id
        "name" (printf "%s_GREETING" (upper (replace "-" "_" .id)))
        "value" .service.greeting
        "targetContainer" "main") -}}
{{- end -}}
{{- end -}}
