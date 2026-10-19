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

{{/*
mycrd.serviceFields (internal)

Pre-render step between the structural schema pass and
mycrd.serviceTokens: rewrites the relative markers of every enabled
service (mycrd.fieldMarkers with the service ID) and declares each of
its fields as a token `<ID>.<path>`.

Interface:
- Params (dict): { "input": <normalized values from the structural
  schema pass>, "schema": <root schema node (mycrd.schema)>, "diag":
  <dict with "errors"/"warnings" lists> }
- Returns YAML: { "input": <input, every enabled service rewritten>,
  "tokens": {<ID>.<path>: <declaration>} }

Implementation notes:
- Rewritten: every key of a service except `type` and `enabled` (both
  static), `environment` included. Declared: every key except `type`,
  `enabled` and `environment` (mycrd.serviceFields.declare).
- A disabled service (mycrd.service.enabled) is left as it is and
  declares nothing: a marker to one of its fields stays unresolved.
- Field token names never collide with a variable, a library token or
  another service's field: none of those can hold a ".".
- Records nothing: every shape problem was reported by the structural
  pass; `diag` is accepted for symmetry with the other pre-render steps.
*/}}
{{- define "mycrd.serviceFields" -}}
{{- $input := deepCopy (.input | default dict) -}}
{{- $schema := .schema -}}
{{- $tokens := dict -}}
{{- $services := (include "mycrd.values.services" (dict "ctx" (dict "mycrd" (dict "input" $input))) | fromYaml).value -}}
{{- $static := list "type" "enabled" -}}
{{- $rewritten := dict -}}
{{- range $id, $svc := $services -}}
  {{- if include "mycrd.service.enabled" (dict "id" $id "service" $svc) -}}
    {{- $new := dict -}}
    {{- range $key, $v := $svc -}}
      {{- if has $key $static -}}
        {{- $_ := set $new $key $v -}}
      {{- else -}}
        {{- $_ := set $new $key (include "mycrd.fieldMarkers" (dict "id" $id "value" $v) | fromYaml).value -}}
      {{- end -}}
    {{- end -}}
    {{- $_ := set $rewritten $id $new -}}
  {{- else -}}
    {{- $_ := set $rewritten $id $svc -}}
  {{- end -}}
{{- end -}}
{{- if $services -}}
  {{- $_ := set $input.application "services" $rewritten -}}
{{- end -}}
{{- range $id, $svc := $rewritten -}}
  {{- if include "mycrd.service.enabled" (dict "id" $id "service" $svc) -}}
    {{- range $key, $v := $svc -}}
      {{- if not (has $key (list "type" "enabled" "environment")) -}}
        {{- include "mycrd.serviceFields.declare" (dict
              "schema" $schema
              "input" $input
              "keys" (concat (include "mycrd.values.serviceKeys" (dict "id" $id) | fromYaml).value (list $key))
              "name" (printf "%s.%s" $id $key)
              "value" $v
              "tokens" $tokens) -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- dict "input" $input "tokens" $tokens | toYaml -}}
{{- end -}}

{{/*
mycrd.serviceFields.declare (internal)

Declares one field (and, for a map field, its keys recursively) as a
field token; shared recursion of mycrd.serviceFields.

Interface:
- Params (dict): { "schema": <root schema node>, "input": <rewritten
  input>, "keys": <keys of the field from the input root>, "name":
  <token name, `<ID>.<path>`>, "value": <the field's value>, "tokens":
  <dict, written in place> }
- Returns: nothing.

Implementation notes:
- By the field's node type (crdkit.schema.node): `map` → not declared,
  each key declared as `<name>.<key>` (a dict at a map node is ambiguous
  between a token declaration and a nested map); `any` →
  `{default: <value>}` (an `any` node takes no token declaration);
  every other type → a dict as written (a token declaration), anything
  else `{default: <value>}`.
- A key without a node (none after the structural pass) is skipped.
- Annotation keys (mycrd.annotationNames) are dropped from a
  declaration: a field token is never exported.
*/}}
{{- define "mycrd.serviceFields.declare" -}}
{{- $node := (include "crdkit.schema.node" (dict "schema" .schema "values" .input "keys" .keys) | fromYaml).value -}}
{{- $type := "" -}}
{{- if kindIs "map" $node -}}
  {{- $type = $node.type | default "" | toString -}}
{{- end -}}
{{- $value := .value -}}
{{- if eq $type "map" -}}
  {{- if kindIs "map" $value -}}
    {{- range $key, $v := $value -}}
      {{- include "mycrd.serviceFields.declare" (dict "schema" $.schema "input" $.input "keys" (concat $.keys (list $key)) "name" (printf "%s.%s" $.name $key) "value" $v "tokens" $.tokens) -}}
    {{- end -}}
  {{- end -}}
{{- else if and $type (kindIs "map" $value) (ne $type "any") -}}
  {{- $decl := deepCopy $value -}}
  {{- range $annotation := (include "mycrd.annotationNames" (dict) | fromYaml).value -}}
    {{- $_ := unset $decl $annotation -}}
  {{- end -}}
  {{- $_ := set .tokens .name $decl -}}
{{- else if $type -}}
  {{- $_ := set .tokens .name (dict "default" $value) -}}
{{- end -}}
{{- end -}}
