devkit
======

devkit is a Makefile-based utility for running AI agents inside isolated Podman
containers with project-specific dependencies.

**Disclaimer**: devkit provides process isolation, not security isolation.
Nothing prevents an agent from running destructive commands such as
``rm -rf .git`` inside your mounted project directory.

The tool focuses on:

- reproducible development environments
- solated execution of AI agents
- minimal setup overhead
- reusable dependency profiles across repositories

devkit intentionally avoids introducing new configuration formats. All
configuration lives in git-config.


Concept
-------

devkit builds container images from:

- selected AI agent
- requested Ubuntu packages
- agent version
- configuration hash

Images are automatically reused when configuration matches.

Each repository declares its development environment via git configuration.
Multiple repositories can share the same environment profile.


Architecture
------------

devkit follows a simple model:


Profiles
--------

A profile defines:

- agent type
- dependency packages

Profiles can be shared between repositories using git configuration includes.


Local Overrides
---------------

Repositories may override profile values locally using git-config.


Image Identity
--------------

Container images are content-addressed: `hash(agent + packages) -> image
identity`. This prevents duplicate builds and allows transparent reuse.


Isolation Model
---------------

- Containers run via Podman.
- Project directory mounted at::

      /srv/<project-name>

- Agent configuration directories are bind-mounted from HOME.
- Environment is isolated from host system.


Requirements
------------

Required utilities:

- ``make``
- ``git``
- ``podman``
- ``curl``

Initial Setup
-------------

Initialize configuration::

    make -f devkit.mk init


Usage
-----

Run agent::

    make -f devkit.mk run

Open interactive shell. If the container is already running, a second session
will be opened in the container::

    make -f devkit.mk shell

Check available and current agent versions::

    make -f devkit.mk check

List devkit images::

    make -f devkit.mk list

Upgrade container image::

    make -f devkit.mk upgrade

Remove images for current environment::

    make -f devkit.mk clean

Remove all devkit images::

    make -f devkit.mk clean-all


Configuration
-------------

All configuration is stored in `git-config`.

Inspect configuration::

    git config devkit.agent
    git config --get-all devkit.packages


devkit.agent
------------

Defines which AI agent should be executed.

Supported agents:

- `aider <https://aider.chat>`
- `claude <https://claude.ai>`
- `codex <https://github.com/openai/codex>`
- `copilot <https://github.com/github/copilot-cli>`
- `gemini <https://geminicli.com>`
- `opencode <https://opencode.ai>`
- `grok (unofficial) <https://grokcli.io>`

Example::

    git config devkit.agent codex


devkit.shell
------------

This variable allows you to override the shell that will be used in the
container (the default is `/bin/bash`). If the user changes this parameter,
user must take care of installing shell package in the container.


devkit.packages
---------------

List of Ubuntu packages installed into the container.

Example::

    git config --add devkit.packages gcc
    git config --add devkit.packages make
    git config --add devkit.packages gdb


devkit.volumes
--------------

Additional list of podman volumes to mount into the container.


devkit.hooks-path
-----------------

Path to a directory with container lifecycle hooks.

When the path exists, devkit mounts it read-only as ``/.devkit/hooks.d`` and
runs the handlers with ``run-parts`` from the container entrypoint before
starting the agent or development shell. The current lifecycle stage is passed
as the first argument and is currently always ``start``.

Example::

    git config devkit.hooks-path ~/devkit/hooks.d

Example hook::

    #!/bin/sh
    [ "$1" = start ] || exit 0
    echo "container is starting"


devkit.build-command
--------------------

Shell fragment executed as root while building the agent image.

This is intended for project-specific image customization that does not fit
into the package list, such as installing extra tools from a mounted script.

Example::

    git config devkit.build-command /mnt/devkit-hooks/install-tools.sh


devkit.build-volumes
--------------------

Additional list of podman volumes to mount only while building the image.

These volumes are passed to ``podman image build`` and can be used by
``devkit.build-command``.

Example::

    git config --add devkit.build-volumes /home/me/devkit-hooks:/mnt/devkit-hooks:ro,Z


devkit.build-id
---------------

Identifier for custom build inputs.

This value is part of the image identity and defaults to ``none``. Change it
when files used by ``devkit.build-command`` change, especially when those
files come from ``devkit.build-volumes``. devkit cannot detect content changes
inside arbitrary build volumes automatically.

Example::

    git config devkit.build-id tools-2026-05-03


Shared profiles via git include
-------------------------------

Git allows configuration reuse using ``include.path``.

Example shared profile:

``~/.config/devkit/basic-c.gitconfig``::

    [devkit]
        agent = codex
        packages = gcc
        packages = make
        packages = gdb
        packages = clang-format

Include inside repository::

    git config include.path ~/devkit/gitconfig.d/kernel-dev.ini

Benefits:

- single source of truth
- consistent tooling
- automatic image reuse
- minimal per-repository setup

Local repository configuration may override included values.


Design Goals
------------

- zero additional tooling beyond Makefile
- no custom configuration formats
- explicit and inspectable behavior
- easy debugging using Podman
- safe execution of AI agents


Limitations
-----------

- Agent conversation history is not shared between containers and the host
  system. Projects are mounted at ``/srv`` rather than at their original host
  path, so the agent treats them as different projects.

- Images are not portable across hosts. The container user is created with the
  host's UID:GID, so an image built on one machine will not work on another
  with different user IDs.


License
-------

GPL-2.0-or-later
