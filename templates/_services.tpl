{{/*
Scope: internal

Interface:
- Params: none (any value is ignored).
- Returns YAML: { "value": [<service type name>, ...] }
- The ORDERED list of service types this library knows. Order is the
  order in which type handlers run (mycrd.integrations.services).

Implementation notes:
- Wrapped in `value:` — Helm's `fromYaml` cannot decode a bare list.
*/}}
{{- define "mycrd.serviceTypes" -}}
value: {{ list "environment" "demo" | toYaml | nindent 2 }}
{{- end -}}

{{/*
Scope: internal

Interface:
- Params (dict): { "decls": <dict of token declarations, each a scalar or a dict> }
- Returns YAML: the same names, every declaration a dict (a scalar
  `v` becomes `{default: v}`); dict declarations are copied.
- Normalizes library-owned declarations (`system`/`defaults`) so that
  annotations can later be attached and consumer dicts deep-merge onto
  them instead of replacing a scalar.
*/}}
{{- define "mycrd.normalizeDeclarations.internal" -}}
{{- $out := dict -}}
{{- range $name, $decl := (.decls | default dict) -}}
  {{- if kindIs "map" $decl -}}
    {{- $_ := set $out $name (deepCopy $decl) -}}
  {{- else -}}
    {{- $_ := set $out $name (dict "default" $decl) -}}
  {{- end -}}
{{- end -}}
{{- $out | toYaml -}}
{{- end -}}

{{/*
Scope: internal

Interface:
- Params: none (any value is ignored).
- Returns YAML: { "value": [<annotation name>, ...] }
- The annotation names this library owns on token declarations:
  `service` (the owning service ID) and `targetContainer`.
  mycrd.render hands the same list to crdkit.render, which treats each
  as a reserved key (never a target entry).
*/}}
{{- define "mycrd.annotationNames" -}}
value: {{ list "service" "targetContainer" | toYaml | nindent 2 }}
{{- end -}}

{{/*
Scope: internal

Interface:
- Params (dict): { "decl": <token declaration dict> }
- Returns YAML: { "annotations": <dict>, "values": <dict> } — the
  declaration's keys partitioned into this library's annotations
  (mycrd.annotationNames) and everything else (target entries, `match`).
*/}}
{{- define "mycrd.splitAnnotations.internal" -}}
{{- $names := (include "mycrd.annotationNames" . | fromYaml).value -}}
{{- $annotations := dict -}}
{{- $values := dict -}}
{{- range $key, $v := (.decl | default dict) -}}
  {{- if has $key $names -}}
    {{- $_ := set $annotations $key $v -}}
  {{- else -}}
    {{- $_ := set $values $key $v -}}
  {{- end -}}
{{- end -}}
{{- dict "annotations" $annotations "values" $values | toYaml -}}
{{- end -}}

{{/*
Scope: internal

Interface:
- Params (dict): { "name": <token name, for messages>, "library": <dict
  of annotations set by the library>, "requested": <dict of annotations
  a consumer variable asks for>, "diag": <dict, appended to in place> }
- Returns YAML: { "value": <final annotations dict> }
- Pure policy function: decides which annotations a token ends up with
  when the library and a consumer both declare it.

Implementation notes:
- An annotation the library set is locked; a missing one is filled in
  from `requested`.
- `targetContainer` may only widen. Allowed requests per library value
  (absent behaves like `none`): none -> none/main/side-car/both;
  main -> main/both; side-car -> side-car/both; both -> both. A request
  outside that set (including an unrecognized value) records a WARNING
  and keeps the library value.
- Any other locked annotation differing from the request records a
  WARNING and keeps the library value.
- When the library has no `targetContainer` (or `none`), a request that
  is not one of main/side-car/both/none is ignored without a
  diagnostic: validating consumer values is mycrd.serviceTokens' job.
*/}}
{{- define "mycrd.annotationPolicy.internal" -}}
{{- $name := .name -}}
{{- $diag := .diag -}}
{{- $library := .library | default dict -}}
{{- $requested := .requested | default dict -}}
{{- $widening := dict
      "none" (list "none" "main" "side-car" "both")
      "main" (list "main" "both")
      "side-car" (list "side-car" "both")
      "both" (list "both") -}}
{{- $final := deepCopy $library -}}
{{- range $key := sortAlpha (keys $requested) -}}
  {{- $want := index $requested $key -}}
  {{- if eq $key "targetContainer" -}}
    {{- $have := get $library "targetContainer" | default "none" -}}
    {{- $allowed := get $widening (toString $have) | default (list) -}}
    {{- if has $want $allowed -}}
      {{- $_ := set $final $key $want -}}
    {{- else if ne (toString $have) "none" -}}
      {{- if ne (toString $want) (toString $have) -}}
        {{- $_ := set $diag "warnings" (append $diag.warnings (printf "variable '%s' tries to narrow library targetContainer '%v' to '%v' — library value kept" $name $have $want)) -}}
      {{- end -}}
    {{- end -}}
  {{- else if hasKey $library $key -}}
    {{- if ne (toString (index $library $key)) (toString $want) -}}
      {{- $_ := set $diag "warnings" (append $diag.warnings (printf "variable '%s' tries to change library annotation '%s' — library value kept" $name $key)) -}}
    {{- end -}}
  {{- else -}}
    {{- $_ := set $final $key $want -}}
  {{- end -}}
{{- end -}}
value: {{ $final | toYaml | nindent 2 }}
{{- end -}}

{{/*
Scope: internal

Interface:
- Params (dict): { "context": <consumer root $>, "diag": <dict with
  "errors"/"warnings" lists, appended to in place>, "system": <dict>,
  "defaults": <dict> }
- Returns YAML: { "tokens": <dict>, "system": <dict>, "defaults": <dict> }
  — ready to pass to crdkit.render.
- Pre-render step: warns about a non-empty root `tokens:` (a values key
  nothing reads), turns `Values.services.<ID>.environment` into token
  declarations annotated with `service: <ID>`, and normalizes the
  library-owned declarations.

Implementation notes:
- Runs before crdkit builds ctx, so it records into the shared `diag`
  seed itself.
- Services are visited in alphabetical ID order, variables in
  alphabetical name order: the first service declaring a name owns it.
- A service with a missing/unknown `type` is skipped entirely,
  `environment` included.
- A scalar variable becomes `{default: <v>}`; `service` is always set to
  the parent service ID (an explicit one is overwritten with a WARNING).
- `targetContainer` outside main/side-car/both/none is corrected to
  `none` with an ERROR.
- A variable named like a `defaults` token keeps the library's locked
  annotations and may widen `targetContainer` / fill in missing ones
  (mycrd.annotationPolicy.internal); its value keys deep-merge over the
  library's in crdkit.
- A variable named like a `system` token is removed from `tokens`; only
  its policy-approved annotations are written onto the system
  declaration (value keys record a WARNING), so a library-owned value
  can be exported without being overridable.
- Read `.Values` through `toYaml | fromYaml` first: Sprig's dict
  functions need plain maps, not Helm's `chartutil.Values`.
*/}}
{{- define "mycrd.serviceTokens" -}}
{{- $diag := .diag -}}
{{- $values := .context.Values | toYaml | fromYaml -}}
{{- $knownTypes := (include "mycrd.serviceTypes" . | fromYaml).value -}}
{{- $containers := list "main" "side-car" "both" "none" -}}

{{- $system := include "mycrd.normalizeDeclarations.internal" (dict "decls" .system) | fromYaml -}}
{{- $defaults := include "mycrd.normalizeDeclarations.internal" (dict "decls" .defaults) | fromYaml -}}

{{- if $values.tokens -}}
  {{- $_ := set $diag "warnings" (append $diag.warnings "values key 'tokens' is not read — declare variables under services.<ID>.environment") -}}
{{- end -}}

{{- $tokens := dict -}}
{{- $owners := dict -}}

{{- $services := $values.services | default dict -}}
{{- if not (kindIs "map" $services) -}}
  {{- $services = dict -}}
{{- end -}}
{{- range $id := sortAlpha (keys $services) -}}
  {{- $svc := index $services $id -}}
  {{- $type := "" -}}
  {{- if kindIs "map" $svc -}}
    {{- $type = get $svc "type" | default "" -}}
  {{- end -}}
  {{- if not (has $type $knownTypes) -}}
    {{- $_ := set $diag "warnings" (append $diag.warnings (printf "service '%s' has unknown type '%v' — service skipped" $id $type)) -}}
  {{- else -}}
    {{- $env := get $svc "environment" | default dict -}}
    {{- if not (kindIs "map" $env) -}}
      {{- $env = dict -}}
    {{- end -}}
    {{- range $name := sortAlpha (keys $env) -}}
      {{- $raw := index $env $name -}}
      {{- $decl := dict "default" $raw -}}
      {{- if kindIs "map" $raw -}}
        {{- $decl = deepCopy $raw -}}
      {{- end -}}
      {{- if hasKey $decl "service" -}}
        {{- $_ := set $diag "warnings" (append $diag.warnings (printf "variable '%s' in service '%s' sets 'service' explicitly — ignored" $name $id)) -}}
      {{- end -}}
      {{- $_ := set $decl "service" $id -}}
      {{- if hasKey $owners $name -}}
        {{- $_ := set $diag "errors" (append $diag.errors (printf "variable '%s' is declared by services '%s' and '%s' — keeping '%s'" $name (index $owners $name) $id (index $owners $name))) -}}
      {{- else -}}
        {{- $_ := set $owners $name $id -}}
        {{- if and (hasKey $decl "targetContainer") (not (has $decl.targetContainer $containers)) -}}
          {{- $_ := set $diag "errors" (append $diag.errors (printf "invalid targetContainer '%v' for '%s' — must be one of main/side-car/both/none" $decl.targetContainer $name)) -}}
          {{- $_ := set $decl "targetContainer" "none" -}}
        {{- end -}}
        {{- $_ := set $tokens $name $decl -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}
{{- end -}}

{{/* library-owned names: apply the annotation policy to consumer variables sharing the name. */}}
{{- range $name := sortAlpha (keys $defaults) -}}
  {{- if hasKey $tokens $name -}}
    {{- $mine := include "mycrd.splitAnnotations.internal" (dict "decl" (index $tokens $name)) | fromYaml -}}
    {{- $lib := include "mycrd.splitAnnotations.internal" (dict "decl" (index $defaults $name)) | fromYaml -}}
    {{- $final := include "mycrd.annotationPolicy.internal" (dict "name" $name "library" $lib.annotations "requested" $mine.annotations "diag" $diag) | fromYaml -}}
    {{- $decl := $mine.values -}}
    {{- range $key, $v := $final.value -}}
      {{- $_ := set $decl $key $v -}}
    {{- end -}}
    {{- $_ := set $tokens $name $decl -}}
  {{- end -}}
{{- end -}}
{{- range $name := sortAlpha (keys $system) -}}
  {{- if hasKey $tokens $name -}}
    {{- $mine := include "mycrd.splitAnnotations.internal" (dict "decl" (index $tokens $name)) | fromYaml -}}
    {{- $lib := include "mycrd.splitAnnotations.internal" (dict "decl" (index $system $name)) | fromYaml -}}
    {{- if $mine.values -}}
      {{- $_ := set $diag "warnings" (append $diag.warnings (printf "token '%s' is reserved by the library — only annotations were applied" $name)) -}}
    {{- end -}}
    {{- $final := include "mycrd.annotationPolicy.internal" (dict "name" $name "library" $lib.annotations "requested" $mine.annotations "diag" $diag) | fromYaml -}}
    {{- $decl := deepCopy (index $system $name) -}}
    {{- range $key, $v := $final.value -}}
      {{- $_ := set $decl $key $v -}}
    {{- end -}}
    {{- $_ := set $system $name $decl -}}
    {{- $_ := unset $tokens $name -}}
  {{- end -}}
{{- end -}}

{{- dict "tokens" $tokens "system" $system "defaults" $defaults | toYaml -}}
{{- end -}}

{{/*
Scope: internal

Interface:
- Params (dict): { "ctx": <chain ctx>, "id": <service ID>, "name":
  <token name>, "value": <generated value, may hold "@ref@" markers or
  be a structure>, "targetContainer": <string, optional> }
- Returns: nothing (mutates ctx.tokens and ctx.diag in place).
- The way a service type handler contributes a variable: registers a
  GENERATED value (crdkit.token.underlay) for `name`, annotated with
  `service: <id>` (and `targetContainer` when given).

Implementation notes:
- A token already annotated with a DIFFERENT service is left untouched
  and an ERROR is recorded: a variable has exactly one owning service.
- Generated values have the lowest priority: anything the consumer
  declared for the same token (under the same service's `environment`)
  wins, `default` included. Annotations already on the declaration win
  over the ones passed here.
*/}}
{{- define "mycrd.service.addVar" -}}
{{- $ctx := .ctx -}}
{{- $owner := "" -}}
{{- if hasKey $ctx.tokens .name -}}
  {{- $owner = get (index $ctx.tokens .name) "service" | default "" -}}
{{- end -}}
{{- if and $owner (ne (toString $owner) (toString .id)) -}}
  {{- $_ := set $ctx.diag "errors" (append $ctx.diag.errors (printf "service '%s' generates variable '%s', already owned by service '%s' — generated value ignored" .id .name $owner)) -}}
{{- else -}}
  {{- $annotations := dict "service" .id -}}
  {{- if .targetContainer -}}
    {{- $_ := set $annotations "targetContainer" .targetContainer -}}
  {{- end -}}
  {{- include "crdkit.token.underlay" (list $ctx .name .value $annotations) -}}
{{- end -}}
{{- end -}}
