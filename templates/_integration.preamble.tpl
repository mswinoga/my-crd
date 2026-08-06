{{/*
mycrd.integration.preamble is FIRST in mycrd.render's chain, always. It
does ALL of the work of turning "whatever the consumer wrote in Values"
plus "this library's own conventions" into the shape of a real CR on
ctx.model — crdkit.render itself doesn't do any of this anymore (it
never reads ctx.root.Values, and never assumes ctx.model has any
particular field — see crdkit's CLAUDE.md/README). Concretely, in order:

  1. apiVersion/kind, via crdkit.dictMerge with an EMPTY path — `(list
     .ctx.model (dict "apiVersion" ... "kind" ...))` — the zero-path-key
     degenerate case crdkit.dictMerge deliberately supports (see its own
     doc comment in crdkit's templates/_model.tpl) for setting several
     independent TOP-LEVEL scalar fields in one call. `apiVersion` is
     built from the locked `API_GROUP` token (templates/_tokens.system.tpl)
     via a literal "@API_GROUP@" marker, NOT a resolved value read out
     here — token resolution is lazy, and crdkit.render only substitutes
     "@...@" markers left in ctx.model in ONE pass, AFTER the whole
     chain has run (see crdkit's CLAUDE.md/README). Writing the marker
     here and letting that later pass resolve it is exactly the same
     mechanism a consumer's own values use — this define never resolves
     anything itself.
  2. metadata.name, from the consuming chart's own Release.Name — a
     generic Helm convention crdkit itself used to apply automatically;
     now this library's job, same as everything else here.
  3. metadata.labels, in three merges whose ORDER is the precedence
     policy (crdkit.dictMerge is `mergeOverwrite` — later call wins on
     key collision; there is no separate "protected" merge mode):
       a. the consumer's OWN `metadata.labels` (from Values) — lowest
          precedence, so it can't stomp on anything below. Reading it
          needs a `| toYaml | fromYaml` round-trip on `.ctx.root.Values`
          first — Sprig's `dig` requires a plain `map[string]interface{}`
          at every level it walks, and Helm's `.Values` is the distinct
          `chartutil.Values` type, which fails `dig`'s internal type
          assertion even though it behaves like a map everywhere else;
          the round-trip normalizes it (and any nested `chartutil.Values`
          under it) into plain maps `dig` can walk.
       b. crdkit.standardLabels — merged in AFTER (a), so it overwrites
          any accidental consumer collision with e.g.
          app.kubernetes.io/name. This is a deliberate choice, not
          crdkit's: a different specific library could just as validly
          call crdkit.standardLabels LAST (after the whole chain) to
          give it unconditional precedence instead — crdkit has no
          opinion either way (see its README's "Building ctx.model").
       c. this library's own library-version label
          (platform.company.io/library-version, via the `LIBRARY_VERSION`
          token — again a marker, resolved on the later pass) — my-crd's
          own responsibility, not crdkit's: crdkit can compute its OWN
          version (crdkit.dependencyVersion) but has no way to know
          "my-crd" exists at all, let alone that it's the thing worth
          labeling a CR with.
     `crdkit.integrations.chain` runs AFTER all three, so any REAL
     integration further down the chain can still deliberately override
     a specific label key on purpose — nothing here is a hard guarantee,
     just an ordering choice.
  4. spec, copied from the consumer's own `Values.spec` verbatim (still
     containing unsubstituted "@TOKEN@" markers at this point — resolved
     by crdkit.render's single pass over the whole model, same as
     everything else).

Mutation-only, same discipline as every other integration: this define
emits NO literal text itself, only `include`s that are themselves
empty-returning (crdkit.dictMerge, crdkit.integrations.chain) — see
crdkit's CLAUDE.md on why mixing real text output into a mutation-phase
define is exactly the kind of thing that has corrupted render output
here before (an early version of crdkit's now-deleted
crdkit.resolveTargetContainerTokens leaked text this way once).
*/}}
{{- define "mycrd.integration.preamble" -}}
{{- include "crdkit.dictMerge" (list .ctx.model (dict "apiVersion" "@API_GROUP@/v1" "kind" "SomeCR")) -}}
{{- include "crdkit.dictMerge" (list .ctx.model "metadata" (dict "name" .ctx.root.Release.Name)) -}}
{{- include "crdkit.dictMerge" (list .ctx.model "metadata" "labels" (dig "metadata" "labels" (dict) (.ctx.root.Values | toYaml | fromYaml))) -}}
{{- include "crdkit.dictMerge" (list .ctx.model "metadata" "labels" (include "crdkit.standardLabels" (dict "context" .ctx.root) | fromYaml)) -}}
{{- include "crdkit.dictMerge" (list .ctx.model "metadata" "labels" (dict "platform.company.io/library-version" "@LIBRARY_VERSION@")) -}}
{{- include "crdkit.dictMerge" (list .ctx.model "spec" (.ctx.root.Values.spec | default dict)) -}}
{{- include "crdkit.integrations.chain" . -}}
{{- end -}}
