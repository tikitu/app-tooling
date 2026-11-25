# homebrew-cask.mk — `make bump-cask`: point the app's Homebrew cask at the
# GitHub release `make github-release` published.
#
# Imported by peru from the app-tooling pattern `homebrew-cask`
# (https://github.com/tikitu/app-tooling). Never edit it here: `peru sync`
# refuses to overwrite a changed copy, and the change belongs in app-tooling.
# docs/app-tooling/homebrew-cask/ says how to use it.
#
# The project's Makefile sets these, then `include mk/homebrew-cask.mk`,
# after mk/mac-dist.mk:
#
#   HOMEBREW_CASK_REPO   the app's GitHub repository, owner/repo     (required)
#   HOMEBREW_CASK_TAP    the tap, as `brew tap` names it: user/tap   (required)
#   HOMEBREW_CASK_NAME   the cask's name, Casks/<name>.rb in the tap (required)
#   HOMEBREW_CASK_ASSET  the release asset the cask downloads
#                        (default: the zip mac-dist makes)

# Leave the including Makefile's default goal alone, wherever the include is.
_homebrew_cask_default_goal := $(.DEFAULT_GOAL)

HOMEBREW_CASK_ASSET ?= $(notdir $(RELEASE_ZIP))

.PHONY: bump-cask

# After github-release. Commits in Homebrew's clone of the tap; pushing is
# left to the person releasing.
bump-cask:
	@[ -n "$(HOMEBREW_CASK_REPO)" ] && [ -n "$(HOMEBREW_CASK_TAP)" ] && [ -n "$(HOMEBREW_CASK_NAME)" ] || \
	  { echo "✗ set HOMEBREW_CASK_REPO, HOMEBREW_CASK_TAP and HOMEBREW_CASK_NAME before including mk/homebrew-cask.mk"; exit 1; }
	@if [ -z "$(VERSION)" ]; then echo "✗ VERSION required (tag or override)"; exit 1; fi
	@scripts/bump-cask.sh --repo "$(HOMEBREW_CASK_REPO)" --tap "$(HOMEBREW_CASK_TAP)" \
	  --cask "$(HOMEBREW_CASK_NAME)" --asset "$(HOMEBREW_CASK_ASSET)" "$(VERSION)"

.DEFAULT_GOAL := $(_homebrew_cask_default_goal)
