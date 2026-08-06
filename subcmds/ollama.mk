# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026  Alexey Gladkov <gladkov.alexey@gmail.com>

OLLAMA_GOALS = ollama ollama-daemon ollama-kill ollama-logs
PUBLIC_GOALS += $(OLLAMA_GOALS)

OLLAMA_CONTAINER = $(PODMAN_CONTAINER)-ollama
OLLAMA_HOME = .ollama

ollama.PKGS  = zstd mesa-vulkan-drivers libvulkan1 vulkan-tools pciutils
ollama.BUILD = RUN $(CURL) -fsSL https://ollama.com/install.sh | bash

.PHONY: $(OLLAMA_GOALS)
.ONESHELL:

ollama-help:
	@echo "Optional ollama commands (require: git config devkit.ollama true):"
	echo " ollama          execute ollama command."
	echo " ollama-daemon   start the daemon."
	echo " ollama-kill     stop the daemon."
	echo " ollama-logs     show daemon logs."
	echo ""

ifneq ($(ollama_ENABLED),)

VOLUMES += $(HOME)/$(OLLAMA_HOME):/home/user/$(OLLAMA_HOME):rw,Z
PODMAN_BUILD_ARGS += --device /dev/dri

ollama-daemon: _create_local_dirs _create-image-$(VENDOR)
	$(Q)set -e --; $(PASSTHRU_SHELL_ARGS);
	$(PODMAN) container run $(PODMAN_RUNTIME_ARGS) $(PODMAN_VOLUMES) $(if $(OLLAMA_BACKGROUND),--detach) \
	  --name '$(OLLAMA_CONTAINER)' $(if $(V),--env=OLLAMA_DEBUG=1) \
	  --device /dev/dri \
	  --entrypoint='["/.devkit/entry","ollama","serve"]' -- '$(PODMAN_IMAGE)' "$$@" $(ARGS);

ollama-kill:
	$(Q)$(MAKE) --no-print-directory -f $(CURFILE) _container-kill _CONTAINER='$(OLLAMA_CONTAINER)'

ollama-logs:
	$(Q)$(MAKE) --no-print-directory -f $(CURFILE) _container-logs _CONTAINER='$(OLLAMA_CONTAINER)'

ollama:
	$(Q)set -e --; $(PASSTHRU_SHELL_ARGS);
	$(PODMAN) container exists '$(OLLAMA_CONTAINER)' ||
	   $(MAKE) --no-print-directory -f $(CURFILE) ollama-daemon NARGS=0 OLLAMA_BACKGROUND=1
	$(PODMAN) container exec $(PODMAN_ARGS) -- '$(OLLAMA_CONTAINER)' ollama "$$@" $(ARGS);
else
$(OLLAMA_GOALS): _disabled
endif
