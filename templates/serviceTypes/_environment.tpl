{{/*
mycrd.serviceType.environment (callback)

Invoked by mycrd.integrations.services.
Handler for `type: environment`. Its variables are consumer declarations
that mycrd.serviceTokens already turned into tokens, so there is nothing
left to generate.

Interface:
- Params (dict): { "ctx": <chain ctx>, "id": <service ID>, "service":
  <the service declaration> }
- Returns: nothing.
*/}}
{{- define "mycrd.serviceType.environment" -}}
{{- end -}}

{{/*
mycrd.serviceType.environment.schema (callback)

Invoked by mycrd.schema (one switch case per service type).
Values schema of a `type: environment` service: the common service keys
only.

Interface:
- Params: any value (ignored).
- Returns YAML: a map schema node.
*/}}
{{- define "mycrd.serviceType.environment.schema" -}}
type: map
doc: "A service that only declares variables."
properties:
  {{- include "mycrd.schema.serviceBase" . | nindent 2 }}
{{- end -}}
