# Docker Utility Scripts

This directory contains portable bash scripts for Docker and Docker Compose management.

## Prerequisites

The following tools are required for these scripts to work properly:

- `docker` and `docker compose`
- `fzf` (for interactive container/project selection)
- `jq` (for JSON parsing)
- [column-port](../unixy/column-port.sh) (portable wrapper of `column` that handles GNU options but falls back to BSD options)

## Container Management Scripts

### Basic Container Operations

- **`dk-shell`** - Start an interactive shell in a container
  - Usage: `dk-shell [container_name] [command...]`
  - If no container specified, prompts with fzf menu
  - Automatically detects best shell (zsh > bash > sh)

- **`dk-ps`** - List running containers in table format
  - Shows: Names, Image, Status, ID

### Container Information

- **`dk-pid`** - List PIDs of containers
  - Usage: `dk-pid [container...]` (default: all containers)
  - Output: Container name and PID

- **`dk-pid-f`** - List detailed process information for containers
  - Usage: `dk-pid-f [container...]` (default: all containers)
  - Output: Container, PID, PPID, User, UID, Process count, Command

- **`dk-ip`** - List IP addresses of containers
  - Usage: `dk-ip [container...]` (default: all containers)

- **`dk-networks`** - List Docker network subnets
  - Shows all networks and their subnet configurations

- **`dk-mount`** - List all mounts for containers
  - Usage: `dk-mount [container...]` (default: all containers)

- **`dk-bind-mount`** - List only bind mounts for containers
  - Usage: `dk-bind-mount [container...]` (default: all containers)

- **`dk-restart-policy`** - List restart policies for containers
  - Usage: `dk-restart-policy [container...]` (default: all containers)

### Bind Mount Management

- **`dk-bind-mount-mark`** - Mark bind mounts with timestamp files for
    `dk-bind-mount-mark-check` to verify (in particular for Docker Desktop for
    Windows, which uses WSL and where bind mounts are unreliable)
  - Creates `.srv-bind-mount` files in bind mount directories
  - Usage: `dk-bind-mount-mark [container...]` (default: all containers)

- **`dk-bind-mount-mark-check`** - Verify proper mounting of bind mounts
    (in particular for Docker Desktop for Windows, which uses WSL and where bind mounts are
    unreliable)
  - Checks if `.srv-bind-mount` files are accessible from containers
  - Usage: `dk-bind-mount-mark-check [container...]` (default: all containers)

- **`dk-bind-mount-mark-autorestart`** - Auto-restarts Docker Compose projects
    until bind mounts are correct
  - Checks if `.srv-bind-mount` files are accessible from containers
  - Usage: `dk-bind-mount-mark-autorestart [project...]` (default: all projects)

## Docker Compose Scripts

### Core Compose Utilities

- **`dkc`** - Wrapper for `docker compose` with automatic project detection
  - Uses `$DKC_PROJ_DIR` environment variable if set
  - Otherwise prompts for project selection
  - Usage: `dkc [compose_args...]`

- **`dkc-shell`** - Shell into main container of Compose project
  - Automatically finds the container with the shortest name
  - Changes to project directory if needed

### Project Management

- **`dkc-compose-file`** - Checks if current directory is a Docker Compose project
    and prints out the detected compose files.
  - Usage: `dkc-compose-file`

- **`dkcs`** - Stop Docker Compose projects
  - Usage: `dkcs [project...]` (default: current directory or prompt)
  - Wrapper for `docker compose stop`

- **`dkcu`** - Start Docker Compose projects
  - Usage: `dkcu [project...]` (default: current directory or prompt)
  - Wrapper for `docker compose up -d --remove-orphans`

- **`dkcu-r`** - Start Docker Compose projects with recreation
  - Usage: `dkcu-r [project...]` (default: current directory or prompt)
  - Wrapper for `docker compose up -d --remove-orphans --force-recreate`

- **`dkcsu`** - Stop then start Docker Compose projects
  - Usage: `dkcsu [project...]` (default: current directory or prompt)
  - Combines `dkcs` and `dkcu` operations

- **`dkcsu-r`** - Stop then start Docker Compose projects with recreation
  - Usage: `dkcsu-r [project...]` (default: current directory or prompt)
  - Combines `dkcs` and `dkcu-r` operations

### Helper Utilities

- **`dkc-project-where`** - Helper script to get Docker Compose project directory
  - Returns directory of specified project, or
  - returns current directory if already in a project, or
  - prompts with fzf to select from available projects

- **`dkc-loop`** - Helper to execute commands across multiple Compose projects
  - Usage: `dkc-loop [project...] -- command [args...]`
  - Sets `$DKC_PROJ_DIR` for each project iteration
  - If no projects specified, uses current directory or prompts

## Docker System Scripts

### Host System Access

- **`dk-system-shell`** - Access Docker host system
  - Usage: `dk-system-shell [command...]`
  - Interactive shell if no command specified
  - Uses `justincormack/nsenter1` container

- **`dk-system-bash`** - Bash shell in Docker host (WSL specific)
  - Usage: `dk-system-bash [command...]`
  - Only works in WSL environments
  - Sets up Docker aliases for WSL

### System Utilities

- **`dk-system-symlink-overlay2`** - Create symlinks to overlay2 directories
  - Creates human-readable symlinks in `/var/lib/docker/overlay2.human`
  - Maps container names to their overlay2 directories

- **`dk-system-symlink-bind-mounts`** - Create symlinks to bind mounts
  - Creates human-readable symlinks for bind mount directories
  - Requires `dk-bind-mount-ids` command
  - Only works in WSL environments

- **`dk-bind-mount-ids`** - Lists mappings from bind mounts to Docker-internal IDs
  - Only works in WSL environments
