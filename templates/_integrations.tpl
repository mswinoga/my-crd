{{/*
Integration filters for this library's CR. Each one is a link in the
chain passed to crdkit.render (see mycrd.render) — see
crdkit.integrations.chain in the crdkit chart for the calling
convention: pre-work on ctx.model/ctx.tokens, recurse into whatever
chain remains, then post-work once that returns.

There is no central, pre-declared ctx.model shape anywhere — not in
crdkit, not here. Every integration is responsible for its OWN fields:
prefer `crdkit.dictMerge`/`crdkit.listExtend` — `(list .ctx.model
"<key1>" ... "<keyN>" <dict-or-list>)`, at least one key, dig-style
positional args (not crdkit's usual named-dict convention, deliberately
— see crdkit's CLAUDE.md) — to add entries to a map/list field in one
call, walking as many nesting levels as needed. Both ensure every level
of the path exists first, every time, even if you believe an earlier
integration already created part of it (chain order isn't something to
depend on). Fall back to the lower-level `crdkit.ensureDictKey` directly
only for a shape those two don't cover. See crdkit's CLAUDE.md for why
plain `set`/`append` can't safely skip this (no auto-vivification of
missing intermediate maps/lists).

mycrd.integration.demo is a placeholder proving the chain mechanism
works end-to-end; real integrations (database, cos, messaging, outbound
http, ...) land here later, each populating whatever ctx.model fields
they need the same way.
*/}}
{{- define "mycrd.integration.demo" -}}
{{- include "crdkit.dictMerge" (list .ctx.model "metadata" "labels" (dict "platform.company.io/integration-demo" "true")) -}}
{{- include "crdkit.integrations.chain" . -}}
{{- end -}}
