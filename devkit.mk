# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026  Alexey Gladkov <gladkov.alexey@gmail.com>

CURFILE = $(lastword $(MAKEFILE_LIST))
PROG ?= make -f $(CURFILE) --
VERSION = 2

V = $(VERBOSE)
Q = $(if $(V),,@)

SIMPLE_GOALS = help version list clean-all
PUBLIC_GOALS = $(SIMPLE_GOALS) clean init check upgrade shell run

define require-utility
$(eval $(1) := $(shell command -v $(2) 2>/dev/null))
$(if $($(1)),,$(error Required utility '$(2)' not found))
endef

$(call require-utility,GIT,git)
$(call require-utility,PODMAN,podman)
$(call require-utility,CURL,curl)

GIT_CONFIG_SUBCOMMANDS = $(shell $(GIT) config get --default= devkit.agent >/dev/null 2>&1 && echo yes)

ifeq ($(GIT_CONFIG_SUBCOMMANDS),yes)
GIT_CONFIG_GET     = $(GIT) config get
GIT_CONFIG_GET_ALL = $(GIT) config get --all
GIT_CONFIG_SET     = $(GIT) config set
else
GIT_CONFIG_GET     = $(GIT) config --get
GIT_CONFIG_GET_ALL = $(GIT) config --get-all
GIT_CONFIG_SET     = $(GIT) config
endif

AGENT.opencode = HOMEURL=https://github.com/anomalyco/opencode/releases/latest       INST=scr LINK=https://opencode.ai/install        BIN=opencode CONFDIR=.config/opencode
AGENT.copilot  = HOMEURL=https://github.com/github/copilot-cli/releases/latest       INST=scr LINK=https://gh.io/copilot-install      BIN=copilot  CONFDIR=.copilot
AGENT.claude   = HOMEURL=https://github.com/anthropics/claude-code/releases/latest   INST=scr LINK=https://claude.ai/install.sh       BIN=claude   CONFDIR=.claude
AGENT.aider    = HOMEURL=https://github.com/Aider-AI/aider/releases/latest           INST=scr LINK=https://aider.chat/install.sh      BIN=aider    CONFDIR=.aider
AGENT.gemini   = HOMEURL=https://github.com/google-gemini/gemini-cli/releases/latest INST=npm LINK=@google/gemini-cli                 BIN=gemini   CONFDIR=.gemini
AGENT.codex    = HOMEURL=https://github.com/openai/codex/releases/latest             INST=npm LINK=@openai/codex                      BIN=codex    CONFDIR=.codex
AGENT.grok     = HOMEURL=https://github.com/superagent-ai/grok-cli/releases/latest   INST=npm LINK=@vibe-kit/grok-cli                 BIN=grok     CONFDIR=.grok
AGENT.vibe     = HOMEURL=https://github.com/mistralai/mistral-vibe/releases          INST=scr LINK=https://mistral.ai/vibe/install.sh BIN=vibe     CONFDIR=.vibe

ifeq ($(filter $(SIMPLE_GOALS),$(MAKECMDGOALS)),) # not SIMPLE_GOALS
GITPROJDIR = $(shell $(GIT) rev-parse --show-toplevel 2>/dev/null)
PROJNAME   = $(notdir $(GITPROJDIR))

$(if $(PROJNAME),,$(error Unable to locate the git repository))

DEF_AGENT = copilot
DEF_DEVSHELL = /bin/bash
DEF_EDITOR = /usr/bin/editor

VENDOR  = ubuntu
AGENT   = $(shell $(GIT_CONFIG_GET)     devkit.agent    || echo $(DEF_AGENT))
DEVSHELL= $(shell $(GIT_CONFIG_GET)     devkit.shell    || echo $(DEF_DEVSHELL))
EDITOR  = $(shell $(GIT_CONFIG_GET)     devkit.editor   || echo $(DEF_EDITOR))
HOOKS   = $(shell $(GIT_CONFIG_GET)     devkit.hooks-path)
DEVPKGS = $(shell $(GIT_CONFIG_GET_ALL) devkit.packages)
VOLUMES = $(shell $(GIT_CONFIG_GET_ALL) devkit.volumes)

LIMIT_MEMORY = $(shell $(GIT_CONFIG_GET) devkit.limit-memory || echo 0)

BUILD_COMMAND = $(shell $(GIT_CONFIG_GET)     devkit.build-command)
BUILD_VOLUMES = $(shell $(GIT_CONFIG_GET_ALL) devkit.build-volumes)
BUILD_ID      = $(shell $(GIT_CONFIG_GET)     devkit.build-id || echo none)

ifneq ($(wildcard $(HOOKS)),)
VOLUMES += $(HOOKS):/.devkit/hooks.d:ro
endif

SHAHASH = $(shell echo \
	AUTH=$(UID):$(GID) \
	AGENT=$(AGENT) \
	VENDOR=$(VENDOR) \
	BUILD_ID=$(BUILD_ID) \
	DEVPKGS=$(sort $(DEVPKGS)) \
	| sha256sum | cut -f1 -d\ )

ifeq ($(strip $(AGENT.$(AGENT))),)
$(error Unknown devkit.agent '$(AGENT)'. Supported: aider, claude, codex, copilot, gemini, opencode, grok, vibe)
endif

$(foreach f,HOMEURL INST LINK BIN CONFDIR,$(eval $(f)=$(patsubst $(f)=%,%,$(filter $(f)=%,$(AGENT.$(AGENT))))))

get-github-release = $(shell $(CURL) -fsSL -o /dev/null -w '%{url_effective}' '$(HOMEURL)' | sed -n 's,.*/tag/v\?,,p')

UID := $(shell id -u)
GID := $(shell id -g)

ifneq ($(filter shell,$(MAKECMDGOALS)),)
PODMAN_ENTRYPOINT := --entrypoint='["/.devkit/entry","$(DEVSHELL)"]'
endif

PODMAN_ARGS = \
	--env=LANG=C.UTF8 \
	--env=EDITOR=$(EDITOR) \
	--tty --interactive \
	--workdir='/srv/$(PROJNAME)'
PODMAN_VOLUMES = \
	--volume=$(GITPROJDIR):/srv/$(PROJNAME):rw,Z \
	--volume=$(HOME)/$(CONFDIR):/home/user/$(CONFDIR):rw,Z \
	$(addprefix --volume=,$(VOLUMES))

PODMAN_CONTAINER = $(AGENT)-for-$(PROJNAME)
PODMAN_IMAGE = localhost/devkit/$(PROJNAME):$(AGENT)

endif # not SIMPLE_GOALS

.PHONY: _create-image-ubuntu $(PUBLIC_GOALS)
.ONESHELL:

help:
	@echo ""
	echo "Usage: $(PROG) [options] [ $(strip $(subst ||,,|$(addprefix | ,$(PUBLIC_GOALS)))) ]"
	echo ""
	echo "The project allows you to manage isolated containers with AI agents."
	echo ""
	echo "Options:"
	echo "  --root            connect to the running container as root;"
	echo "  --agent=AGENT     use a different agent;"
	echo "  --workdir=DIR     run the agent in the DIR directory;"
	echo "  -V, --version     output version information and exit;"
	echo "  -h, --help        display this help and exit."
	echo ""
	echo "Commands:"
	echo " init        creates the initial configuration in git-config."
	echo " list        shows all devkit known images."
	echo " check       shows current and available agent versions."
	echo " upgrade     upgrades podman image for current devkit."
	echo " shell       run shell inside devkit container."
	echo " run         starts devkit container."
	echo " clean       deletes all images for the current devkit."
	echo " clean-all   deletes all devkit images."
	echo " version     output version information and exit."
	echo " help        display this help and exit."
	echo ""
	echo "Report bugs to authors."
	echo ""

version:
	@echo "devkit version $(VERSION)"
	echo ""
	echo "Copyright (C) 2026  Alexey Gladkov."
	echo ""
	echo "devkit comes with ABSOLUTELY NO WARRANTY. This is free software, and you"
	echo "are welcome to redistribute it under certain conditions."
	echo "See the GNU General Public Licence for details."

init:
	$(Q)if ! $(GIT_CONFIG_GET) devkit.agent >/dev/null 2>&1; then
	  $(GIT_CONFIG_SET) devkit.agent "$(AGENT)";
	else
	  echo "Discovered the existing configuration and cowardly refuse to break it." >&2;
	fi

ubuntu.packages.npm = npm
ubuntu.packages.scr = bash curl

_create-image-ubuntu: $(if $(filter upgrade,$(MAKECMDGOALS)),clean)
	$(Q)image="`$(PODMAN) image list --filter label=local.devkit.hash=$(SHAHASH) --format '{{.Id}}' | head -1`"
	current="`$(PODMAN) image list --filter 'reference=$(PODMAN_IMAGE)' --format '{{.Id}}' | head -1`"
	[ -z "$$current" ] || [ "$$current" = "$$image" ] || $(PODMAN) image rm -f '$(PODMAN_IMAGE)'
	[ -z "$$image" ] || {
	   $(PODMAN) image tag "$$image" '$(PODMAN_IMAGE)'
	   exit
	}
	$(PODMAN) image build --tag="$(PODMAN_IMAGE)" $(addprefix --volume=,$(BUILD_VOLUMES)) \
	  --layers=false --force-rm --format=docker --file=- <<-'EOF'
	  FROM docker.io/library/ubuntu:latest
	  USER root
	  ENV PATH=/root/bin:/root/.local/bin:$$PATH
	  SHELL ["/bin/bash", "-eo", "pipefail", "-c"]
	  RUN mkdir -p -- /.devkit
	  RUN printf >/.devkit/entry '%s\n' \
	  '#!/bin/bash -efu' \
	  '[ ! -d /.devkit/hooks.d ] || run-parts --lsbsysinit --arg=start /.devkit/hooks.d' \
	  'exec "$$@"'; \
	  chmod 755 /.devkit/entry
	  RUN min="`sed -ne 's,^UID_MIN[[:space:]]*,,p' /etc/login.defs`"; getent passwd | while IFS=: read -r name _ uid _; do [ "$$uid" -lt "$$min" ] || userdel -rf "$$name"; done
	  RUN groupadd -g "$(GID)" user; useradd --uid="$(UID)" --gid="$(GID)" -d /home/user -m user
	  RUN apt-get -y -q$(if $(Q),qq) update
	  RUN apt-get -y -q$(if $(Q),qq) --no-install-recommends install $(sort ca-certificates bash vim-tiny curl tar debianutils $(DEVPKGS) $(ubuntu.packages.$(INST)))
	  RUN apt-get -y -q$(if $(Q),qq) clean; rm -rf /var/lib/apt/lists/*
	  RUN find /root -type d | xargs -r chmod -R g+rx,o+rx
	  RUN [ "$(INST)" != npm ] || { npm install -g "$(LINK)" --omit=dev;  rm -rf /root/.npm /root/.cache; }
	  RUN [ "$(INST)" != scr ] || { curl -fsSL "$(LINK)" | bash; }
	  SHELL ["/bin/bash", "-eio", "pipefail", "-c"]
	  RUN bin="`command -v $(BIN)`"; [ "$$bin" = "/usr/local/bin/$(BIN)" ] || ln -vs -- "$$bin" "/usr/local/bin/$(BIN)"
	  SHELL ["/bin/bash", "-eo", "pipefail", "-c"]
	  RUN :; $(BUILD_COMMAND)
	  LABEL local.devkit.hash=$(SHAHASH)
	  LABEL local.devkit.agent=$(AGENT)
	  LABEL local.devkit.agent.version=$(get-github-release)
	  LABEL local.devkit.build.id=$(BUILD_ID)
	  ENTRYPOINT ["/.devkit/entry","/usr/local/bin/$(BIN)"]
	EOF

run: _create-image-$(VENDOR)
	$(Q)set -e --; i=0; while [ $$i -lt $${NARGS:-0} ]; do
	  eval "a=\"\$${ARG$$i-}\""; set -- "$$@" "$$a";
	  i=$$(( $$i + 1 ));
	done
	[ -z '$(CONFDIR)' ] || mkdir -p -- $(HOME)/$(CONFDIR)
	if ! $(PODMAN) container exists '$(PODMAN_CONTAINER)'; then
	  $(PODMAN) container run $(PODMAN_ARGS) \
	    --name '$(PODMAN_CONTAINER)' $(PODMAN_VOLUMES) \
	    --rm --log-driver=none --network=host --userns=keep-id --memory=$(LIMIT_MEMORY) \
	    --user='$(UID):$(GID)' \
	    $(PODMAN_ENTRYPOINT) -- '$(PODMAN_IMAGE)' "$$@" $(ARGS);
	else
	  $(PODMAN) container exec $(PODMAN_ARGS) \
	    --user='$(if $(ROOT),root,$(UID):$(GID))' \
	    -- '$(PODMAN_CONTAINER)' $(DEVSHELL) "$$@" $(ARGS);
	fi

shell: run

check:
	$(Q)set -e --;
	avail_ver="$(get-github-release)";
	image_ver="`$(PODMAN) image list --filter 'reference=$(PODMAN_IMAGE)' --format '{{index .Labels "local.devkit.agent.version"}}'`";
	echo "The $(AGENT) information:";
	echo " - release home page: $(HOMEURL)";
	echo " -  config directory: ~/$(CONFDIR)";
	echo " - available version: $${avail_ver:-*unavailable*}";
	echo " -   current version: $${image_ver:-*unknown*}";

clean-all:
	$(Q)$(PODMAN) image list --format '{{.Id}}' --filter 'label=local.devkit.agent'  | xargs -r $(PODMAN) image rm -f

clean:
	$(Q)$(PODMAN) image list --format '{{.Id}}' --filter 'reference=$(PODMAN_IMAGE)' | xargs -r $(PODMAN) image rm -f

upgrade: clean _create-image-$(VENDOR)

list:
	$(Q)$(PODMAN) image list --filter label=local.devkit.agent
