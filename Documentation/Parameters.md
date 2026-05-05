# devkit parameters

devkit reads these parameters from the git-config of the project for which the
agent is started.

Inspect configuration:

```sh
git config devkit.agent
git config --get-all devkit.packages
```

## devkit.agent

Defines which AI agent should be executed.

See [README.md](../README.md) for the list of supported agents.

Example:

```sh
git config devkit.agent codex
```

## devkit.shell

This variable allows you to override the shell that will be used in the
container (the default is `/bin/bash`). If the user changes this parameter,
user must take care of installing shell package in the container.

## devkit.packages

List of Ubuntu packages installed into the container.

Example:

```sh
git config --add devkit.packages gcc
git config --add devkit.packages make
git config --add devkit.packages gdb
```

## devkit.volumes

Additional list of podman volumes to mount into the container.

## devkit.hooks-path

Path to a directory with container lifecycle hooks.

When the path exists, devkit mounts it read-only as `/.devkit/hooks.d` and runs
the handlers with `run-parts` from the container entrypoint before starting the
agent or development shell. The current lifecycle stage is passed as the first
argument and is currently always `start`.

Example:

```sh
git config devkit.hooks-path ~/devkit/hooks.d
```

Example hook:

```sh
#!/bin/sh
[ "$1" = start ] || exit 0
echo "container is starting"
```

## devkit.build-command

Shell fragment executed as root while building the agent image.

This is intended for project-specific image customization that does not fit
into the package list, such as installing extra tools from a mounted script.

Example:

```sh
git config devkit.build-command /mnt/devkit-hooks/install-tools.sh
```

## devkit.build-volumes

Additional list of podman volumes to mount only while building the image.

These volumes are passed to `podman image build` and can be used by
`devkit.build-command`.

Example:

```sh
git config --add devkit.build-volumes /home/me/devkit-hooks:/mnt/devkit-hooks:ro,Z
```

## devkit.build-id

Identifier for custom build inputs.

This value is part of the image identity and defaults to `none`. Change it
when files used by `devkit.build-command` change, especially when those files
come from `devkit.build-volumes`. devkit cannot detect content changes inside
arbitrary build volumes automatically.

Example:

```sh
git config devkit.build-id tools-2026-05-03
```
