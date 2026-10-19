{{/*
mycrd.integrations.references (callback)

Invoked by crdkit's integration chain.
Validates the references the service handlers recorded and writes the
valid ones to `spec.application.services.<id>.references`.

Interface:
- Params: ctx (see crdkit.integrations.chain).
- Returns: nothing (mutates ctx.model and ctx.diag in place).

Implementation notes:
- ALWAYS last in the chain: a referenced node may be created by a
  handler that runs after the one referencing it.
- Services are visited in alphabetical ID order, each one's pointers
  sorted, so diagnostics and output are deterministic.
- Per pointer, in order:
  1. Self-reference -> WARNING `service '<id>' references '<pointer>',
     which it defines itself — dropped`. Self means: the service's own
     node, a node owned by the service (ctx.mycrd.owners), or a mount
     whose only contributor is the service.
  2. Node under a disabled service (`ctx.mycrd.disabled`, filled by
     mycrd.integrations.services) -> ERROR `service '<id>' references
     '<pointer>', which belongs to disabled service '<disabled>' —
     dropped`. Checked before the existence check: a disabled service
     has no node, and the message names the cause. Applies to service
     and variable pointers; mount and file pointers carry no service, so
     a mount only disabled services would have created falls under 3.
  3. Node missing in the model (crdkit.model.hasPath) -> ERROR `service
     '<id>' references '<pointer>', which does not exist — dropped`. A
     variable whose token exists with its service but is not exported
     records `service '<id>' references '<pointer>': variable '<name>'
     is not exported (targetContainer none) — dropped` instead.
  4. Otherwise kept.
- Kept pointers are unique (the registry is keyed by pointer); the
  `references` key is omitted when none is kept.
- Pointers carry no `@TOKEN@` markers; they are never resolved.
*/}}
{{- define "mycrd.integrations.references" -}}
{{- $ctx := . -}}
{{- include "mycrd.service.registry" $ctx -}}
{{- range $id := sortAlpha (keys $ctx.mycrd.references) -}}
  {{- $refs := index $ctx.mycrd.references $id -}}
  {{- $ownPointer := include "mycrd.paths.pointer" (dict "segments" (include "mycrd.paths.service" (dict "service" $id) | fromYaml).value) -}}
  {{- $kept := list -}}
  {{- range $pointer := sortAlpha (keys $refs) -}}
    {{- $descriptor := index $refs $pointer -}}
    {{- $contributors := get $ctx.mycrd.contributors $pointer | default dict -}}
    {{- $disabledOwner := "" -}}
    {{- range $disabled := sortAlpha (keys $ctx.mycrd.disabled) -}}
      {{- $prefix := include "mycrd.paths.pointer" (dict "segments" (include "mycrd.paths.service" (dict "service" $disabled) | fromYaml).value) -}}
      {{- if and (not $disabledOwner) (or (eq $pointer $prefix) (hasPrefix (printf "%s/" $prefix) $pointer)) -}}
        {{- $disabledOwner = $disabled -}}
      {{- end -}}
    {{- end -}}
    {{- if or (eq $pointer $ownPointer) (eq (get $ctx.mycrd.owners $pointer | default "") $id) (and (eq (len $contributors) 1) (hasKey $contributors $id)) -}}
      {{- include "crdkit.diag.warning" (list $ctx.diag (printf "service '%s' references '%s', which it defines itself — dropped" $id $pointer)) -}}
    {{- else if $disabledOwner -}}
      {{- include "crdkit.diag.error" (list $ctx.diag (printf "service '%s' references '%s', which belongs to disabled service '%s' — dropped" $id $pointer $disabledOwner)) -}}
    {{- else if include "crdkit.model.hasPath" (concat (list $ctx.model) $descriptor.segments) -}}
      {{- $kept = append $kept $pointer -}}
    {{- else -}}
      {{- $notExported := false -}}
      {{- if $descriptor.var -}}
        {{- $decl := get $ctx.tokens $descriptor.var.name -}}
        {{- if and (kindIs "map" $decl) (eq (get $decl "service" | default "" | toString) $descriptor.var.service) (not (has (get $decl "targetContainer" | default "") (list "main" "side-car" "both"))) -}}
          {{- $notExported = true -}}
        {{- end -}}
      {{- end -}}
      {{- if $notExported -}}
        {{- include "crdkit.diag.error" (list $ctx.diag (printf "service '%s' references '%s': variable '%s' is not exported (targetContainer none) — dropped" $id $pointer $descriptor.var.name)) -}}
      {{- else -}}
        {{- include "crdkit.diag.error" (list $ctx.diag (printf "service '%s' references '%s', which does not exist — dropped" $id $pointer)) -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}
  {{- if $kept -}}
    {{- include "crdkit.listExtend" (concat (list $ctx.model) (include "mycrd.paths.service" (dict "service" $id) | fromYaml).value (list "references" $kept)) -}}
  {{- end -}}
{{- end -}}
{{- end -}}
