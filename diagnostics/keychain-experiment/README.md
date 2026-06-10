# Keychain isolation experiment

A controlled study of how Claude Code v2.1.x stores OAuth credentials on macOS,
specifically whether two separate Anthropic accounts can coexist when used via
two `CLAUDE_CONFIG_DIR`-isolated claudewho profiles.

## Findings (2026-06-10)

After running the 7-step protocol against two real Anthropic accounts
(personal Pro and work Maxio), the empirical picture is:

1. **CLI multi-account is native.** v2.1.x writes a separate Keychain entry
   per account (`Claude Code-credentials-<8hex>`). Logging into a second
   account does **not** delete the first account's entry — both coexist.
2. **The suffix is deterministic per Anthropic account.** Re-logging into
   the same account regenerates the same 8-hex suffix (`2a2a2f1a` for the
   personal account in both observed logins).
3. **Claude disambiguates by `.claude.json` `accountUuid`.** Under
   `CLAUDE_CONFIG_DIR=X`, Claude reads `X/.claude.json`'s `oauthAccount.
   accountUuid` and selects the matching suffixed Keychain entry. If
   `.claude.json` has no identity (fresh profile), it falls back to
   whichever entry is available — that's how a never-logged-in profile
   silently inherits another profile's identity.
4. **The suffix-less `Claude Code-credentials` entry is for the Desktop /
   IDE Claude Code**, not the CLI. The IDE has no multi-account support.

**Implications for claudewho:**

- For the **CLI**, no Keychain swap is needed. After each profile logs in
  once, `CLAUDE_CONFIG_DIR=<profile>` is sufficient to get the right
  identity. claudewho's job here is only to set `CLAUDE_CONFIG_DIR` and
  not stomp it (a wrapper-stomp bug was found and fixed alongside this
  experiment — see the project memory `claudewho-claude-wrapper-stomp-bug`).
- For the **IDE / Desktop**, the v2.3.0 stash-and-swap of the suffix-less
  entry is the right mechanism. Run `claudewho use <name>` before launching
  the IDE.

The original "shared identity across profiles" complaint that motivated
this investigation turned out to be the empty-profile fallback from
finding 3 plus the wrapper-stomp bug — *not* a fundamental limitation of
Claude Code's credential storage.

The rest of this document describes the protocol that produced these
findings. Keep it around in case Anthropic changes the credential model
again and we need to re-derive the new behavior.

## Why this exists

`claudewho` v2.3.0 added a Keychain stash/swap mechanism on the assumption that
Claude Code stores OAuth credentials under a single shared Keychain entry named
`Claude Code-credentials`. Investigation revealed that **v2.1.x does not use
that entry** — it stores credentials under `Claude Code-credentials-<8hex>`,
where the 8-character suffix appears to be derived from a per-OAuth-flow
`clientId`, not from `CLAUDE_CONFIG_DIR` or the account identity.

The v2.3.0 swap mechanism is therefore a no-op: it manipulates a legacy slot
Claude no longer reads from. We need empirical data on how the suffixed
entries actually behave under logout/login cycles before we can design a
working fix.

## Hypotheses we want to test

1. **Profile sharing.** With one account logged in via profile A, does Claude
   under profile B see the same identity, or does it prompt for a fresh login?
2. **Login behavior.** When a second account is logged in from profile B, does
   the new Keychain entry **replace** account A's entry, **add** a second
   entry alongside, or **delete-and-create** in some other order?
3. **Suffix derivation.** Does the same Anthropic account always produce the
   same 8-hex suffix when re-logged in, or does each login generate a fresh
   one? (This determines whether `claudewho` can predict and restore suffix
   names, or whether it must snapshot them at stash-time.)
4. **`.claude.json` writeback.** When Claude runs under `CLAUDE_CONFIG_DIR=X`
   but uses keychain credentials for account Y, does the `oauthAccount` block
   in `X/.claude.json` get overwritten with Y's identity? (This is the
   mechanism by which both profiles' `.claude.json` files ended up showing the
   same email.)

## Prerequisites

- macOS with `jq` installed (`brew install jq` if missing).
- Two distinct Anthropic accounts you can sign into.
- Both `~/.claudewho-personal` and `~/.claudewho-work` profile directories
  already exist (run `claudewho list` to confirm).
- You are not in a hurry: each login involves a browser OAuth flow.

## Setup

```bash
cd /path/to/claudewho/diagnostics/keychain-experiment
# Verify the script is executable
ls -l observe.sh
```

Snapshots are written to `~/claudewho-experiment/<HHMMSS>-<label>.txt`. Run
the script with a label after each step:

```bash
./observe.sh <label>
```

## The protocol — 7 snapshots

> **Important:** exit the Claude Code session you used to design this
> experiment first, otherwise its in-memory token will keep the keychain
> "warm" and confuse the diagnostics. Do that before Step 0.

### Step 0 — clean slate

```bash
# Force logout from both profiles
claudewho use personal && claude     # type /logout, then /exit
claudewho use work     && claude     # type /logout, then /exit

# Purge any stragglers the experiment cares about
security delete-generic-password -s "Claude Code-credentials"          2>/dev/null || true
security delete-generic-password -s "Claude Code-credentials-personal" 2>/dev/null || true
security delete-generic-password -s "Claude Code-credentials-work"     2>/dev/null || true
# Delete the two real entries we observed pre-experiment (replace with
# whatever your own list-keychains showed):
security delete-generic-password -s "Claude Code-credentials-2a2a2f1a" 2>/dev/null || true
security delete-generic-password -s "Claude Code-credentials-67e870d6" 2>/dev/null || true

./observe.sh "0-clean-slate"
```

Expected at this point: zero `Claude Code-credentials*` keychain entries. If
any remain, add a `security delete-generic-password -s "<name>"` for each.

### Step 1 — log in as account A via the personal profile

```bash
claudewho use personal
claude                # log in as your PERSONAL account, then /exit immediately
./observe.sh "1-personal-loggedin"
```

### Step 2 — switch profile without launching claude

```bash
claudewho use work
./observe.sh "2-switched-to-work-no-login"
```

This isolates the effect of `claudewho use` alone (it should not touch the
keychain).

### Step 3 — launch claude under the work profile but do not log in

```bash
claude                # do NOT log in. Just observe whose identity it shows. /exit.
./observe.sh "3-claude-launched-under-work"
```

**Key observation:** does claude under `CLAUDE_CONFIG_DIR=work` come up
authenticated as your personal account, or does it prompt for login? Also
check whether `work/.claude.json` was rewritten with personal's identity.

### Step 4 — log in as account B from the work profile

```bash
claude                # /login as your WORK account, then /exit
./observe.sh "4-work-loggedin"
```

**Key observations:**
- Does the personal-account keychain entry from Step 1 still exist? (Compare
  the suffix from Step 1's snapshot.)
- Is there a new suffixed entry for work, or did the existing one's password
  just get overwritten?

### Step 5 — switch back to the personal profile, launch claude without re-login

```bash
claudewho use personal
claude                # do NOT send a prompt. Just look at the identity shown. /exit.
./observe.sh "5-back-to-personal"
```

**Key observation:** is claude under personal now claiming to be the work
account (i.e., login at Step 4 was destructive to account A), or is it back
to personal (i.e., the two coexist)?

### Step 6 — collect snapshots

```bash
ls -la ~/claudewho-experiment/
```

Paste all seven `.txt` files back into the conversation.

## What the data tells us

Map each observation to a design implication:

| Question | Observation that answers it | Implication for the fix |
|---|---|---|
| Are profiles auth-isolated by default? | Step 3 shows personal identity under work profile | Confirms we need a real workaround |
| Same account → same suffix? | Compare Step 1 suffix to (later) re-login suffix | If stable: claudewho can predict suffix per account. If unstable: must snapshot at stash-time |
| Login adds or replaces? | Step 4 entry count vs Step 1 entry count | Determines whether claudewho must capture creds **before** the destructive event |
| Does `.claude.json` track active identity? | Step 3 mtime + email of `work/.claude.json` | Tells us whether we can rely on `.claude.json` as a "what account is this profile bound to" hint |

## After the experiment

```bash
# Optional: clear all experimental keychain entries and start fresh
for svc in $(security dump-keychain ~/Library/Keychains/login.keychain-db 2>/dev/null \
  | grep -oE '"svce"<blob>="Claude Code-credentials[^"]*"' \
  | sed 's/"svce"<blob>="\(.*\)"/\1/'); do
  security delete-generic-password -s "$svc" 2>/dev/null
done
# Then log in fresh on the profile you want to actually use.
```

## Notes on safety

- `observe.sh` reads only metadata (`svce`, `acct`, `cdat`, `mdat`). It does
  not extract or print Keychain passwords.
- `security dump-keychain` may trigger a one-time access prompt the first
  time. Click **Always Allow** if you want subsequent runs to be silent.
- The snapshot `.txt` files contain no credentials. They are safe to paste
  into chat or commit to the repo for review.

## Whether to commit this directory

Up to you. It's a one-off investigation, not part of claudewho's runtime
behavior. If you do commit it, consider adding `claudewho-experiment/` to
`.gitignore` so the per-run snapshot directory under `$HOME` does not get
confused for a tracked path.
