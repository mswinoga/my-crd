{{/*
Field references: a service field may reference another field of the
same service with the relative marker `@.<path>@`. my-crd rewrites it to
the absolute marker `@<ID>.<path>@` (mycrd.fieldMarkers) and declares
every field of an enabled service as a token named `<ID>.<path>`
(mycrd.serviceFields), so crdkit's token resolution does the rest: lazy,
per target, chained, cycle-checked.

Library templates: a library token (`system`/`defaults`) holding a
relative marker binds it to the service that uses it (mycrd.templates).
mycrd.serviceFields declares one copy `<ID>..<T>` per enabled service
and template, bound to the service; mycrd.service.addVar/addFile
rewrite a marker `@T@` to `@<ID>..T@` (mycrd.templateMarkers).
*/}}

{{/*
mycrd.fieldMarkers (internal)

Rewrites every relative marker `@.<path>@` to the absolute marker
`@<id>.<path>@`, and every `@.@` to the plain text `<id>` (the service
ID), in every string leaf of a value.

Interface:
- Params (dict): { "id": <service ID>, "value": <any> }
- Returns YAML: { "value": <value with every string leaf rewritten> }

Implementation notes:
- Walks dicts and lists recursively; map keys and non-string scalars
  are left as they are.
- Markers are found like crdkit finds them (leftmost, non-overlapping,
  crdkit's marker pattern); only one starting with `@.` is rewritten, so
  `@AT@` escapes and plain text stay.
- `@.@` becomes text, not a token: the ID is known here, nothing is left
  to resolve.
*/}}
{{- define "mycrd.fieldMarkers" -}}
{{- $id := toString .id -}}
{{- $value := .value -}}
{{- if kindIs "string" $value -}}
  {{/* tokenize like crdkit (leftmost, non-overlapping markers), so "@AT@.x@AT@" stays an escape: mark every marker, rewrite the relative ones, unmark. */}}
  {{- $marked := regexReplaceAll "@([A-Za-z0-9_.]+)@" $value "\x00${1}\x01" -}}
  {{- $rewritten := regexReplaceAll "\x00\\.([A-Za-z0-9_.]+)\x01" $marked (printf "@%s.${1}@" $id) -}}
  {{- $rewritten = $rewritten | replace "\x00.\x01" $id -}}
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
  schema pass>, "schema": <root schema node (mycrd.schema)>, "system":
  <library system declarations, optional>, "defaults": <library
  default declarations, optional>, "diag": <dict with
  "errors"/"warnings" lists> }
- Returns YAML: { "input": <input, every enabled service rewritten>,
  "tokens": {<ID>.<path>: <declaration>, <ID>..<T>: <declaration>},
  "templates": [<library template names, sorted (mycrd.templates)>] }

Implementation notes:
- Rewritten: every key of a service except `type` and `enabled` (both
  static), `environment` included. Declared: every key except `type`,
  `enabled` and `environment` (mycrd.serviceFields.declare).
- A disabled service (mycrd.service.enabled) is left as it is and
  declares nothing: a marker to one of its fields stays unresolved.
- Field token names never collide with a variable, a library token or
  another service's field: none of those can hold a ".".
- Library templates (mycrd.serviceFields.instantiate): every enabled
  service gets a copy `<ID>..<T>` of every template `T`. The empty path
  segment keeps a copy distinct from every field token. Unused copies
  cost nothing: resolution is lazy.
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
{{- $library := dict "system" (.system | default dict) "defaults" (.defaults | default dict) -}}
{{- $templates := (include "mycrd.templates" $library | fromYaml).value -}}
{{- range $id, $svc := $rewritten -}}
  {{- if include "mycrd.service.enabled" (dict "id" $id "service" $svc) -}}
    {{- include "mycrd.serviceFields.instantiate" (dict "id" $id "library" $library "templates" $templates "tokens" $tokens) -}}
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
{{- dict "input" $input "tokens" $tokens "templates" $templates | toYaml -}}
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
- Annotation keys (mycrd.tokenAnnotationNames) are dropped from a
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
  {{- range $annotation := (include "mycrd.tokenAnnotationNames" (dict) | fromYaml).value -}}
    {{- $_ := unset $decl $annotation -}}
  {{- end -}}
  {{- $_ := set .tokens .name $decl -}}
{{- else if $type -}}
  {{- $_ := set .tokens .name (dict "default" $value) -}}
{{- end -}}
{{- end -}}


{{/*
mycrd.markerNames (internal)

Lists the names of the markers in every string leaf of a value.

Interface:
- Params (dict): { "value": <any> }
- Returns YAML: { "value": [<marker name without the "@"s>, ...] }

Implementation notes:
- Markers are found like crdkit finds them (leftmost, non-overlapping,
  crdkit's marker pattern), so an `@AT@` escape is one marker `AT`.
- Walks dict values and list items; map keys are not read.
*/}}
{{- define "mycrd.markerNames" -}}
{{- $names := list -}}
{{- $value := .value -}}
{{- if kindIs "string" $value -}}
  {{- range $marker := regexFindAll "@[A-Za-z0-9_.]+@" $value -1 -}}
    {{- $names = append $names (trimPrefix "@" (trimSuffix "@" $marker)) -}}
  {{- end -}}
{{- else if or (kindIs "map" $value) (kindIs "slice" $value) -}}
  {{- range $v := $value -}}
    {{- $names = concat $names (include "mycrd.markerNames" (dict "value" $v) | fromYaml).value -}}
  {{- end -}}
{{- end -}}
value: {{ $names | toYaml | nindent 2 }}
{{- end -}}

{{/*
mycrd.templates (internal)

Finds the library templates: library declarations whose relative
markers bind to the service that uses them.

Interface:
- Params (dict): { "system": <library system declarations>,
  "defaults": <library default declarations> }
- Returns YAML: { "value": [<template name>, ...] } (sorted)

Implementation notes:
- A declaration (scalar or dict, every string leaf) is a template when
  it holds a relative marker (`@.<path>@` or `@.@`, mycrd.markerNames) or a
  marker to another template; the second rule is iterated to a fixed
  point (at most one pass per declaration).
- A cycle between templates is not checked here: crdkit's cycle ERROR
  reports it when a copy is resolved.
*/}}
{{- define "mycrd.templates" -}}
{{- $decls := deepCopy (.defaults | default dict) -}}
{{- range $name, $decl := (.system | default dict) -}}
  {{- $_ := set $decls $name $decl -}}
{{- end -}}
{{- $markers := dict -}}
{{- $found := dict -}}
{{- range $name, $decl := $decls -}}
  {{- $names := (include "mycrd.markerNames" (dict "value" $decl) | fromYaml).value -}}
  {{- $_ := set $markers $name $names -}}
  {{- range $marker := $names -}}
    {{- if regexMatch "^\\.[A-Za-z0-9_.]*$" $marker -}}
      {{- $_ := set $found $name true -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- range $pass := keys $decls -}}
  {{- range $name, $names := $markers -}}
    {{- range $marker := $names -}}
      {{- if hasKey $found $marker -}}
        {{- $_ := set $found $name true -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
value: {{ keys $found | sortAlpha | toYaml | nindent 2 }}
{{- end -}}

{{/*
mycrd.templateMarkers (internal)

Rewrites every marker to a library template, `@T@`, to the service's
copy `@<id>..T@`, in every string leaf of a value.

Interface:
- Params (dict): { "id": <service ID>, "templates": [<template names>
  (mycrd.templates)], "value": <any> }
- Returns YAML: { "value": <value with every string leaf rewritten> }

Implementation notes:
- Markers are found like mycrd.fieldMarkers finds them, so an `@AT@`
  escape stays; every other marker is left as written.
- Walks dicts and lists recursively; map keys and non-string scalars
  are left as they are.
*/}}
{{- define "mycrd.templateMarkers" -}}
{{- $id := toString .id -}}
{{- $templates := .templates | default list -}}
{{- $value := .value -}}
{{- if kindIs "string" $value -}}
  {{- $marked := regexReplaceAll "@([A-Za-z0-9_.]+)@" $value "\x00${1}\x01" -}}
  {{- range $t := $templates -}}
    {{- $marked = replace (printf "\x00%s\x01" $t) (printf "@%s..%s@" $id $t) $marked -}}
  {{- end -}}
value: {{ $marked | replace "\x00" "@" | replace "\x01" "@" | quote }}
{{- else if kindIs "map" $value -}}
  {{- $result := dict -}}
  {{- range $k, $v := $value -}}
    {{- $_ := set $result $k (include "mycrd.templateMarkers" (dict "id" $id "templates" $templates "value" $v) | fromYaml).value -}}
  {{- end -}}
value: {{ $result | toYaml | nindent 2 }}
{{- else if kindIs "slice" $value -}}
  {{- $result := list -}}
  {{- range $v := $value -}}
    {{- $result = append $result (include "mycrd.templateMarkers" (dict "id" $id "templates" $templates "value" $v) | fromYaml).value -}}
  {{- end -}}
value: {{ $result | toYaml | nindent 2 }}
{{- else -}}
value: {{ $value | toYaml | nindent 2 }}
{{- end -}}
{{- end -}}

{{/*
mycrd.serviceFields.instantiate (internal)

Declares one service's copies of the library templates; part of
mycrd.serviceFields.

Interface:
- Params (dict): { "id": <service ID>, "library": { "system": <dict>,
  "defaults": <dict> }, "templates": [<template names>], "tokens":
  <dict, written in place> }
- Returns: nothing.

Implementation notes:
- Copy `<id>..<T>`: the declaration normalized like library tokens (a
  scalar `v` → `{default: v}`; a `system` declaration replaces a
  `defaults` one of the same name), annotation keys dropped (a copy is
  never exported), relative markers bound to `id`
  (mycrd.fieldMarkers), markers to templates rewritten to the
  service's copies (mycrd.templateMarkers).
- The library declaration itself stays as written.
*/}}
{{- define "mycrd.serviceFields.instantiate" -}}
{{- $library := deepCopy (.library.defaults | default dict) -}}
{{- range $name, $decl := (.library.system | default dict) -}}
  {{- $_ := set $library $name $decl -}}
{{- end -}}
{{- $decls := include "mycrd.normalizeDeclarations" (dict "decls" $library) | fromYaml -}}
{{- $annotations := (include "mycrd.tokenAnnotationNames" (dict) | fromYaml).value -}}
{{- range $t := .templates -}}
  {{- $decl := index $decls $t -}}
  {{- range $annotation := $annotations -}}
    {{- $_ := unset $decl $annotation -}}
  {{- end -}}
  {{- $decl = (include "mycrd.fieldMarkers" (dict "id" $.id "value" $decl) | fromYaml).value -}}
  {{- $decl = (include "mycrd.templateMarkers" (dict "id" $.id "templates" $.templates "value" $decl) | fromYaml).value -}}
  {{- $_ := set $.tokens (printf "%s..%s" $.id $t) $decl -}}
{{- end -}}
{{- end -}}
