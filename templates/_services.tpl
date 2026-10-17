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
value: {{ list "environment" | toYaml | nindent 2 }}
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

{{- dict "tokens" $tokens "system" $system "defaults" $defaults | toYaml -}}
{{- end -}}
