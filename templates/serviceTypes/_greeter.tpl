{{/*
mycrd.serviceType.greeter (callback)

Invoked by mycrd.integrations.services.
Handler for `type: greeter`: exports the variable `<ID>_GREETER` holding
the service ID, and adds a configMap mount `<ID>-config` with the file
`message` holding the greeting.

Interface:
- Params (dict): { "ctx": <chain ctx>, "id": <service ID>, "service":
  <the normalized service declaration; reads `greeting`> }
- Returns: nothing (mutates the model and ctx.tokens through
  mycrd.service.addVar / mycrd.service.addFile).

Implementation notes:
- A service without `greeting` generates nothing.
- Generated values have the lowest priority, so
  `services.<ID>.environment.<ID>_GREETER` overrides the variable.
- `greeting` is per-target: read through mycrd.service.value, so it is
  resolved for the render target and checked against its schema.
- Service types follow this shape: one `mycrd.serviceType.<type>`
  define in templates/serviceTypes/_<type>.tpl, listed in
  mycrd.serviceTypes.
*/}}
{{- define "mycrd.serviceType.greeter" -}}
{{- if hasKey .service "greeting" -}}
  {{- include "mycrd.service.addVar" (dict
        "ctx" .ctx
        "id" .id
        "name" (printf "%s_GREETER" .id)
        "value" .id
        "targetContainer" "main") -}}
  {{- include "mycrd.service.addFile" (dict
        "ctx" .ctx
        "id" .id
        "mount" (printf "%s-config" .id)
        "source" "configMap"
        "file" "message"
        "content" (include "mycrd.service.value" (dict "ctx" .ctx "id" .id "field" (list "greeting")) | fromYaml).value) -}}
{{- end -}}
{{- end -}}

{{/*
mycrd.serviceType.greeter.schema (callback)

Invoked by mycrd.schema (one switch case per service type).
Values schema of a `type: greeter` service.

Interface:
- Params: any value (ignored).
- Returns YAML: a map schema node.
*/}}
{{- define "mycrd.serviceType.greeter.schema" -}}
kind: map
doc: "Example type: exports `<ID>_GREETER` and a configMap mount `<ID>-config`."
properties:
  {{- include "mycrd.schema.serviceBase" . | nindent 2 }}
  greeting:
    kind: scalar
    type: string
    doc: "Content of the file `message`; absent → nothing generated."
{{- end -}}
