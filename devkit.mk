# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026  Alexey Gladkov <gladkov.alexey@gmail.com>

CURFILE := $(lastword $(MAKEFILE_LIST))
PROG ?= make -f $(CURFILE) --
VERSION = 5

V = $(VERBOSE)
Q = $(if $(V),,@)

SIMPLE_GOALS = help version list clean-all
SASHIKO_GOALS = sashiko sashiko-daemon sashiko-kill sashiko-logs
PUBLIC_GOALS = $(SIMPLE_GOALS) $(SASHIKO_GOALS) clean init check upgrade exec shell run

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

ifeq ($(filter $(SIMPLE_GOALS),$(MAKECMDGOALS)),) # not SIMPLE_GOALS
GITPROJDIR = $(shell $(GIT) rev-parse --show-toplevel 2>/dev/null)
PROJNAME   = $(notdir $(GITPROJDIR))
WORKDIR    = /srv/$(PROJNAME)

$(if $(PROJNAME),,$(error Unable to locate the git repository))

VENDOR   = ubuntu
AGENT    = $(shell $(GIT_CONFIG_GET)     devkit.agent    || echo dummy)
DEVSHELL = $(shell $(GIT_CONFIG_GET)     devkit.shell    || echo /bin/bash)
EDITOR   = $(shell $(GIT_CONFIG_GET)     devkit.editor   || echo /usr/bin/editor)
SASHIKO  = $(shell $(GIT_CONFIG_GET)     devkit.sashiko  || echo false)
HOOKS    = $(shell $(GIT_CONFIG_GET)     devkit.hooks-path)
DEVPKGS  = $(shell $(GIT_CONFIG_GET_ALL) devkit.packages)
VOLUMES  = $(shell $(GIT_CONFIG_GET_ALL) devkit.volumes)
ENVFILES = $(shell $(GIT_CONFIG_GET_ALL) devkit.env-file)
CAPS     = $(shell $(GIT_CONFIG_GET_ALL) devkit.caps)

LIMIT_MEMORY = $(shell $(GIT_CONFIG_GET) devkit.limit-memory || echo 0)

BUILD_COMMAND = $(shell $(GIT_CONFIG_GET)     devkit.build-command)
BUILD_VOLUMES = $(shell $(GIT_CONFIG_GET_ALL) devkit.build-volumes)
BUILD_ID      = $(shell $(GIT_CONFIG_GET)     devkit.build-id || echo none)
BUILD_COMMAND_HASH = $(shell $(GIT_CONFIG_GET) devkit.build-command 2>/dev/null | sha256sum | cut -f1 -d\ )

ifneq ($(AGENT),dummy)
SASHIKO_ENABLED = $(filter true yes on 1,$(SASHIKO))
endif

ifneq ($(SASHIKO_ENABLED),)
SASHIKO_PROVIDER = $(shell $(GIT_CONFIG_GET) devkit.sashiko-provider || echo $(AGENT)-cli)
SASHIKO_MODEL    = $(shell $(GIT_CONFIG_GET) devkit.sashiko-model    || echo use-own-agent-model)

SASHIKO_HOME = .local/share/sashiko

VOLUMES += $(HOME)/$(SASHIKO_HOME):/home/user/$(SASHIKO_HOME):rw,Z

ifneq ($(filter sashiko-daemon,$(MAKECMDGOALS)),)
WORKDIR = /home/user/$(SASHIKO_HOME)
endif
endif

SHAHASH = $(shell echo \
	AUTH=$(UID):$(GID) \
	AGENT=$(AGENT) \
	VENDOR=$(VENDOR) \
	VERSION=$(VERSION) \
	BUILD_ID=$(BUILD_ID) \
	BUILD_COMMAND=$(BUILD_COMMAND_HASH) \
	SASHIKO=$(SASHIKO_ENABLED) \
	DEVPKGS=$(sort $(DEVPKGS)) \
	| sha256sum | cut -f1 -d\ )

PODMAN_BUILD_ARGS = --layers
ifneq ($(filter upgrade,$(MAKECMDGOALS)),)
PODMAN_BUILD_ARGS += --no-cache --pull=always
endif

AGENTS_DIR = $(dir $(CURFILE))/agents
AGENT.include = $(AGENTS_DIR)/$(AGENT).mk

ifeq ($(wildcard $(AGENT.include)),)
known_agents = $(patsubst %.mk,%,$(notdir $(wildcard $(AGENTS_DIR)/*.mk)))
$(error Unknown devkit.agent '$(AGENT)'. Supported: $(sort $(known_agents)))
endif

get-github-release = $(CURL) -fsSL -o /dev/null -w '%{url_effective}' '$(HOMEURL)' | sed -n 's,.*/tag/v\?,,p'

include $(dir $(CURFILE))agents/$(AGENT).mk

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
	--rm --network=host --userns=keep-id --memory=$(LIMIT_MEMORY)
PODMAN_VOLUMES = \
	--volume=$(GITPROJDIR):/srv/$(PROJNAME):rw,Z \
	$(addprefix --volume=,$(VOLUMES))

PODMAN_CONTAINER = $(AGENT)-for-$(PROJNAME)
SASHIKO_CONTAINER = $(PODMAN_CONTAINER)-sashiko
PODMAN_IMAGE = localhost/devkit/$(PROJNAME):$(AGENT)

endif # not SIMPLE_GOALS

.PHONY: _create-image-ubuntu _create_local_dirs _check-version _check-none $(PUBLIC_GOALS)
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
	echo " exec            run a command in the devkit container."
	echo " shell           open a shell in the devkit container."
	echo " run             start the configured agent."
	echo " clean           deletes the image for the current agent."
	echo " clean-all       deletes all devkit images."
	echo " version         output version information and exit."
	echo " help            display this help and exit."
	echo ""
	echo "Optional sashiko commands (require: git config devkit.sashiko true):"
	echo " sashiko         start the service if needed and open its CLI."
	echo " sashiko-daemon  start the review daemon."
	echo " sashiko-kill    stop the review daemon."
	echo " sashiko-logs    show review-daemon logs."
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

_check-version:
	$(Q)set -e --;
	avail_ver="`$(get-github-release)`";
	image_ver="`$(PODMAN) image list --filter 'reference=$(PODMAN_IMAGE)' --format '{{index .Labels "local.devkit.agent.version"}}'`";
	echo "The $(AGENT) information:";
	echo " - release home page: $(HOMEURL)";
	echo " -  config directory: ~/$(CONFDIR)";
	echo " - available version: $${avail_ver:-*unavailable*}";
	echo " -   current version: $${image_ver:-*unknown*}";

_check-dummy:
	$(Q)set -e --;
	echo "This is a project container without any AI agents."

check: _check-$(if $(HOMEURL),version,dummy)

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

ubuntu.packages     = ca-certificates bash vim-tiny curl tar debianutils
ubuntu.packages.npm = npm
ubuntu.packages.pip = python3-venv
ubuntu.packages.scr = bash curl

PIP_VENV = /opt/devkit/agent

COREPKGS    = $(sort $(ubuntu.packages))
AGENTPKGS   = $(sort $(filter-out $(COREPKGS),$(PACKAGES) $(ubuntu.packages.$(INST))))
USERPKGS    = $(sort $(filter-out $(COREPKGS) $(AGENTPKGS),$(DEVPKGS)))
SASHIKOPKGS = $(sort $(filter-out $(COREPKGS) $(USERPKGS) $(AGENTPKGS),$(if $(SASHIKO_ENABLED),cargo)))

ubuntu-install = RUN apt-get -y -q$(if $(Q),qq) update; apt-get -y -q$(if $(Q),qq) --no-install-recommends install $(1); apt-get -y -q$(if $(Q),qq) clean; rm -rf /var/lib/apt/lists/*

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
	agent_version="`$(get-github-release)`"
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
	  $(if $(filter npm,$(INST)),RUN : "$$DEVKIT_AGENT_VERSION"; npm install -g "$(LINK)" --omit=dev && rm -rf /root/.npm /root/.cache)
	  $(if $(filter pip,$(INST)),RUN : "$$DEVKIT_AGENT_VERSION" && python3 -m venv "$(PIP_VENV)" && "$(PIP_VENV)/bin/python" -m pip install $(if $(Q),-q) --no-cache-dir "$(LINK)" && "$(PIP_VENV)/bin/python" -m pip check)
	  $(if $(filter scr,$(INST)),RUN : "$$DEVKIT_AGENT_VERSION"; curl -fsSL "$(LINK)" | $(SCR_ENV) bash)
	  $(if $(USERPKGS),$(call ubuntu-install,$(USERPKGS)))
	  $(if $(SASHIKOPKGS),$(call ubuntu-install,$(SASHIKOPKGS)))
	  $(if $(SASHIKO_ENABLED),RUN cargo install --root / sashiko)
	  SHELL ["/bin/bash", "-eio", "pipefail", "-c"]
	  RUN bin="$(if $(filter pip,$(INST)),$(PIP_VENV)/bin/$(BIN),`command -v $(BIN)`)" && [ -x "$$bin" ] && { [ "$$bin" = "/usr/local/bin/$(BIN)" ] || ln -vs -- "$$bin" "/usr/local/bin/$(BIN)"; }
	  SHELL ["/bin/bash", "-eo", "pipefail", "-c"]
	  ARG DEVKIT_BUILD_ID
	  RUN : "$$DEVKIT_BUILD_ID"; $(BUILD_COMMAND)
	  ENTRYPOINT ["/.devkit/entry","/usr/local/bin/$(BIN)"]
	EOF

PASSTHRU_SHELL_ARGS = i=0; while [ $$i -lt $${NARGS:-0} ]; do eval "a=\"\$${ARG$$i-}\""; set -- "$$@" "$$a"; i=$$(($$i+1)); done

run: _create_local_dirs _create-image-$(VENDOR)
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

ifneq ($(SASHIKO_ENABLED),)
$(HOME)/$(SASHIKO_HOME):
	$(Q)mkdir -p -- \
	  $(HOME)/$(SASHIKO_HOME)/bin \
	  $(HOME)/$(SASHIKO_HOME)/worktries

$(HOME)/$(SASHIKO_HOME)/Settings.toml: $(HOME)/$(SASHIKO_HOME)
	$(Q)cat > "$@" <<-'EOF'
	  database.token = ""
	  database.url = "/home/user/$(SASHIKO_HOME)/devkit.db"
	  mailing_lists.track = ""
	  nntp.port = 119
	  nntp.server = "nntp.lore.kernel.org"
	  review.concurrency = 20
	  review.worktree_dir = "/home/user/$(SASHIKO_HOME)/worktries"
	  server.host = "::"
	  server.port = 8080
	  server.read_only = false
	EOF

$(HOME)/$(SASHIKO_HOME)/bin/devkit-agent: $(HOME)/$(SASHIKO_HOME)
	$(Q)cat > "$@" <<-'EOF'
	  #!/bin/bash -efu
	  if [ -n "$${SASHIKO__GIT__REPOSITORY_PATH-}" ]; then
	    . "/home/user/$(SASHIKO_HOME)/$${0##*/}.env";
	    args=(); i=0;
	    for a in "$$@"; do
	      case "$$a" in
	        (*="use-own-agent-model")                              ;;
	        ("use-own-agent-model") i=$$(($$i-1)); unset args[$$i] ;;
	        (*) args[$$i]="$$a"; i=$$(($$i+1))                     ;;
	      esac;
	    done;
	    set -- "$${args[@]}" $${ARGS-}
	  fi;
	  exec "/usr/local/bin/$${0##*/}" "$$@"
	EOF
	chmod 755 -- "$@"

$(HOME)/$(SASHIKO_HOME)/bin/$(BIN): $(HOME)/$(SASHIKO_HOME)/bin/devkit-agent
	$(Q)ln -sf -- devkit-agent "$@"

$(HOME)/$(SASHIKO_HOME)/$(BIN).env: $(CURFILE)
	$(Q)cat > $(HOME)/$(SASHIKO_HOME)/$(BIN).env <<-'EOF'
	  ARGS='$(SASHIKO.agent.options)'
	EOF

sashiko-daemon: _create_local_dirs _create-image-$(VENDOR) $(HOME)/$(SASHIKO_HOME)/Settings.toml $(HOME)/$(SASHIKO_HOME)/bin/$(BIN) $(HOME)/$(SASHIKO_HOME)/$(BIN).env
	$(Q)set -e --; $(PASSTHRU_SHELL_ARGS);
	$(PODMAN) container run $(PODMAN_RUNTIME_ARGS) $(PODMAN_VOLUMES) $(if $(SASHIKO_BACKGROUND),--detach) \
	  --name '$(SASHIKO_CONTAINER)' \
	  --env=SASHIKO__AI__PROVIDER='$(SASHIKO_PROVIDER)' \
	  --env=SASHIKO__AI__MODEL='$(SASHIKO_MODEL)' \
	  --env=SASHIKO__GIT__REPOSITORY_PATH='/srv/$(PROJNAME)' \
	  --entrypoint='["/.devkit/entry","sashiko"]' -- '$(PODMAN_IMAGE)' "$$@" $(ARGS);

sashiko-kill:
	$(Q)set -e --;
	! $(PODMAN) container exists '$(SASHIKO_CONTAINER)' ||
	  $(PODMAN) container kill '$(SASHIKO_CONTAINER)'

sashiko-logs:
	$(Q)set -e --; $(PASSTHRU_SHELL_ARGS);
	$(PODMAN) container logs '$(SASHIKO_CONTAINER)' "$$@" $(ARGS);

sashiko:
	$(Q)set -e --; $(PASSTHRU_SHELL_ARGS);
	$(PODMAN) container exists '$(SASHIKO_CONTAINER)' ||
	   $(MAKE) --no-print-directory -f $(CURFILE) sashiko-daemon NARGS=0 SASHIKO_BACKGROUND=1
	$(PODMAN) container exec $(PODMAN_ARGS) -- '$(SASHIKO_CONTAINER)' sashiko-cli "$$@" $(ARGS);
else
.PHONY: _sashiko-disabled

_sashiko-disabled:
	@echo "devkit: sashiko support is not enabled in git-config."
	echo  "devkit: run \`git config set devkit.sashiko true' to enable it."

sashiko-daemon: _sashiko-disabled
sashiko-kill:   _sashiko-disabled
sashiko-logs:   _sashiko-disabled
sashiko:        _sashiko-disabled
endif
