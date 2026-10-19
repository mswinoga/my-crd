{{/*
Field references: a service field may reference another field of the
same service with the relative marker `@.<path>@`. my-crd rewrites it to
the absolute marker `@<ID>.<path>@` (mycrd.fieldMarkers) and declares
every field of an enabled service as a token named `<ID>.<path>`
(mycrd.serviceFields), so crdkit's token resolution does the rest: lazy,
per target, chained, cycle-checked.
*/}}

{{/*
mycrd.fieldMarkers (internal)

Rewrites every relative marker `@.<path>@` to the absolute marker
`@<id>.<path>@`, in every string leaf of a value.

Interface:
- Params (dict): { "id": <service ID>, "value": <any> }
- Returns YAML: { "value": <value with every string leaf rewritten> }

Implementation notes:
- Walks dicts and lists recursively; map keys and non-string scalars
  are left as they are.
- Markers are found like crdkit finds them (leftmost, non-overlapping,
  crdkit's marker pattern); only one starting with `@.` and at least one
  name character is rewritten, so `@.@`, `@AT@` escapes and plain text
  stay.
*/}}
{{- define "mycrd.fieldMarkers" -}}
{{- $id := toString .id -}}
{{- $value := .value -}}
{{- if kindIs "string" $value -}}
  {{/* tokenize like crdkit (leftmost, non-overlapping markers), so "@AT@.x@AT@" stays an escape: mark every marker, rewrite the relative ones, unmark. */}}
  {{- $marked := regexReplaceAll "@([A-Za-z0-9_.]+)@" $value "\x00${1}\x01" -}}
  {{- $rewritten := regexReplaceAll "\x00\\.([A-Za-z0-9_.]+)\x01" $marked (printf "@%s.${1}@" $id) -}}
value: {{ $rewritten | replace "\x00" "@" | replace "\x01" "@" | quote }}
{{- else if kindIs "map" $value -}}
  {{- $result := dict -}}
  {{- range $k, $v := $value -}}
    {{- $_ := set $result $k (include "mycrd.fieldMarkers" (dict "id" $id "value" $v) | fromYaml).value -}}
  {{- end -}}
value: {{ $result | toYaml | nindent 2 }}
{{- else if kindIs "slice" $value -}}
  {{- $result := list -}}
  {{- range $v := $value -}}
    {{- $result = append $result (include "mycrd.fieldMarkers" (dict "id" $id "value" $v) | fromYaml).value -}}
  {{- end -}}
value: {{ $result | toYaml | nindent 2 }}
{{- else -}}
value: {{ $value | toYaml | nindent 2 }}
{{- end -}}
{{- end -}}
