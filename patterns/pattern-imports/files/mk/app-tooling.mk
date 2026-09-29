# app-tooling.mk — make targets for the conventions this project takes from
# app-tooling (https://github.com/tikitu/app-tooling), through peru.
#
# Imported by peru from the pattern `pattern-imports`. Never edit it here:
# `peru sync` refuses to overwrite a changed copy, and the change belongs in
# app-tooling. docs/app-tooling/pattern-imports/README.md says how this works.
#
# From the project's Makefile:   include mk/app-tooling.mk

# Leave the including Makefile's default goal alone, wherever the include is.
_app_tooling_default_goal := $(.DEFAULT_GOAL)

# Pinned, like every other dependency; uvx fetches it on first use.
PERU ?= uvx peru@1.3.5
APP_TOOLING_URL := https://github.com/tikitu/app-tooling

.PHONY: app-tooling-check app-tooling-update app-tooling-tools

app-tooling-tools:
	@command -v uvx >/dev/null 2>&1 || { echo "✗ uv not installed (brew install uv)"; exit 1; }

# The imported files are exactly what peru.yaml's rev says: nothing edited in
# place, nothing left behind by an update that was not finished. Needs a
# clean tree, because the answer is the diff `peru sync` leaves. On failure
# the tree holds the pinned versions; `git checkout -- .` puts it back.
app-tooling-check: app-tooling-tools
	@[ -z "$$(git status --porcelain)" ] || { echo "✗ commit or stash first: this check reads the diff peru sync leaves"; exit 1; }
	@$(PERU) sync --force --no-overrides --quiet
	@if [ -n "$$(git status --porcelain)" ]; then \
	  git status --short; \
	  echo "✗ imported files differ from peru.yaml's rev (the tree now has the rev's versions)"; exit 1; \
	fi
	@echo "✓ app-tooling imports match peru.yaml"

# Move to the newest commit of peru.yaml's `reup:` tag or branch, import it,
# and show what to do: the CHANGELOG entries the update added. Needs a clean
# tree, so the update is a diff of its own.
#
# APP_TOOLING_LOCAL=<checkout> reads commits from a local checkout instead of
# GitHub; peru.yaml still names GitHub, so push them before anyone else syncs.
app-tooling-update: app-tooling-tools
	@[ -z "$$(git status --porcelain)" ] || { echo "✗ commit or stash first, so the update is a diff of its own"; exit 1; }
	@$(if $(APP_TOOLING_LOCAL),GIT_CONFIG_COUNT=1 \
	  GIT_CONFIG_KEY_0="url.$$(cd $(APP_TOOLING_LOCAL) && pwd).insteadOf" \
	  GIT_CONFIG_VALUE_0="$(APP_TOOLING_URL)") \
	  $(PERU) reup --force --no-overrides
	@git status --short
	@echo "→ the catch-up steps: CHANGELOG entries this update added"
	@git --no-pager diff -- 'docs/app-tooling/*/CHANGELOG.md'

.DEFAULT_GOAL := $(_app_tooling_default_goal)
