{{/*
mycrd.schema (internal)

The consumer values schema my-crd validates its input against
(crdkit.schema.*). Accepts any values: no node is checked yet.

Interface:
- Params: root context (`.`).
- Returns YAML: the root schema node (see crdkit's
  templates/_schema.tpl for the node shape).
*/}}
{{- define "mycrd.schema" -}}
kind: any
doc: "Consumer values of my-crd."
{{- end -}}
