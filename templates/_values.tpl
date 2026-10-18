{{/*
mycrd.values.services (internal)

The consumer's services map, read from the normalized input. The only
place that knows where services live in the input
(`application.services`).

Interface:
- Params (dict): { "ctx": <chain ctx, or any dict carrying
  `mycrd.input`> }
- Returns YAML: { "value": <services map> } — `{}` when `application`
  or `application.services` is absent.

Implementation notes:
- `ctx.mycrd.input` is the output of the structural schema pass
  (mycrd.render): every service in it is a map with a known `type` and
  a boolean `enabled`, malformed shapes are already dropped and
  reported. Records nothing.
- mycrd.serviceTokens runs before crdkit builds ctx and passes
  `{mycrd: {input}}` as `ctx`.
*/}}
{{- define "mycrd.values.services" -}}
{{- $input := dig "mycrd" "input" (dict) .ctx | default dict -}}
{{- $application := get $input "application" -}}
{{- $services := dict -}}
{{- if and (kindIs "map" $application) (kindIs "map" $application.services) -}}
  {{- $services = $application.services -}}
{{- end -}}
value: {{ $services | toYaml | nindent 2 }}
{{- end -}}

{{/*
mycrd.values.serviceKeys (internal)

The keys leading from the root of the input to one service — the input
location mycrd.values.services reads, as a key list for crdkit.schema.node
and crdkit.schema.path.

Interface:
- Params (dict): { "id": <service ID> }
- Returns YAML: { "value": ["application", "services", <id>] }
*/}}
{{- define "mycrd.values.serviceKeys" -}}
value:
- application
- services
- {{ .id | toString | quote }}
{{- end -}}
