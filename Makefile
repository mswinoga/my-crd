.PHONY: update-deps dev render test test-diagnostics

# Refreshes BOTH levels of the file:// dependency chain, bottom-up:
# first my-crd's own bundled crdkit (in case crdkit changed), then
# harness's bundled my-crd (which will now correctly include the
# just-refreshed crdkit, since packaging my-crd bundles its current
# on-disk state as-is, charts/ and all). `helm dependency update` (and
# `helm template`'s `--dependency-update` flag) are NOT transitive —
# running either only at the harness level would silently bundle a
# stale crdkit copy if my-crd's own hadn't already been refreshed. See
# ../CLAUDE.md's "Layout" section for the full story.
update-deps:
	helm dependency update
	cd harness && helm dependency update

dev: update-deps
	@for f in harness/ci/test-values/*.yaml; do \
		echo "=== $$f ==="; \
		helm template harness -f "$$f"; \
		echo; \
	done

# Render a single, arbitrary values file for manual inspection — e.g. a
# work-in-progress one that isn't checked in as a fixture yet. VALUES
# can point anywhere on disk, not just harness/ci/test-values/.
#   make render VALUES=/path/to/wip-values.yaml
render: update-deps
	helm template harness -f "$(VALUES)"

test: update-deps
	helm unittest harness -f '../tests/*_test.yaml'

# Supplementary to `test`: helm-unittest asserts against parsed YAML
# fields, so it cannot see the "# ERROR:"/"# WARNING:" diagnostic
# comments (comments don't survive YAML parsing). This greps raw
# `helm template` output instead. See README.md "Testing" section.
test-diagnostics: update-deps
	./tests/diagnostics_test.sh
