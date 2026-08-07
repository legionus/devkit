# Ollama support

devkit can install Ollama in the project image and run an Ollama server in a
separate container. The Ollama command-line client can then manage and run
locally hosted models.

Ollama support is disabled by default. Enable it in the repository:

```sh
git config devkit.ollama true
```

Enabling Ollama changes the image identity. The next command that needs the
image builds one containing Ollama, Vulkan utilities, and the required graphics
libraries.

## Requirements

The Ollama integration passes `/dev/dri` to both the image build and the daemon
container. The host must provide this device and permit the current user to
access it.

## Commands

### `ollama`

Starts the Ollama daemon in the background if it is not already running, then
executes the Ollama command-line client in the daemon container. Additional
arguments are passed to the client:

```sh
devkit.sh ollama [ARG]...
```

For example:

```sh
devkit.sh ollama list
devkit.sh ollama run MODEL
```

### `ollama-daemon`

Starts `ollama serve` in the foreground:

```sh
devkit.sh ollama-daemon [ARG]...
```

Additional arguments are passed to `ollama serve`. Normally it is not necessary
to run this command directly because `devkit.sh ollama` starts the daemon in the
background when needed.

### `ollama-kill`

Stops the Ollama daemon container:

```sh
devkit.sh ollama-kill
```

### `ollama-logs`

Shows the daemon container logs. Additional arguments are passed to
`podman container logs`:

```sh
devkit.sh ollama-logs [ARG]...
```

## Configuration

### `devkit.ollama`

Enables Ollama support when set to `true`, `yes`, `on`, or `1`. The default is
disabled.

```sh
git config devkit.ollama true
```

## Persistent data and diagnostics

devkit stores downloaded models and other Ollama state in `~/.ollama` on the
host and mounts that directory into the daemon container.

Run devkit with `--verbose` to set `OLLAMA_DEBUG=1` for a newly started daemon:

```sh
devkit.sh --verbose ollama-daemon
```

The daemon uses the host network, like other devkit containers. Use
`devkit.sh ollama-logs` to inspect startup and runtime errors.
