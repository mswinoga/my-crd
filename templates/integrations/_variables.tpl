{{/*
Scope: internal (chain entry, not called directly by consumers)

Interface:
- Params: ctx (see crdkit.integrations.chain).
- Returns: nothing (mutates ctx.model in place).
- Scans every declared token for an explicit `targetContainer` of
  main/side-car/both, and merges each into
  `ctx.model.spec.variables.<name>` as `{name: "@<name>@",
  targetContainer: <targetContainer>}`.

Implementation notes:
- The `name` field holds a `@<name>@` marker, not the resolved value
  directly — it resolves automatically in crdkit.render's single
  substitution pass (see crdkit's README "Building ctx.model"), so this
  integration never calls crdkit.token.value itself.
- Reads the RAW declaration's `targetContainer` directly, not through
  resolution — it's a flat property of the declaration, never
  target-escalated (see crdkit's README "Token model").
- `targetContainer: "none"` (the default) and any invalid value are
  both excluded, silently — an invalid value is still caught the first
  time the token is actually resolved (e.g. via its `@NAME@` marker
  here), same as any other declared-but-unused token.
- Placed LAST in mycrd.render's chain so a token added earlier in the
  chain (via crdkit.token.add) is still picked up.
*/}}
{{- define "mycrd.integrations.variables" -}}
{{- $accepted := list "main" "side-car" "both" -}}
{{- $vars := dict -}}
{{- range $name, $decl := .tokens -}}
  {{- if and (kindIs "map" $decl) (hasKey $decl "targetContainer") (has $decl.targetContainer $accepted) -}}
    {{- $_ := set $vars $name (dict "name" (printf "@%s@" $name) "targetContainer" $decl.targetContainer) -}}
  {{- end -}}
{{- end -}}
{{- include "crdkit.dictMerge" (list .model "spec" "variables" $vars) -}}
{{- end -}}
