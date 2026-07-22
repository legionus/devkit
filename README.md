# devkit

devkit is a makefile-based utility for running AI agents inside isolated podman
containers with project-specific dependencies.

**Disclaimer**: devkit provides process isolation, not security isolation.
Nothing prevents an agent from running destructive commands such as
`rm -rf .git` inside your mounted project directory.

## Design Goals

- zero additional tooling beyond Makefile
- no custom configuration formats
- explicit and inspectable behavior
- easy debugging using podman
- safe execution of AI agents

## Limitations

- Agent conversation history is not shared between containers and the host
  system. Projects are mounted at `/srv` rather than at their original host
  path, so the agent treats them as different projects.

- Images are not portable across hosts. The container user is created with the
  host's UID:GID, so an image built on one machine will not work on another
  with different user IDs.

## Architecture

devkit treats each repository as the owner of its own agent environment. The
environment is described by the repository git-config: selected agent, ubuntu
packages, additional volumes, build customizations and lifecycle hooks. Shared
profiles are ordinary git-config include files, so a repository can inherit a
baseline environment and override only the parts that differ locally.

From that configuration devkit derives an image identity. If a matching image
already exists, it is reused. Otherwise devkit builds a new image from an ubuntu
base, installs the selected agent and requested packages, applies build-time
customizations, and records metadata labels such as the agent, agent version and
configuration hash.

Whole-image reuse requires the complete image identity to match. Git include
files compose configuration but do not create parent images or separate package
layers. When devkit must build an image, podman may reuse unchanged intermediate
layers from earlier builds. Fixed packages, agent dependencies, the agent, the
configured package list, and optional sashiko support are built in separate
steps. Agent dependencies and installation precede the configured package
list, allowing images for the same agent to share its layers when their
configured packages differ.

At runtime devkit starts a named podman container for the repository. The
project tree is mounted at `/srv/<project-name>`, the selected agent
configuration directory is mounted from the host, and any configured volumes are
added. The image entrypoint runs container `start` hooks and then replaces
itself with the requested command: either the agent or the development shell.

If the named container is already running, `devkit shell` opens another session
inside it instead of creating a second container. This keeps long-running agent
sessions and interactive debugging in the same project environment.

## Requirements

Required utilities:

- `make`
- `git`
- `podman`
- `curl`

## Initial Setup

Initialize configuration:

```
$ devkit.sh init
```

## Usage

Run agent:

```
$ devkit.sh run
```

Open interactive shell. If the container is already running, a second session
will be opened in the container:

```
$ devkit.sh shell
```

Check available and current agent versions:

```
$ devkit.sh check
```

List devkit images:

```
$ devkit.sh list
```

Upgrade container image:

```
$ devkit.sh upgrade
```

An upgrade pulls the current ubuntu base image and performs a fresh build
without reusing complete images or cached intermediate layers.

Remove images for current environment:

```
$ devkit.sh clean
```

Remove all devkit images:

```
$ devkit.sh clean-all
```

The clean commands remove tagged devkit images. They retain podman's
intermediate build cache, which remains under podman cache management.

### Optional Sashiko review service

Sashiko is an agentic Linux kernel code review system. It uses
Linux-kernel-specific prompts and a dedicated protocol to review proposed
kernel changes. It can ingest patches from mailing lists or a local git
repository.

Enable it for a repository:

```
$ git config devkit.sashiko true
```

Start the service and open its CLI:

```
$ devkit.sh sashiko
```

`devkit.sh sashiko-daemon` starts the review daemon, `devkit.sh sashiko-kill`
stops it, and `devkit.sh sashiko-logs` shows its logs.

## Configuration

All configuration is stored in `git-config`.

Inspect configuration:

```
$ git config devkit.agent
$ git config --get-all devkit.packages
```

Example of configuration:

```ini
[devkit]
	agent = codex
	editor = /usr/bin/vim
	env-file = .env
	packages = git ripgrep
	packages = build-essential bc flex bison libelf-dev binutils-dev
	packages = libncurses-dev
```

Supported agents:

- [aider](https://aider.chat)
- [cecli](https://github.com/cecli-dev/cecli)
- [claude](https://claude.ai)
- [codex](https://github.com/openai/codex)
- [copilot](https://github.com/github/copilot-cli)
- [gemini](https://geminicli.com)
- [goose](https://github.com/aaif-goose/goose)
- [opencode](https://opencode.ai)
- [grok (unofficial)](https://grokcli.io)
- [vibe](https://docs.mistral.ai/mistral-vibe/terminal)
- [kimi](https://moonshotai.github.io/kimi-code/en/)

See [Documentation/Parameters.md](Documentation/Parameters.md) for the full
list of supported `devkit.*` parameters. These parameters are read from the
git-config of the project for which the agent is started.

### Shared profiles via git include

Git allows configuration reuse using `include.path`.

A profile usually defines the agent type and dependency packages. Profiles can
be shared between repositories using git configuration includes.

Example shared profile:

```ini
# ~/.config/devkit/basic-c.ini
[devkit]
    packages = gcc make gdb
    packages = clang-format
```

Include inside repository:

```
$ git config devkit.agent codex
$ git config include.path ~/.config/devkit/basic-c.ini
```

Benefits:

- single source of truth
- consistent tooling
- automatic image reuse when complete image identities match
- minimal per-repository setup

Local repository configuration may override included values.

An included profile is not a parent-image boundary. Projects that add different
package sets produce different complete image identities, but projects using
the same agent can share layers through the agent installation. The configured
package layer is shared only when its package list and all preceding layers
match.

## License

GPL-2.0-or-later
