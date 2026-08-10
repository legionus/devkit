# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026  Alexey Gladkov <gladkov.alexey@gmail.com>

SASHIKO_GOALS = sashiko sashiko-daemon sashiko-kill sashiko-logs
PUBLIC_GOALS += $(SASHIKO_GOALS)

SASHIKO_PROVIDER   = $(shell $(GIT_CONFIG_GET) devkit.sashiko-provider   || echo $(AGENT)-cli)
SASHIKO_MODEL      = $(shell $(GIT_CONFIG_GET) devkit.sashiko-model      || echo use-own-agent-model)
SASHIKO_CONCURRENT = $(shell $(GIT_CONFIG_GET) devkit.sashiko-concurrent || echo 1)

SASHIKO_CONTAINER = $(PODMAN_CONTAINER)-sashiko
SASHIKO_HOME      = .local/share/sashiko

sashiko.PKGS  = cargo
sashiko.BUILD = RUN cargo install --locked --root / sashiko

.PHONY: $(SASHIKO_GOALS)
.ONESHELL:

sashiko-help:
	@echo "Optional sashiko commands (require: git config devkit.sashiko true):"
	echo " sashiko         start the service if needed and open its CLI."
	echo " sashiko-daemon  start the review daemon."
	echo " sashiko-kill    stop the review daemon."
	echo " sashiko-logs    show review-daemon logs."
	echo ""

ifneq ($(sashiko_ENABLED),)

VOLUMES += $(HOME)/$(SASHIKO_HOME):/home/user/$(SASHIKO_HOME):rw,Z
PODMAN_PATH += /home/user/$(SASHIKO_HOME)/bin

ifneq ($(filter sashiko-daemon,$(MAKECMDGOALS)),)
WORKDIR = /home/user/$(SASHIKO_HOME)
endif

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
	  review.concurrency = $(SASHIKO_CONCURRENT)
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
	  exec "/usr/local/bin/agent" "$$@"
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
	$(Q)$(MAKE) --no-print-directory -f $(CURFILE) _container-kill _CONTAINER='$(SASHIKO_CONTAINER)'

sashiko-logs:
	$(Q)$(MAKE) --no-print-directory -f $(CURFILE) _container-logs _CONTAINER='$(SASHIKO_CONTAINER)'

sashiko:
	$(Q)set -e --; $(PASSTHRU_SHELL_ARGS);
	$(PODMAN) container exists '$(SASHIKO_CONTAINER)' ||
	   $(MAKE) --no-print-directory -f $(CURFILE) sashiko-daemon NARGS=0 SASHIKO_BACKGROUND=1
	$(PODMAN) container exec $(PODMAN_ARGS) -- '$(SASHIKO_CONTAINER)' sashiko-cli "$$@" $(ARGS);
else
$(SASHIKO_GOALS): _disabled
endif
