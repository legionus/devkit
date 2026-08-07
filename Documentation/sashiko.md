# Sashiko support

Sashiko is an agentic Linux kernel code review service. devkit can install it
in the project image, run its review daemon in a separate container, and open
the Sashiko command-line client connected to that daemon.

Sashiko support is disabled by default. Enable it in the repository:

```sh
git config devkit.sashiko true
```

Enabling Sashiko changes the image identity. The next command that needs the
image builds one containing Sashiko and its Rust dependencies.

## Commands

### `sashiko`

Starts the Sashiko daemon in the background if it is not already running, then
opens `sashiko-cli` in the daemon container. Additional arguments are passed to
`sashiko-cli`:

```sh
devkit.sh sashiko [ARG]...
```

### `sashiko-daemon`

Starts the review daemon in the foreground:

```sh
devkit.sh sashiko-daemon [ARG]...
```

Additional arguments are passed to `sashiko`. Normally it is not necessary to
run this command directly because `devkit.sh sashiko` starts the daemon in the
background when needed.

### `sashiko-kill`

Stops the Sashiko daemon container:

```sh
devkit.sh sashiko-kill
```

### `sashiko-logs`

Shows the daemon container logs. Additional arguments are passed to
`podman container logs`:

```sh
devkit.sh sashiko-logs [ARG]...
```

## Configuration

### `devkit.sashiko`

Enables Sashiko support when set to `true`, `yes`, `on`, or `1`. The default is
disabled.

```sh
git config devkit.sashiko true
```

### `devkit.sashiko-provider`

Sets the Sashiko AI provider. The value is passed to the daemon as
`SASHIKO__AI__PROVIDER`. By default devkit uses `<agent>-cli`, where `<agent>`
is the value of `devkit.agent`; for example, `codex-cli`.

```sh
git config devkit.sashiko-provider codex-cli
```

### `devkit.sashiko-model`

Sets the model requested by Sashiko. The value is passed to the daemon as
`SASHIKO__AI__MODEL`. The default is `use-own-agent-model`, which tells the
devkit wrapper not to override the configured agent's own model.

```sh
git config devkit.sashiko-model MODEL
```

## Persistent data and defaults

devkit stores Sashiko data in `~/.local/share/sashiko` on the host and mounts
that directory into the daemon container. On first use it creates a default
`Settings.toml`, a database, helper scripts, and a directory for review
worktrees there.

The generated configuration listens on all IPv6 interfaces on port 8080, uses
`nntp.lore.kernel.org` as its NNTP server, and allows 20 concurrent reviews.
Edit `~/.local/share/sashiko/Settings.toml` to change the service configuration.
devkit does not replace an existing settings file.

The project repository is mounted into the daemon and supplied to Sashiko as
its Git repository path. The daemon uses the agent selected by `devkit.agent`;
devkit adds the non-interactive permission option required by supported agents
when applicable.
