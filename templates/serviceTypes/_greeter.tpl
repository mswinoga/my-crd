{{/*
mycrd.serviceType.greeter (internal)

Called by mycrd.integrations.services.
Handler for `type: greeter`: exports the variable `<SID>_GREETER` (SID =
ID upper-cased, '-' replaced by '_') holding the service ID, and adds a
configMap mount `<ID>-config` with the file `message` holding the
greeting.

Interface:
- Params (dict): { "ctx": <chain ctx>, "id": <service ID>, "service":
  <the service declaration; reads `greeting`> }
- Returns: nothing (mutates the model and ctx.tokens through
  mycrd.service.addVar / mycrd.service.addFile).

Implementation notes:
- A service without `greeting` generates nothing.
- Generated values have the lowest priority, so
  `services.<ID>.environment.<SID>_GREETER` overrides the variable.
- `greeting` may hold `@TOKEN@` markers; they are resolved in the file
  content by the normal substitution pass.
- Service types follow this shape: one `mycrd.serviceType.<type>`
  define in templates/serviceTypes/_<type>.tpl, listed in
  mycrd.serviceTypes.
*/}}
{{- define "mycrd.serviceType.greeter" -}}
{{- if hasKey .service "greeting" -}}
  {{- include "mycrd.service.addVar" (dict
        "ctx" .ctx
        "id" .id
        "name" (printf "%s_GREETER" (upper (replace "-" "_" .id)))
        "value" .id
        "targetContainer" "main") -}}
  {{- include "mycrd.service.addFile" (dict
        "ctx" .ctx
        "id" .id
        "mount" (printf "%s-config" .id)
        "source" "configMap"
        "file" "message"
        "content" .service.greeting) -}}
{{- end -}}
{{- end -}}
