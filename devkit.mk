# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026  Alexey Gladkov <gladkov.alexey@gmail.com>

CURNAME = devkit
CURFILE = $(lastword $(MAKEFILE_LIST))

V = $(VERBOSE)
Q = $(if $(V),,@)

define require-utility
$(eval $(1) := $(shell command -v $(2) 2>/dev/null))
$(if $($(1)),,$(error Required utility '$(2)' not found))
endef

$(call require-utility,GIT,git)
$(call require-utility,PODMAN,podman)
$(call require-utility,CURL,curl)

GITPROJDIR = $(shell $(GIT) rev-parse --show-toplevel 2>/dev/null)
PROJNAME   = $(notdir $(GITPROJDIR))

$(if $(PROJNAME),,$(error Unable to locate the git repository.))

DEF_AGENT = copilot
DEF_DEVNAME = $(PROJNAME)

AGENT   = $(shell $(GIT) config get       devkit.agent    || echo $(DEF_AGENT))
DEVNAME = $(shell $(GIT) config get       devkit.name     || echo $(DEF_DEVNAME))
DEVPKGS = $(shell $(GIT) config get --all devkit.packages)
SHAHASH = $(shell echo $(AGENT) $(sort $(DEVPKGS)) | sha256sum | cut -f1 -d\ )

get-image-id       = $(shell $(PODMAN) image list --filter label=local.devkit.hash=$(SHAHASH) --format '{{.Id}}')
get-github-release = $(shell $(CURL) --silent --head --show-headers --no-location '$(1)' | sed -n 's,^location:.*/tag/v\?,,p')

ubuntu.packages.npm = npm
ubuntu.packages.scr = bash curl

AGENT.copilot.HOME     = https://github.com/github/copilot-cli/releases/latest
AGENT.copilot.VERSION  = $(call get-github-release,$(AGENT.copilot.HOME))
AGENT.copilot.URL      = https://gh.io/copilot-install
AGENT.copilot.SRCTYPE  = scr
AGENT.copilot.BIN      = copilot
AGENT.copilot.CONFDIR  = .copilot

AGENT.codex.HOME       = https://github.com/openai/codex/releases/latest
AGENT.codex.VERSION    = $(call get-github-release,$(AGENT.codex.HOME))
AGENT.codex.URL        = @openai/codex
AGENT.codex.SRCTYPE    = npm
AGENT.codex.BIN        = codex
AGENT.codex.CONFDIR    = .codex

AGENT.opencode.HOME    = https://github.com/anomalyco/opencode/releases/latest
AGENT.opencode.VERSION = $(call get-github-release,$(AGENT.opencode.HOME))
AGENT.opencode.URL     = https://opencode.ai/install
AGENT.opencode.SRCTYPE = scr
AGENT.opencode.BIN     = opencode
AGENT.opencode.CONFDIR = .config/opencode

AGENT.gemini.HOME      = https://github.com/google-gemini/gemini-cli/releases/latest
AGENT.gemini.VERSION   = $(call get-github-release,$(AGENT.gemini.HOME))
AGENT.gemini.URL       = @google/gemini-cli
AGENT.gemini.SRCTYPE   = npm
AGENT.gemini.BIN       = gemini
AGENT.gemini.CONFDIR   = .gemini

AGENT.claude.HOME      = https://github.com/anthropics/claude-code/releases/latest
AGENT.claude.VERSION   = $(call get-github-release,$(AGENT.claude.HOME))
AGENT.claude.URL       = https://claude.ai/install.sh
AGENT.claude.SRCTYPE   = scr
AGENT.claude.BIN       = claude
AGENT.claude.CONFDIR   = .claude

.PHONY: _check-image _create-image help init clean check upgrade list bash run
.ONESHELL:

help:
	@echo ""
	echo "Usage: make -f $(CURFILE) [ help$(foreach x,init clean check upgrade list bash run, | $(x)) ]"
	echo ""
	echo "The project allows you to manage isolated containers with AI agents."
	echo ""
	echo "Commands:"
	echo " init        creates the initial configuration in git-config."
	echo " list        shows all devkit known images."
	echo " check       shows current and available agent versions."
	echo " upgrade     upgrades podman image for current devkit."
	echo " bash        run /bin/bash inside devkit container."
	echo " run         starts devkit container."
	echo " clean       deletes all images for the current devkit."
	echo " clean-all   deletes all devkit images."
	echo " help        display this help and exit."
	echo ""
	echo "Report bugs to authors."
	echo ""

init:
	$(Q)if ! $(GIT) config get devkit.name >/dev/null 2>&1; then
	  $(GIT) config set devkit.name "$(DEVNAME)";
	  $(GIT) config set devkit.agent "$(AGENT)";
	  $(GIT) config set devkit.packages "bash";
	else
	  echo "Discovered the existing configuration and cowardly refuse to break it." >&2;
	fi

_create-image:
	$(Q)[ -n "$(get-image-id)" ] || printf '%s\n' \
	  "FROM docker.io/library/ubuntu:latest" \
	  "USER root" \
	  "RUN apt-get -y -q update" \
	  "RUN apt-get -y -q install $(sort ca-certificates bash curl tar $(DEVPKGS) $(ubuntu.packages.$(AGENT.$(AGENT).SRCTYPE)))" \
	  "RUN apt-get -y -q clean; rm -rf /var/lib/apt/lists/*" \
	  "RUN [ '$(AGENT.$(AGENT).SRCTYPE)' != 'npm' ] || { npm install -g '$(AGENT.$(AGENT).URL)'; }" \
	  "RUN [ '$(AGENT.$(AGENT).SRCTYPE)' != 'scr' ] || { curl -fsSL '$(AGENT.$(AGENT).URL)' | bash; }" \
	  "LABEL local.devkit.name=$(DEVNAME)" \
	  "LABEL local.devkit.hash=$(SHAHASH)" \
	  "LABEL local.devkit.agent=$(AGENT)" \
	  "LABEL local.devkit.agent.version=$(AGENT.$(AGENT).VERSION)" \
	  "ENTRYPOINT [\"/usr/local/bin/$(AGENT.$(AGENT).BIN)\"]" |
	$(PODMAN) image build --squash --force-rm -t "localhost/$(CURNAME)/$(DEVNAME):latest" -f-;

_check-image:
	$(Q)[ -n "$(get-image-id)" ] || $(MAKE) -f "$(CURFILE)" _create-image
	mkdir -p -- $(HOME)/$(AGENT.$(AGENT).CONFDIR)

ifneq ($(filter bash,$(MAKECMDGOALS)),)
PODMAN_ARGS := --entrypoint=/bin/bash
endif

ifneq ($(filter run,$(MAKECMDGOALS)),)
ARGS = $(strip $(eval found :=)$(foreach w,$(MAKECMDGOALS),$(if $(found),$(w),$(if $(filter run,$(w)),$(eval found := 1)))))

.DEFAULT:
	@:
endif

run: _check-image
	$(Q)$(PODMAN) container run \
	  --volume='$(GITPROJDIR):/srv/$(PROJNAME):rw' \
	  --volume='$(HOME)/$(AGENT.$(AGENT).CONFDIR):/root/$(AGENT.$(AGENT).CONFDIR):rw' \
	  --workdir='/srv/$(PROJNAME)' \
	  --rm --tty --interactive $(PODMAN_ARGS) -- "$(get-image-id)" $(ARGS) || \
	  echo "container exit status $$?"

bash: run
	@:

check:
	$(Q)image_id="$(get-image-id)";
	avail_ver="$(AGENT.$(AGENT).VERSION)";
	image_ver="`[ -z "$$image_id" ] || $(PODMAN) image inspect "$$image_id" --format '{{index .Labels "local.devkit.agent.version"}}'`";
	echo "The $(AGENT) information:";
	echo " - release home page: $(AGENT.$(AGENT).HOME)";
	echo " - available version: $${avail_ver:-*unavailable*}";
	echo " -   current version: $${image_ver:-*unknown*}";

clean-all:
	$(Q)$(PODMAN) image list --filter label=local.devkit.name --format '{{.Id}}' | xargs -r $(PODMAN) image rm

clean:
	$(Q)$(PODMAN) image list --filter label=local.devkit.name=$(DEVNAME) --format '{{.Id}}' | xargs -r $(PODMAN) image rm

upgrade: clean
	$(Q)$(MAKE) -f "$(CURFILE)" _create-image

list:
	$(Q)$(PODMAN) image list --filter label=local.devkit.name
