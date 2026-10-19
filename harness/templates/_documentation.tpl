{{- /*
harness.documentation.sections (internal)

Renders the example values (`.Values`) through `mycrd.render` and extracts,
per service type, the output the type generates: variables, references and
the service's rendered node, as crdkit `sections` for the case
`application.services.*[type=<type>]`.

Interface:
- Params: the root context (`.`); `.Values` is the example file merged
  over harness/values.yaml.
- Returns: YAML `{sections: {<node path>: [<section>]}, errors: [<the
  render's `# ERROR:`/`# WARNING:` lines, or a parse failure>],
  missingTypes: [<entries of mycrd.serviceTypes with no example
  service>]}`.

Implementation notes:
- Needs `renderMode: validate` (harness/values.yaml): a deploy-mode render
  with errors aborts the whole run.
- Diagnostics are collected from the raw text; comments do not survive
  the parse.
- Generated variables are the rendered `environment` keys the service
  does not declare itself; an empty table yields no section.
- A service of the type that is absent from the output (disabled) is
  skipped.
*/ -}}
{{- define "harness.documentation.sections" -}}
{{- $text := include "mycrd.render" . -}}
{{- $errors := regexFindAll "(?m)^# (?:ERROR|WARNING):.*$" $text -1 -}}
{{- $parsed := fromYaml $text -}}
{{- if hasKey $parsed "Error" -}}
  {{- $errors = append $errors (printf "# ERROR: render output does not parse: %s" $parsed.Error) -}}
{{- end -}}
{{- $input := .Values | toYaml | fromYaml -}}
{{- $inServices := dig "application" "services" (dict) $input -}}
{{- $outServices := dig "spec" "application" "services" (dict) $parsed -}}
{{- $types := (include "mycrd.serviceTypes" . | fromYaml).value -}}
{{- $byType := dict -}}
{{- range $id, $service := $inServices -}}
  {{- if and (kindIs "map" $service) (kindIs "string" $service.type) -}}
    {{- $_ := set $byType $service.type (append (get $byType $service.type | default (list)) $id) -}}
  {{- end -}}
{{- end -}}
{{- $missing := list -}}
{{- $sections := dict -}}
{{- range $type := $types -}}
  {{- if not (hasKey $byType $type) -}}
    {{- $missing = append $missing $type -}}
  {{- else -}}
    {{- $variables := list -}}
    {{- $references := list -}}
    {{- $seenVariables := dict -}}
    {{- $seenReferences := dict -}}
    {{- $code := "" -}}
    {{- $codeId := "" -}}
    {{- range $id := get $byType $type -}}
      {{- if hasKey $outServices $id -}}
        {{- $service := get $inServices $id -}}
        {{- $out := get $outServices $id -}}
        {{- $declared := dig "environment" (dict) $service -}}
        {{- range $name, $variable := dig "environment" (dict) $out -}}
          {{- if not (hasKey $declared $name) -}}
            {{- $pattern := include "harness.documentation.pattern" (dict "text" $name "id" $id "service" $service "services" $inServices) -}}
            {{- if not (hasKey $seenVariables $pattern) -}}
              {{- $_ := set $seenVariables $pattern true -}}
              {{- $variables = append $variables (list $pattern $name (toString $variable.value) (toString (dig "targetContainer" "" $variable))) -}}
            {{- end -}}
          {{- end -}}
        {{- end -}}
        {{- range $pointer := $out.references | default (list) -}}
          {{- $pattern := include "harness.documentation.pattern" (dict "text" $pointer "id" $id "service" $service "services" $inServices) -}}
          {{- if not (hasKey $seenReferences $pattern) -}}
            {{- $_ := set $seenReferences $pattern true -}}
            {{- $references = append $references (list $pattern $pointer) -}}
          {{- end -}}
        {{- end -}}
        {{- if not $codeId -}}
          {{- $codeId = $id -}}
          {{- $code = $out | toYaml -}}
        {{- end -}}
      {{- end -}}
    {{- end -}}
    {{- $list := list -}}
    {{- if $variables -}}
      {{- $list = append $list (dict "title" "Generated variables" "doc" "Added to the service's `environment` by its handler." "columns" (list "Pattern" "Example" "Value" "Container") "rows" $variables) -}}
    {{- end -}}
    {{- if $references -}}
      {{- $list = append $list (dict "title" "References" "doc" "Nodes the service points the controller at." "columns" (list "Pattern" "Example") "rows" $references) -}}
    {{- end -}}
    {{- if $codeId -}}
      {{- $list = append $list (dict "title" "Example output" "doc" (printf "`spec.application.services.%s` as rendered." $codeId) "code" $code) -}}
    {{- end -}}
    {{- if $list -}}
      {{- $_ := set $sections (printf "application.services.*[type=%s]" $type) $list -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- dict "sections" $sections "errors" $errors "missingTypes" $missing | toYaml -}}
{{- end -}}

{{- /*
harness.documentation.pattern (internal)

Turns the concrete name, pointer or value of a service's generated output
into its pattern.

Interface:
- Params (dict): { "text": <string>, "id": <the service's ID>,
  "service": <its example input>, "services": <all example services> }
- Returns: the text with the service's own ID as `<ID>`, then the ID of
  another example service held by a field as `<field>`.

Implementation notes:
- Only whole IDs are replaced (neighbours are non-alphanumeric, `_` and
  `/` included), so a plain field value never turns into a placeholder.
- Each replacement runs twice: adjacent matches share their separator
  and the first pass skips every second one.
*/ -}}
{{- define "harness.documentation.pattern" -}}
{{- $text := .text -}}
{{- $replacements := list (list .id "<ID>") -}}
{{- range $field, $value := .service -}}
  {{- if and (ne $field "type") (kindIs "string" $value) (ne $value $.id) (hasKey $.services $value) -}}
    {{- $replacements = append $replacements (list $value (printf "<%s>" $field)) -}}
  {{- end -}}
{{- end -}}
{{- range $replacement := $replacements -}}
  {{- $expression := printf "(^|[^A-Za-z0-9])%s($|[^A-Za-z0-9])" (regexQuoteMeta (first $replacement)) -}}
  {{- range until 2 -}}
    {{- $text = regexReplaceAll $expression $text (printf "${1}%s${2}" (last $replacement)) -}}
  {{- end -}}
{{- end -}}
{{- $text -}}
{{- end -}}

{{- /*
harness.documentation.document (internal)

One `crdkit.schema.document` call over mycrd.schema for the example
values, shared by the three documentation templates.

Interface:
- Params (dict): { "root": <root context>, "format": json|html|md,
  "sections": <harness.documentation.sections, decoded>, "diag": <dict
  with errors/warnings lists, filled in place> }
- Returns: the document text.

Implementation notes:
- `documentation` and `renderMode` are left out of the example: the
  first is the switch that renders these templates, the second comes
  from harness/values.yaml, not from the example file.
*/ -}}
{{- define "harness.documentation.document" -}}
{{- $example := omit (.root.Values | toYaml | fromYaml) "documentation" "renderMode" -}}
{{- include "crdkit.schema.document" (dict "format" .format "schemaText" (include "mycrd.schema" .root) "example" $example "sections" .sections.sections "title" "my-crd values" "htmlLink" "VALUES.html" "diag" .diag) -}}
{{- end -}}

{{- /*
harness.undocumented (internal)

Collects the schema path of every node without a `doc`, recursively.

Interface:
- Params (dict): { "node": <schema node>, "path": <schema path>,
  "skip": <key to leave out of `properties`, optional>, "acc": <dict
  with a "list" key, appended to in place> }
- Returns: nothing.

Implementation notes:
- A switch case's switch key (`type`) is left out: the switch node
  documents it.
*/ -}}
{{- define "harness.undocumented" -}}
{{- $node := .node -}}
{{- $path := .path -}}
{{- $acc := .acc -}}
{{- if not $node.doc -}}
  {{- $_ := set $acc "list" (append $acc.list $path) -}}
{{- end -}}
{{- range $key, $child := $node.properties | default dict -}}
  {{- if ne $key ($.skip | default "") -}}
    {{- include "harness.undocumented" (dict "node" $child "path" (printf "%s.properties.%s" $path $key) "acc" $acc) -}}
  {{- end -}}
{{- end -}}
{{- range $key := list "values" "items" -}}
  {{- if hasKey $node $key -}}
    {{- include "harness.undocumented" (dict "node" (index $node $key) "path" (printf "%s.%s" $path $key) "acc" $acc) -}}
  {{- end -}}
{{- end -}}
{{- if hasKey $node "switch" -}}
  {{- range $case, $child := $node.switch.cases -}}
    {{- include "harness.undocumented" (dict "node" $child "path" (printf "%s.switch.cases.%s" $path $case) "skip" $node.switch.by "acc" $acc) -}}
  {{- end -}}
{{- end -}}
{{- end -}}
