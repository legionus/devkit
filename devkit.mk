# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026  Alexey Gladkov <gladkov.alexey@gmail.com>
# Copyright (C) 2026  Wladmis <dev@wladmis.org>

CURFILE := $(lastword $(MAKEFILE_LIST))
PROG ?= make -f $(CURFILE) --
VERSION = 5
DEVKIT_HOMEURL = https://github.com/devkit-dev/devkit/releases/latest
DEVKIT_WORKDIR = $(realpath $(dir $(CURFILE)))

V = $(VERBOSE)
Q = $(if $(V),,@)

SIMPLE_GOALS = help version list clean-all self-upgrade
PUBLIC_GOALS = $(SIMPLE_GOALS) clean init check upgrade exec shell run

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

get-if-true = $(if $(filter true yes on 1,$(1)),true)
get-github-release = $(CURL) -fsSL -o /dev/null -w '%{url_effective}' '$(1)' | sed -n 's,.*/tag/v\?,,p'

SUBCMDS = $(basename $(notdir $(wildcard $(DEVKIT_WORKDIR)/subcmds/*.mk)))

ifeq ($(filter $(SIMPLE_GOALS),$(MAKECMDGOALS)),) # not SIMPLE_GOALS
GITPROJDIR = $(shell $(GIT) rev-parse --show-toplevel 2>/dev/null)
PROJNAME   = $(notdir $(GITPROJDIR))
WORKDIR    = /srv/$(PROJNAME)

$(if $(PROJNAME),,$(error Unable to locate the git repository))

VENDOR   = ubuntu
AGENT    = $(shell $(GIT_CONFIG_GET)     devkit.agent    || echo dummy)
DEVSHELL = $(shell $(GIT_CONFIG_GET)     devkit.shell    || echo /bin/bash)
EDITOR   = $(shell $(GIT_CONFIG_GET)     devkit.editor   || echo /usr/bin/editor)
HOOKS    = $(shell $(GIT_CONFIG_GET)     devkit.hooks-path)
DEVPKGS  = $(shell $(GIT_CONFIG_GET_ALL) devkit.packages)
VOLUMES  = $(shell $(GIT_CONFIG_GET_ALL) devkit.volumes)
ENVFILES = $(shell $(GIT_CONFIG_GET_ALL) devkit.env-file)
CAPS     = $(shell $(GIT_CONFIG_GET_ALL) devkit.caps)

LIMIT_MEMORY = $(shell $(GIT_CONFIG_GET) devkit.limit-memory || echo 0)

CHECK_UPGRADE = $(shell $(GIT_CONFIG_GET) devkit.check-upgrade || echo true)

BUILD_COMMAND = $(shell $(GIT_CONFIG_GET)     devkit.build-command)
BUILD_VOLUMES = $(shell $(GIT_CONFIG_GET_ALL) devkit.build-volumes)
BUILD_ID      = $(shell $(GIT_CONFIG_GET)     devkit.build-id || echo none)
BUILD_COMMAND_HASH = $(shell $(GIT_CONFIG_GET) devkit.build-command 2>/dev/null | sha256sum | cut -f1 -d\ )

ifneq ($(AGENT),dummy)
$(foreach cmd,$(SUBCMDS),$(eval $(cmd)_ENABLED = $(call get-if-true,$(shell $(GIT_CONFIG_GET) devkit.$(cmd) ||:))))
endif

PODMAN_BUILD_ARGS = --layers

SHAHASH = $(shell echo \
	AUTH=$(UID):$(GID) \
	AGENT=$(AGENT) \
	VENDOR=$(VENDOR) \
	VERSION=$(VERSION) \
	BUILD_ID=$(BUILD_ID) \
	BUILD_COMMAND=$(BUILD_COMMAND_HASH) \
	SASHIKO=$(sashiko_ENABLED) \
	OLLAMA=$(ollama_ENABLED) \
	DEVPKGS=$(sort $(DEVPKGS)) \
	| sha256sum | cut -f1 -d\ )

ifneq ($(filter upgrade,$(MAKECMDGOALS)),)
PODMAN_BUILD_ARGS += --no-cache --pull=always
endif

AGENTS_DIR = $(dir $(CURFILE))/agents
AGENT.include = $(AGENTS_DIR)/$(AGENT).mk

ifeq ($(wildcard $(AGENT.include)),)
known_agents = $(patsubst %.mk,%,$(notdir $(wildcard $(AGENTS_DIR)/*.mk)))
$(error Unknown devkit.agent '$(AGENT)'. Supported: $(sort $(known_agents)))
endif

include $(DEVKIT_WORKDIR)/agents/$(AGENT).mk

UID := $(shell id -u)
GID := $(shell id -g)

ifneq ($(filter shell,$(MAKECMDGOALS)),)
PODMAN_ENTRYPOINT := --entrypoint='["/.devkit/entry","$(DEVSHELL)"]'
endif

ifneq ($(filter exec,$(MAKECMDGOALS)),)
PODMAN_ENTRYPOINT := --entrypoint='["/.devkit/entry"]'
DEVSHELL :=
endif

ifneq ($(wildcard $(HOOKS)),)
VOLUMES += $(HOOKS):/.devkit/hooks.d:ro
endif

ifneq ($(DATADIR),)
VOLUMES += $(HOME)/$(DATADIR):/home/user/$(DATADIR):rw,Z
endif

ifneq ($(CONFDIR),)
VOLUMES += $(HOME)/$(CONFDIR):/home/user/$(CONFDIR):rw,Z
endif

CONFFILE_OPTIONS = rw,Z
VOLUMES += $(foreach f,$(CONFFILES),$(if $(wildcard $(HOME)/$(f)),$(HOME)/$(f):/home/user/$(f):$(CONFFILE_OPTIONS)))

PODMAN_ARGS = \
	--env=LANG=C.UTF8 \
	--env=EDITOR=$(EDITOR) \
	--tty --interactive \
	--user='$(if $(ROOT),root,$(UID):$(GID))' \
	--workdir='$(WORKDIR)'
PODMAN_RUNTIME_ARGS = $(PODMAN_ARGS) \
	$(addprefix --env-file=,$(ENVFILES)) \
	$(addprefix --cap-del=,$(patsubst -%,%,$(filter -%,$(CAPS)))) \
	$(addprefix --cap-add=,$(patsubst +%,%,$(filter +%,$(CAPS)))) \
	--tmpfs /run \
	--tmpfs /tmp \
	--rm --network=host --userns=keep-id --memory=$(LIMIT_MEMORY)
PODMAN_VOLUMES = \
	--volume=$(GITPROJDIR):/srv/$(PROJNAME):rw,Z \
	$(addprefix --volume=,$(VOLUMES))

PODMAN_CONTAINER = $(AGENT)-for-$(PROJNAME)
PODMAN_IMAGE = localhost/devkit/$(PROJNAME):$(AGENT)

endif # not SIMPLE_GOALS

.PHONY: _create-image-ubuntu _create_local_dirs _check-devkit-version _check-self-upgrade _check-version _check-none $(PUBLIC_GOALS)
.ONESHELL:

help:
	@echo ""
	echo "Usage: $(PROG) [OPTION]... COMMAND [ARGS]..."
	echo ""
	echo "The project allows you to manage isolated containers with AI agents."
	echo ""
	echo "Options:"
	echo "  --root            run the container as root;"
	echo "  --agent=AGENT     use a different agent;"
	echo "  --workdir=DIR     use DIR as the project directory;"
	echo "  -v, --verbose     print a message for each action;"
	echo "  -V, --version     output version information and exit;"
	echo "  -h, --help        display this help and exit."
	echo ""
	echo "General commands:"
	echo " init            creates the initial configuration in git-config."
	echo " list            shows all devkit known images."
	echo " check           shows current and available agent versions."
	echo " upgrade         upgrades podman image for current devkit."
	echo " self-upgrade    upgrade devkit to the latest version."
	echo " exec            run a command in the devkit container."
	echo " shell           open a shell in the devkit container."
	echo " run             start the configured agent."
	echo " clean           deletes the image for the current agent."
	echo " clean-all       deletes all devkit images."
	echo " version         output version information and exit."
	echo " help            display this help and exit."
	echo ""
	for cmd in $(SUBCMDS); do
	 $(MAKE) --no-print-directory -f "$(DEVKIT_WORKDIR)/subcmds/$$cmd.mk" "$$cmd-help"
	done
	echo "Report bugs to authors."
	echo ""
	echo "Configuration (git config):"
	echo " devkit.check-upgrade  check for new devkit version on run (default: true)."

version:
	@echo "devkit version $(VERSION)"
	echo ""
	echo "Copyright (C) 2026  Alexey Gladkov."
	echo "Copyright (C) 2026  Wladmis."
	echo ""
	echo "devkit comes with ABSOLUTELY NO WARRANTY. This is free software, and you"
	echo "are welcome to redistribute it under certain conditions."
	echo "See the GNU General Public Licence for details."

_check-devkit-version:
	$(Q)set -e --;
	avail_ver="`$(call get-github-release,$(DEVKIT_HOMEURL))`";
	echo "devkit information:";
	echo " - release home page: $(DEVKIT_HOMEURL)";
	echo " - available version: $${avail_ver:-*unavailable*}";
	echo " -   current version: $(VERSION)";

_check-version:
	$(Q)set -e --;
	avail_ver="`$(call get-github-release,$(HOMEURL))`";
	image_ver="`$(PODMAN) image list --filter 'reference=$(PODMAN_IMAGE)' --format '{{index .Labels "local.devkit.agent.version"}}'`";
	echo "The $(AGENT) information:";
	echo " - release home page: $(HOMEURL)";
	echo " -  config directory: ~/$(CONFDIR)";
	echo " - available version: $${avail_ver:-*unavailable*}";
	echo " -   current version: $${image_ver:-*unknown*}";

_check-dummy:
	$(Q)set -e --;
	echo "This is a project container without any AI agents."

_check-self-upgrade:
	$(Q)if [ '$(CHECK_UPGRADE)' != 'false' ]; then \
	  avail_ver="`$(call get-github-release,$(DEVKIT_HOMEURL))`"; \
	  if [ -n "$$avail_ver" ] && [ "$$avail_ver" != "$(VERSION)" ]; then \
	    echo "devkit: new version $$avail_ver is available (current: $(VERSION))." >&2; \
	    echo "devkit: run \`devkit self-upgrade' to upgrade." >&2; \
	  fi; \
	fi

check: _check-devkit-version _check-$(if $(HOMEURL),version,dummy)

init:
	$(Q)if ! $(GIT_CONFIG_GET) devkit.agent >/dev/null 2>&1; then
	  $(GIT_CONFIG_SET) devkit.agent "$(AGENT)";
	else
	  echo "Discovered the existing configuration and cowardly refuse to break it." >&2;
	fi

_create_local_dirs:
	$(Q)set -e --;
	[ -z '$(CONFDIR)' ] || mkdir -p -- $(HOME)/$(CONFDIR)
	[ -z '$(DATADIR)' ] || mkdir -p -- $(HOME)/$(DATADIR)

ubuntu.packages     = ca-certificates git bash vim-tiny curl tar debianutils
ubuntu.packages.npm = npm
ubuntu.packages.pip = python3-venv
ubuntu.packages.scr = bash curl

PIP_VENV = /opt/devkit/agent

COREPKGS    = $(sort $(ubuntu.packages))
AGENTPKGS   = $(sort $(filter-out $(COREPKGS),$(PACKAGES) $(ubuntu.packages.$(INST))))
USERPKGS    = $(sort $(filter-out $(COREPKGS) $(AGENTPKGS),$(DEVPKGS)))

ubuntu-install = RUN apt-get -y -q$(if $(Q),qq) update; apt-get -y -q$(if $(Q),qq) --no-install-recommends install $(1); apt-get -y -q$(if $(Q),qq) clean; rm -rf /var/lib/apt/lists/*

run.install.npm = npm install -g "$(LINK)" --omit=dev && rm -rf /root/.npm /root/.cache
run.install.pip = python3 -m venv "$(PIP_VENV)" && "$(PIP_VENV)/bin/python" -m pip install $(if $(Q),-q) --no-cache-dir "$(LINK)" && "$(PIP_VENV)/bin/python" -m pip check
run.install.scr = curl -fsSL "$(LINK)" | $(SCR_ENV) bash

_create-image-ubuntu: $(if $(filter upgrade,$(MAKECMDGOALS)),clean)
	$(Q)image=
	if [ -z '$(filter upgrade,$(MAKECMDGOALS))' ]; then
	  image="`$(PODMAN) image list --filter label=local.devkit.hash=$(SHAHASH) --format '{{.Id}}' | head -1`"
	fi
	current="`$(PODMAN) image list --filter 'reference=$(PODMAN_IMAGE)' --format '{{.Id}}' | head -1`"
	[ -z "$$current" ] || [ "$$current" = "$$image" ] || $(PODMAN) image rm -f '$(PODMAN_IMAGE)'
	[ -z "$$image" ] || {
	   $(PODMAN) image tag "$$image" '$(PODMAN_IMAGE)'
	   exit
	}
	agent_version="`$(call get-github-release,$(HOMEURL))`"
	$(PODMAN) image build --tag="$(PODMAN_IMAGE)" \
	  --label=local.devkit.agent=$(AGENT) \
	  --label=local.devkit.agent.version="$$agent_version" \
	  --label=local.devkit.build.id=$(BUILD_ID) \
	  --label=local.devkit.hash=$(SHAHASH) \
	  --build-arg=DEVKIT_AGENT_VERSION="$$agent_version" \
	  --build-arg=DEVKIT_BUILD_ID="$(BUILD_ID)" \
	  $(addprefix --volume=,$(BUILD_VOLUMES)) \
	  $(PODMAN_BUILD_ARGS) --force-rm --format=docker --file=- <<-'EOF'
	  FROM docker.io/library/ubuntu:latest
	  USER root
	  ENV DEBIAN_FRONTEND=noninteractive
	  ENV PATH=/home/user/$(SASHIKO_HOME)/bin:/home/user/bin:/home/user/.local/bin:/root/bin:/root/.local/bin:$$PATH
	  SHELL ["/bin/bash", "-eo", "pipefail", "-c"]
	  RUN mkdir -p -- /.devkit
	  RUN printf >/.devkit/entry '%s\n' \
	  '#!/bin/bash -efu' \
	  '[ ! -d /.devkit/hooks.d ] || run-parts --lsbsysinit --arg=start /.devkit/hooks.d' \
	  'exec "$$@"'; \
	  chmod 755 /.devkit/entry
	  RUN min="`sed -ne 's,^UID_MIN[[:space:]]*,,p' /etc/login.defs`"; getent passwd | while IFS=: read -r name _ uid _; do [ "$$uid" -lt "$$min" ] || userdel -rf "$$name"; done
	  RUN groupadd -g "$(GID)" user; useradd --uid="$(UID)" --gid="$(GID)" -d /home/user -m user
	  RUN mkdir -p -- /home/user/.config /home/user/.local/{bin,lib,state,share}
	  RUN chown -R '$(UID):$(GID)' /home/user
	  $(call ubuntu-install,$(COREPKGS))
	  $(if $(AGENTPKGS),$(call ubuntu-install,$(AGENTPKGS)))
	  RUN find /root -type d | xargs -r chmod -R g+rx,o+rx
	  ARG DEVKIT_AGENT_VERSION
	  RUN : "$$DEVKIT_AGENT_VERSION"; $(run.install.$(INST))
	  $(if $(USERPKGS),$(call ubuntu-install,$(USERPKGS)))
	  $(foreach cmd,$(SUBCMDS),\
	    $(if $($(cmd)_ENABLED),# <<< Section for $(cmd)
	      $(call ubuntu-install,$($(cmd).PKGS))
	      $($(cmd).BUILD)
	      # >>>))
	  SHELL ["/bin/bash", "-eio", "pipefail", "-c"]
	  RUN bin="`command -v $(BIN)`" && [ -x "$$bin" ] && { [ "$$bin" = "/usr/local/bin/agent" ] || ln -vs -- "$$bin" "/usr/local/bin/agent"; }
	  SHELL ["/bin/bash", "-eo", "pipefail", "-c"]
	  ARG DEVKIT_BUILD_ID
	  RUN : "$$DEVKIT_BUILD_ID"; $(BUILD_COMMAND)
	  ENTRYPOINT ["/.devkit/entry","/usr/local/bin/agent"]
	EOF

PASSTHRU_SHELL_ARGS = i=0; while [ $$i -lt $${NARGS:-0} ]; do eval "a=\"\$${ARG$$i-}\""; set -- "$$@" "$$a"; i=$$(($$i+1)); done

run: _check-self-upgrade _create_local_dirs _create-image-$(VENDOR)
	$(Q)set -e --; $(PASSTHRU_SHELL_ARGS);
	if ! $(PODMAN) container exists '$(PODMAN_CONTAINER)'; then
	  $(PODMAN) container run $(PODMAN_RUNTIME_ARGS) $(PODMAN_VOLUMES) \
	    --name '$(PODMAN_CONTAINER)' --log-driver=none \
	    $(PODMAN_ENTRYPOINT) -- '$(PODMAN_IMAGE)' "$$@" $(ARGS);
	else
	  $(PODMAN) container exec $(PODMAN_ARGS) \
	    -- '$(PODMAN_CONTAINER)' $(DEVSHELL) "$$@" $(ARGS);
	fi

shell: run
exec: run

clean-all:
	$(Q)$(PODMAN) image list --format '{{.Id}}' --filter 'label=local.devkit.agent'  | xargs -r $(PODMAN) image rm -f

clean:
	$(Q)$(PODMAN) image list --format '{{.Id}}' --filter 'reference=$(PODMAN_IMAGE)' | xargs -r $(PODMAN) image rm -f

upgrade: clean _create-image-$(VENDOR)

list:
	$(Q)$(PODMAN) image list --filter label=local.devkit.agent

self-upgrade:
	$(Q)set -e --;
	avail_ver="`$(call get-github-release,$(DEVKIT_HOMEURL))`";
	if [ "$${avail_ver}" = "$(VERSION)" ]; then
	  echo "devkit is up to date ($(VERSION)).";
	  exit 0;
	fi;
	if [ -z "$${avail_ver}" ]; then
	  echo "devkit: unable to determine the latest version." >&2;
	  exit 1;
	fi;
	bin_dir="";
	for d in "$$HOME/bin" "$$HOME/.local/bin"; do
	  case ":$${PATH-}:" in
	    *:"$$d":*) bin_dir="$$d"; break ;;
	  esac;
	done;
	if [ -z "$${bin_dir}" ]; then
	  echo "devkit: error: neither $$HOME/bin nor $$HOME/.local/bin is in PATH." >&2;
	  exit 1;
	fi;
	dest_dir="$$HOME/.local/share/devkit";
	archive_url="$(DEVKIT_HOMEURL:releases/latest=archive/refs/tags/v$${avail_ver}.tar.gz)";
	rm -rf -- "$$dest_dir";
	mkdir -p -- "$$dest_dir";
	$(CURL) -fsSL "$$archive_url" | tar -xzf - -C "$$dest_dir" --strip-components=1;
	mkdir -p -- "$${bin_dir}";
	ln -sf -- "$$dest_dir/devkit.sh" "$${bin_dir}/devkit";
	echo "devkit upgraded: $(VERSION) -> $${avail_ver}";

_container-kill:
	$(Q)set -e --;
	! $(PODMAN) container exists '$(_CONTAINER)' ||
	  $(PODMAN) container kill '$(_CONTAINER)'

_container-logs:
	$(Q)set -e --; $(PASSTHRU_SHELL_ARGS);
	$(PODMAN) container logs '$(_CONTAINER)' "$$@" $(ARGS);

_disabled:
	@echo "devkit: $(firstword $(subst -, ,$(firstword $(MAKECMDGOALS)))) support is not enabled in git-config."

.PHONY: _container-kill _container-logs _disabled

-include $(wildcard $(DEVKIT_WORKDIR)/subcmds/*.mk)
