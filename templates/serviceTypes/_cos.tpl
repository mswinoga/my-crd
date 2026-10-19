{{/*
mycrd.serviceType.cos (callback)

Invoked by mycrd.integrations.services.
Handler for `type: cos`: exports the variable `<ID>_TOKEN`, a secret
reference built by the library template `COS_TOKEN` from the service's
own `instance` and `bucket`.

Interface:
- Params (dict): { "ctx": <chain ctx>, "id": <service ID>, "service":
  <the normalized service declaration; fields read only through the
  template> }
- Returns: nothing (mutates the model and ctx.tokens through
  mycrd.service.addVar).

Implementation notes:
- The value is the marker `@COS_TOKEN@`: mycrd.service.addVar rewrites
  it to the service's copy `@<ID>..COS_TOKEN@`, whose relative markers
  are bound to `<ID>` (mycrd.serviceFields). Per-target fields resolve
  for the render target in crdkit's final substitution pass.
- A required field the consumer left out is reported by the structural
  pass; its marker then stays unresolved ("possible typo" WARNING).
*/}}
{{- define "mycrd.serviceType.cos" -}}
{{- include "mycrd.service.addVar" (dict
      "ctx" .ctx
      "id" .id
      "name" (printf "%s_TOKEN" .id)
      "value" "@COS_TOKEN@"
      "targetContainer" "main") -}}
{{- end -}}

{{/*
mycrd.serviceType.cos.schema (callback)

Invoked by mycrd.schema (one switch case per service type).
Values schema of a `type: cos` service.

Interface:
- Params: any value (ignored).
- Returns YAML: a map schema node.
*/}}
{{- define "mycrd.serviceType.cos.schema" -}}
type: map
doc: "Example type: an object-storage bucket; exports `<ID>_TOKEN`, built by the library templates `COS_BUCKET_PATH` and `COS_TOKEN` from `instance` and `bucket`."
properties:
  {{- include "mycrd.schema.serviceBase" . | nindent 2 }}
  instance:
    type: string
    required: true
    doc: "Object-storage instance name."
  bucket:
    type: string
    required: true
    doc: "Bucket name."
{{- end -}}
