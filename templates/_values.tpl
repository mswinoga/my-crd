{{/*
mycrd.values.services (internal)

The consumer's services map, read from the values. The only place that
knows where services live in the input (`application.services`).

Interface:
- Params (dict): { "root": <consumer root $> }
- Returns YAML: { "value": <services map> } — `{}` when `application`
  or `application.services` is absent, null or not a map.

Implementation notes:
- Records nothing: mycrd.serviceTokens reports malformed shapes from
  the raw values, once.
- Reads `.Values` through `toYaml | fromYaml`: Sprig's dict functions
  need plain maps, not Helm's `chartutil.Values`.
*/}}
{{- define "mycrd.values.services" -}}
{{- $application := (.root.Values | toYaml | fromYaml).application -}}
{{- $services := dict -}}
{{- if and (kindIs "map" $application) (kindIs "map" $application.services) -}}
  {{- $services = $application.services -}}
{{- end -}}
value: {{ $services | toYaml | nindent 2 }}
{{- end -}}
