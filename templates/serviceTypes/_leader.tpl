{{/*
mycrd.serviceType.leader (internal)

Called by mycrd.integrations.services.
Handler for `type: leader`: exports the variable `<SID>_SEED` (SID = ID
upper-cased, '-' replaced by '_') with the fixed value "5", and records
references to the exported variable `<GSID>_GREETER` of the greeter
service named by `greeter` and to the file `message` of that greeter's
mount `<greeter>-config`.

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
- GSID is derived from the greeter's ID the same way as SID.
*/}}
{{- define "mycrd.serviceType.leader" -}}
{{- if hasKey .service "greeter" -}}
  {{- $greeter := toString .service.greeter -}}
  {{- include "mycrd.service.addVar" (dict
        "ctx" .ctx
        "id" .id
        "name" (printf "%s_SEED" (upper (replace "-" "_" .id)))
        "value" "5"
        "targetContainer" "main") -}}
  {{- include "mycrd.service.referenceVar" (dict
        "ctx" .ctx
        "id" .id
        "service" $greeter
        "name" (printf "%s_GREETER" (upper (replace "-" "_" $greeter)))) -}}
  {{- include "mycrd.service.referenceFile" (dict
        "ctx" .ctx
        "id" .id
        "mount" (printf "%s-config" $greeter)
        "file" "message") -}}
{{- end -}}
{{- end -}}
