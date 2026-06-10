```
   ____ _        _   _   _ ____  _______        ___   _  ___
  / ___| |      / \ | | | |  _ \| ____\ \      / / | | |/ _ \
 | |   | |     / _ \| | | | | | |  _|  \ \ /\ / /| |_| | | | |
 | |___| |___ / ___ \ |_| | |_| | |___  \ V  V / |  _  | |_| |
  \____|_____/_/   \_\___/|____/|_____|  \_/\_/  |_| |_|\___/
```

# claudewho

Manage multiple Claude Code account configurations easily. Switch between work and personal accounts, or maintain separate configurations for different projects.

## Installation

### Homebrew (recommended)

```bash
brew install frisble/tap/claudewho
```

Or:

```bash
brew tap frisble/tap
brew install claudewho
```

### Manual

```bash
git clone https://github.com/frisble/claudewho.git
cd claudewho
chmod +x bin/claudewho
sudo ln -s "$(pwd)/bin/claudewho" /usr/local/bin/claudewho
```

## Usage

### Create accounts

```bash
claudewho add work
claudewho add personal
claudewho add client-project
```

### List accounts

```bash
claudewho list
```

Output:
```
Configured Claude accounts:

  work                 ~/.claudewho-work              (authenticated)
  personal             ~/.claudewho-personal          (not authenticated)
  client-project       ~/.claudewho-client-project    (authenticated)

Use claudewho-<name> or claudewho use <name> to launch.
```

### Launch Claude with an account

```bash
# Using the wrapper command (recommended)
claudewho-work
claudewho-personal

# Or using the command
claudewho use work
```

### Remove an account

```bash
claudewho remove personal
```

This will prompt for confirmation before deleting the account directory.

### Wrap other commands

If you use other Claude-aware tools (e.g. `recall`), you can wrap them so they automatically use the active claudewho account:

```bash
claudewho wrap recall
```

This creates a wrapper at `~/.local/bin/recall` that sets `CLAUDE_CONFIG_DIR` to the active account before running the real binary. Any tool wrapped this way will follow whichever account is selected via `claudewho use <name>`.

## Commands

| Command | Description |
|---------|-------------|
| `list` | List all configured accounts |
| `add <name>` | Create a new account configuration |
| `remove <name>` | Remove an account (with confirmation) |
| `use <name>` | Switch to the specified account |
| `wrap <command>` | Create a wrapper for a command to use the active account |
| `ide-setup` | Configure IDE integration (VSCode) |
| `shell-init` | Print shell aliases for sourcing |
| `keychain status` | Show Keychain state — bindings, suffixed CLI entries, stashes (macOS) |
| `keychain bind <p> <suffix>` | Bind a profile to a `Claude Code-credentials-<suffix>` entry (macOS) |
| `keychain unbind <p>` | Remove a profile's suffix binding (macOS) |
| `version` | Show version information |
| `help` | Show help message |

## IDE Integration (VSCode)

The Claude Code IDE extensions bundle their own CLI and don't respect `CLAUDE_CONFIG_DIR` by default. claudewho provides wrapper scripts that work with the extension's `claudeProcessWrapper` setting.

### Setup

```bash
claudewho ide-setup
```

This creates the necessary wrapper scripts and prints configuration instructions.

### Option 1: Follow current account

All IDE windows share whichever account is active via `claudewho use <name>`.

Add to your VSCode settings.json (`Cmd+Shift+P` > "Open Settings (JSON)"):

```json
"claude-code.claudeProcessWrapper": "~/.local/bin/claudewho-ide"
```

### Option 2: Per-workspace account (parallel)

Different workspaces can use different accounts simultaneously.

Add to your workspace's `.vscode/settings.json`:

```json
"claude-code.claudeProcessWrapper": "~/.local/bin/claudewho-ide-work"
```

To see all available per-account wrappers:

```bash
claudewho ide-setup
```

Or get the config for a specific account:

```bash
claudewho ide-setup --account work
```

## How it works

- Each account is stored in `~/.claudewho-<name>/`
- Account names are tracked in `~/.claudewho.conf`
- Wrapper scripts like `claudewho-work` are created in `~/.local/bin/` and set `CLAUDE_CONFIG_DIR` before launching Claude
- Your original `~/.claude` directory is never modified

### macOS credential isolation

There are two different Claude Code clients with **different credential
storage models** on macOS, and claudewho handles each one differently.

**CLI (`claude` binary, v2.1.x)** stores OAuth credentials per account
under `Claude Code-credentials-<8hex>` Keychain entries — one entry per
authenticated Anthropic account. When you run `claude` under a given
`CLAUDE_CONFIG_DIR`, it reads that profile's `.claude.json` and looks up
the entry whose `accountUuid` matches. **Multi-account works natively** —
you just need to log in once per profile so each gets its own entry.
claudewho's only job for the CLI is to set `CLAUDE_CONFIG_DIR` to the
right value via the per-account wrappers.

**Desktop app / IDE extension** (VSCode `claude-code` extension, the
Claude desktop app) uses the suffix-less `Claude Code-credentials` entry,
which has no multi-account support. To switch identities in the IDE,
claudewho stashes each profile's token under `Claude Code-credentials-<name>`
and swaps it into the canonical slot on `claudewho use <name>`:

- `claudewho use <next>` stashes the current canonical token under the
  previously active profile, then restores `<next>`'s stash into the
  canonical slot.
- If `<next>` has no stash yet, the canonical entry is cleared so the next
  IDE login is fresh.
- `claudewho remove <name>` deletes the per-profile stash.
- `claudewho keychain status` shows which slots are populated.

Tokens never leave the Keychain. The first time claudewho touches the
canonical entry, macOS may prompt for access — click **Always Allow**.

**Run `claudewho use <name>` before launching VS Code** to choose which
account the IDE extension uses for the session.

#### Auto-fill the IDE slot from a CLI credential (suffix bindings)

If you've already logged in to both accounts via the CLI, you have two
`Claude Code-credentials-<8hex>` Keychain entries. Tell claudewho which
suffix belongs to which profile, and `claudewho use <name>` will copy
that entry's token into the IDE slot automatically — no need to log in
again from the IDE.

```bash
claudewho keychain status               # see which suffixes exist
claudewho keychain bind personal 2a2a2f1a
claudewho keychain bind work     67e870d6
claudewho use personal                  # IDE slot now has personal's token
```

If a profile has no binding yet, `claudewho use` falls back to the older
per-profile stash mechanism (a separate Keychain entry claudewho
maintains itself).

Linux and Windows are unaffected: credentials there live in
`$CLAUDE_CONFIG_DIR/.credentials.json` and are already isolated by profile.

## Requirements

- Claude Code CLI installed (`npm install -g @anthropic-ai/claude-code`)
- Bash 4.0+ or Zsh
- macOS or Linux

## Notes

- Each account requires a separate Anthropic account (different email)
- Each account has its own usage limits
- Check [Anthropic's terms of service](https://www.anthropic.com/terms) to ensure compliance

## License

MIT
