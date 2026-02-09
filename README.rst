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
- logical environment name

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

Open interactive shell::

    make -f devkit.mk bash

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
    git config devkit.name
    git config --get-all devkit.packages


devkit.agent
------------

Defines which AI agent should be executed.

Supported agents:

- ``copilot``
- ``codex``
- ``opencode``
- ``gemini``
- ``claude``

Example::

    git config devkit.agent codex


devkit.name
-----------

Logical name of the dependency environment. This identifies a reusable
environment profile. Container images are tagged and reused based on this
identity and configuration hash. Multiple repositories can share identical
images.

Typical usage:

- shared "basic-c" environment
- shared Python tooling environments
- centralized dependency definitions


devkit.packages
---------------

List of Ubuntu packages installed into the container.

Example::

    git config --add devkit.packages gcc
    git config --add devkit.packages make
    git config --add devkit.packages gdb


Shared profiles via git include
-------------------------------

Git allows configuration reuse using ``include.path``.

Example shared profile:

``~/.config/devkit/basic-c.gitconfig``::

    [devkit]
        name = basic-c
        agent = codex
        packages = gcc
        packages = make
        packages = gdb
        packages = clang-format

Include inside repository::

    git config include.path ~/.config/devkit/basic-c.gitconfig

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
