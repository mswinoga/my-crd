{{/*
Scope: internal (called by mycrd.integrations.services)

Interface:
- Params (dict): { "ctx": <chain ctx>, "id": <service ID>, "service":
  <the service declaration> }
- Returns: nothing.
- Handler for `type: environment`. Its variables are consumer
  declarations that mycrd.serviceTokens already turned into tokens, so
  there is nothing left to generate.
*/}}
{{- define "mycrd.serviceType.environment" -}}
{{- end -}}
