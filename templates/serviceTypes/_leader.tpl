{{/*
mycrd.serviceType.leader (callback)

Invoked by mycrd.integrations.services.
Handler for `type: leader`: exports the variable `<ID>_SEED` with the
fixed value "5", and records references to the exported variable
`<greeter>_GREETER` of the greeter service named by `greeter` and to the
file `message` of that greeter's mount `<greeter>-config`.

Interface:
- Params (dict): { "ctx": <chain ctx>, "id": <service ID>, "service":
  <the service declaration; reads `greeter`, a service ID> }
- Returns: nothing (mutates the model, ctx.tokens and ctx.mycrd through
  the mycrd.service.* helpers).

Implementation notes:
- A service without `greeter` generates nothing.
- The referenced greeter is not checked here: a reference to a missing
  node is dropped with an ERROR by mycrd.integrations.references, after
  every handler ran.
*/}}
{{- define "mycrd.serviceType.leader" -}}
{{- if hasKey .service "greeter" -}}
  {{- $greeter := toString .service.greeter -}}
  {{- include "mycrd.service.addVar" (dict
        "ctx" .ctx
        "id" .id
        "name" (printf "%s_SEED" .id)
        "value" "5"
        "targetContainer" "main") -}}
  {{- include "mycrd.service.referenceVar" (dict
        "ctx" .ctx
        "id" .id
        "service" $greeter
        "name" (printf "%s_GREETER" $greeter)) -}}
  {{- include "mycrd.service.referenceFile" (dict
        "ctx" .ctx
        "id" .id
        "mount" (printf "%s-config" $greeter)
        "file" "message") -}}
{{- end -}}
{{- end -}}

{{/*
mycrd.serviceType.leader.schema (callback)

Invoked by mycrd.schema (one switch case per service type).
Values schema of a `type: leader` service.

Interface:
- Params: any value (ignored).
- Returns YAML: a map schema node.
*/}}
{{- define "mycrd.serviceType.leader.schema" -}}
type: map
doc: "Example type: exports `<ID>_SEED` and references a greeter's variable and file."
properties:
  {{- include "mycrd.schema.serviceBase" . | nindent 2 }}
  greeter:
    type: string
    markers: false
    doc: "ID of the greeter service to reference; absent → nothing generated."
{{- end -}}
