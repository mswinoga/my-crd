{{/*
mycrd.serviceType.db (callback)

Invoked by mycrd.integrations.services.
Handler for `type: db`: exports the variables `<ID>_PASSWORD` (the
`password` field) and `<ID>_PORT` (the `port` field).

Interface:
- Params (dict): { "ctx": <chain ctx>, "id": <service ID>, "service":
  <the normalized service declaration; reads `password` and `port`> }
- Returns: nothing (mutates the model and ctx.tokens through
  mycrd.service.addVar).

Implementation notes:
- Both fields are read through mycrd.service.value: resolved for the
  render target (field references included) and checked against their
  schema; `port` comes back as an int.
- `password` defaults to a value built from `instance` by a field
  reference (`secret://@.instance@/password`); the consumer may override
  it, with references too.
- A required field the consumer left out is reported by the structural
  pass; the variable built from it is then not generated.
*/}}
{{- define "mycrd.serviceType.db" -}}
{{- range $pair := list (list "password" "PASSWORD") (list "port" "PORT") -}}
  {{- $field := index $pair 0 -}}
  {{- if hasKey $.service $field -}}
    {{- include "mycrd.service.addVar" (dict
          "ctx" $.ctx
          "id" $.id
          "name" (printf "%s_%s" $.id (index $pair 1))
          "value" (include "mycrd.service.value" (dict "ctx" $.ctx "id" $.id "field" (list $field)) | fromYaml).value
          "targetContainer" "main") -}}
  {{- end -}}
{{- end -}}
{{- end -}}

{{/*
mycrd.serviceType.db.schema (callback)

Invoked by mycrd.schema (one switch case per service type).
Values schema of a `type: db` service.

Interface:
- Params: any value (ignored).
- Returns YAML: a map schema node.
*/}}
{{- define "mycrd.serviceType.db.schema" -}}
type: map
doc: "Example type: a database connection; exports `<ID>_PASSWORD` and `<ID>_PORT`. Fields may reference each other with `@.<field>@`."
properties:
  {{- include "mycrd.schema.serviceBase" . | nindent 2 }}
  instance:
    type: string
    required: true
    doc: "Database instance name."
  host:
    type: string
    required: true
    doc: "Database host."
  port:
    type: int
    required: true
    doc: "Database port; exported as `<ID>_PORT`."
  password:
    type: string
    default: "secret://@.instance@/password"
    doc: "Password reference; exported as `<ID>_PASSWORD`."
  url:
    type: string
    doc: "Connection URL, e.g. `http://@.host@/@.instance@:@.port@`; not exported, referable as `@.url@`."
  options:
    type: list
    items:
      type: string
      doc: "One option, e.g. `sslmode=require`."
    doc: "Connection options; a reference `@.options@` splices them joined by `,`."
{{- end -}}
