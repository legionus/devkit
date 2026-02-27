# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026  Alexey Gladkov <gladkov.alexey@gmail.com>

CURNAME = devkit
CURFILE = $(lastword $(MAKEFILE_LIST))
PROG ?= make -f $(CURFILE) --
VERSION = 1

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

ifeq ($(filter help clean clean-all list,$(MAKECMDGOALS)),)
$(if $(PROJNAME),,$(error Unable to locate the git repository))
endif

UID := $(shell id -u)
GID := $(shell id -g)

DEF_AGENT = copilot
DEF_DEVNAME = $(PROJNAME)
DEF_DEVSHELL = /bin/bash
DEF_EDITOR = /usr/bin/editor

ifneq ($(GITPROJDIR),)
VENDOR  = ubuntu
AGENT   = $(shell $(GIT) config get       devkit.agent    || echo $(DEF_AGENT))
DEVNAME = $(shell $(GIT) config get       devkit.name     || echo $(DEF_DEVNAME))
DEVSHELL= $(shell $(GIT) config get       devkit.shell    || echo $(DEF_DEVSHELL))
EDITOR  = $(shell $(GIT) config get       devkit.editor   || echo $(DEF_EDITOR))
DEVPKGS = $(shell $(GIT) config get --all devkit.packages)
VOLUMES = $(shell $(GIT) config get --all devkit.volumes)
SHAHASH = $(shell echo $(UID):$(GID) $(AGENT) $(VENDOR) $(sort $(DEVPKGS)) | sha256sum | cut -f1 -d\ )

BUILD_CMD = $(shell $(GIT) config get devkit.build-cmd)
BUILD_VOL = $(shell $(GIT) config get devkit.build-dir)
endif

get-image-id       = $(shell $(PODMAN) image list --filter label=local.devkit.hash=$(SHAHASH) --format '{{.Id}}')
get-github-release = $(shell $(CURL) -fsSL -o /dev/null -w '%{url_effective}' -L '$(1)' | sed -n 's,.*/tag/v\?,,p')

ubuntu.packages.npm = npm
ubuntu.packages.scr = bash curl

AGENT.opencode = HOMEURL=https://github.com/anomalyco/opencode/releases/latest       INST=scr LINK=https://opencode.ai/install   BIN=opencode CONFDIR=.config/opencode
AGENT.copilot  = HOMEURL=https://github.com/github/copilot-cli/releases/latest       INST=scr LINK=https://gh.io/copilot-install BIN=copilot  CONFDIR=.copilot
AGENT.claude   = HOMEURL=https://github.com/anthropics/claude-code/releases/latest   INST=scr LINK=https://claude.ai/install.sh  BIN=claude   CONFDIR=.claude
AGENT.aider    = HOMEURL=https://github.com/Aider-AI/aider/releases/latest           INST=scr LINK=https://aider.chat/install.sh BIN=aider    CONFDIR=.aider
AGENT.gemini   = HOMEURL=https://github.com/google-gemini/gemini-cli/releases/latest INST=npm LINK=@google/gemini-cli            BIN=gemini   CONFDIR=.gemini
AGENT.codex    = HOMEURL=https://github.com/openai/codex/releases/latest             INST=npm LINK=@openai/codex                 BIN=codex    CONFDIR=.codex
AGENT.grok     = HOMEURL=https://github.com/superagent-ai/grok-cli/releases/latest   INST=npm LINK=@vibe-kit/grok-cli            BIN=grok     CONFDIR=.grok

ifeq ($(strip $(AGENT.$(AGENT))),)
$(error Unknown devkit.agent '$(AGENT)'. Supported: aider, claude, codex, copilot, gemini, opencode, grok)
endif

$(foreach f,HOMEURL INST LINK BIN CONFDIR,$(eval $(f)=$(patsubst $(f)=%,%,$(filter $(f)=%,$(AGENT.$(AGENT))))))

.PHONY: _check-image _create-image-$(VENDOR) help version init clean clean-all check upgrade list shell run
.ONESHELL:

help:
	@echo ""
	echo "Usage: $(PROG) [ help$(foreach x,version init clean check upgrade list shell run, | $(x)) ]"
	echo ""
	echo "The project allows you to manage isolated containers with AI agents."
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
	$(Q)if ! $(GIT) config get devkit.name >/dev/null 2>&1; then
	  $(GIT) config set devkit.name "$(DEVNAME)";
	  $(GIT) config set devkit.agent "$(AGENT)";
	else
	  echo "Discovered the existing configuration and cowardly refuse to break it." >&2;
	fi

_create-image-ubuntu:
	$(Q)[ -n "$(get-image-id)" ] || printf '%s\n' \
	  'FROM docker.io/library/ubuntu:latest' \
	  'USER root' \
	  'ENV PATH=/root/bin:/root/.local/bin:$$PATH' \
	  'SHELL ["/bin/bash", "-eo", "pipefail", "-c"]' \
	  'RUN min="`sed -ne "s,^UID_MIN[[:space:]]*,,p" /etc/login.defs`"; getent passwd | while IFS=: read -r name _ uid _; do [ "$$uid" -lt "$$min" ] || userdel -rf "$$name"; done' \
	  'RUN groupadd -g "$(GID)" user; useradd --uid="$(UID)" --gid="$(GID)" -d /home/user -m user' \
	  'RUN apt-get -y -q$(if $(Q),qq) update' \
	  'RUN apt-get -y -q$(if $(Q),qq) --no-install-recommends install $(sort ca-certificates bash vim-tiny curl tar $(DEVPKGS) $(ubuntu.packages.$(INST)))' \
	  'RUN apt-get -y -q$(if $(Q),qq) clean; rm -rf /var/lib/apt/lists/*' \
	  'RUN find /root -type d | xargs -r chmod -R g+rx,o+rx' \
	  'RUN [ "$(INST)" != npm ] || { npm install -g "$(LINK)" --omit=dev;  rm -rf /root/.npm /root/.cache; }' \
	  'RUN [ "$(INST)" != scr ] || { curl -fsSL "$(LINK)" | bash; }' \
	  'SHELL ["/bin/bash", "-eio", "pipefail", "-c"]' \
	  'RUN bin="`command -v $(BIN)`"; [ "$$bin" = "/usr/local/bin/$(BIN)" ] || ln -vs -- "$$bin" "/usr/local/bin/$(BIN)"' \
	  'RUN [ -z "$(BUILDCMD)" ] || $(BUILDCMD)' \
	  'LABEL local.devkit.name=$(DEVNAME)' \
	  'LABEL local.devkit.hash=$(SHAHASH)' \
	  'LABEL local.devkit.agent=$(AGENT)' \
	  'LABEL local.devkit.agent.version=$(call get-github-release,$(HOMEURL))' \
	  'ENTRYPOINT ["/usr/local/bin/$(BIN)"]' |
	$(PODMAN) image build --layers=false --force-rm --format=docker --file=- \
	  $(if $(BUILD_VOL),--volume=$(BUILD_VOL):/.host:ro) \
	  --tag="localhost/$(CURNAME)/$(DEVNAME):latest"

_check-image:
	$(Q)[ -n "$(get-image-id)" ] || $(MAKE) -f "$(CURFILE)" _create-image-$(VENDOR)
	[ -z '$(CONFDIR)' ] || mkdir -p -- $(HOME)/$(CONFDIR)

ifneq ($(filter shell,$(MAKECMDGOALS)),)
PODMAN_ENTRYPOINT := --entrypoint=$(DEVSHELL)
endif

PODMAN_ENV = \
	--env=LANG=C.UTF8 \
	--env=EDITOR=$(EDITOR)
PODMAN_VOLUMES = \
	--volume=$(GITPROJDIR):/srv/$(PROJNAME):rw,Z \
	--volume=$(HOME)/$(CONFDIR):/home/user/$(CONFDIR):rw,Z \
	$(addprefix --volume=,$(VOLUMES))

run: _check-image
	$(Q)set --; i=0; while [ $$i -lt $${NARGS:-0} ]; do
	  eval "a=\"\$${ARG$$i-}\""; set -- "$$@" "$$a";
	  i=$$(( $$i + 1 ));
	done
	if ! $(PODMAN) container exists '$(AGENT)-for-$(PROJNAME)'; then
	  $(PODMAN) container run --tty --interactive \
	    --name '$(AGENT)-for-$(PROJNAME)' \
	    $(PODMAN_ENV) $(PODMAN_VOLUMES) \
	    --rm --log-driver=none \
	    --network=host --userns=keep-id \
	    --user='$(UID):$(GID)' \
	    --workdir='/srv/$(PROJNAME)' \
	    $(PODMAN_ENTRYPOINT) -- '$(get-image-id)' "$$@" $(ARGS);
	else
	  $(PODMAN) container exec --tty --interactive \
	    $(PODMAN_ENV) \
	    --user='$(if $(ROOT),root,$(UID):$(GID))' \
	    --workdir='/srv/$(PROJNAME)' \
	    -- '$(AGENT)-for-$(PROJNAME)' $(DEVSHELL) "$$@" $(ARGS);
	fi

shell: run
	@:

check:
	$(Q)image_id="$(get-image-id)";
	avail_ver="$(call get-github-release,$(HOMEURL))";
	image_ver="`[ -z "$$image_id" ] || $(PODMAN) image inspect "$$image_id" --format '{{index .Labels "local.devkit.agent.version"}}'`";
	echo "The $(AGENT) information:";
	echo " - release home page: $(HOMEURL)";
	echo " -  config directory: ~/$(CONFDIR)";
	echo " - available version: $${avail_ver:-*unavailable*}";
	echo " -   current version: $${image_ver:-*unknown*}";

clean-all:
	$(Q)$(PODMAN) image list --filter label=local.devkit.name --format '{{.Id}}' | xargs -r $(PODMAN) image rm

clean:
	$(Q)$(PODMAN) image list --filter label=local.devkit.name=$(DEVNAME) --format '{{.Id}}' | xargs -r $(PODMAN) image rm

upgrade: clean
	$(Q)$(MAKE) -f "$(CURFILE)" _create-image-$(VENDOR)

list:
	$(Q)$(PODMAN) image list --filter label=local.devkit.name
