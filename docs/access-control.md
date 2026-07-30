# Access control (design)

Per-peer scoping so each person you connect with can only touch the part of
your machine you meant for them — Simon your work tree, Farhan only the hobby
project you share with him.

Status: design, not yet built. This captures the agreed shape before
implementation.

## Principles

- **Simple to set up.** The user declares intent in one line; herald hides all
  the mechanics (tokens, sandboxing, routing). Never expose sandbox plumbing as
  required config.
- **Agent/CLI to change, a glanceable table to verify.** You grant and revoke
  access by telling your agent (which runs the CLI); you *audit* it by looking
  at a read-only table. Security config is exactly where you shouldn't have to
  trust a chat transcript that the scoping came out right.
- **Strong path is the default.** "Simple" must never quietly mean "weak": the
  confined path is what you get out of the box, degrading gracefully only where
  the platform can't enforce it.

## Threat model

The real attack surface is the receiving agent acting on **untrusted task text**
— a malicious or careless peer sending a request engineered to read or damage
files outside their remit (prompt injection to escape scope). Also: attached
files landing in sensitive paths, and a leaked or shared token. Access control
exists to shrink each peer's blast radius.

## Identity (prerequisite)

Per-peer authorisation is meaningless until the sender is authenticated. Today
there is a single shared inbound token and `from` is self-asserted, so any peer
holding the token could impersonate another. The design replaces this with:

- **Per-peer inbound tokens** — each peer gets a distinct secret to reach you;
  the token *is* the identity, and is rotatable to revoke one peer without
  affecting the rest. Minted and exchanged during the existing
  `introduce`/`accept` flow, invisible to the user.
- **Tailscale identity as a cross-check** — the daemon can ask
  `tailscale whois` who owns the source node and reject if it doesn't match the
  token's peer. Defence in depth; unspoofable.

## Policy model

Each peer maps to a **root** and a set of **capabilities**:

```
peers:
  simon:  { token: ..., root: ~/work,            can: [message, task, file] }
  farhan: { token: ..., root: ~/projects/hobby,  can: [message, task] }
```

- **root** — the only part of the filesystem this peer's work may touch.
- **can** — which item kinds they may send (`message` / `task` / `file`), plus
  whether their tasks may auto-run or always require human approval.
- **Domains** are a later shortcut: name a scope once
  (`herald domain add hobby --root ~/projects/hobby`) and assign several peers
  to it. Same config model, no rework. Per-peer `root` ships first.

## Enforcement

Layered, so the guarantee is honest about what each tier can promise:

1. **Herald-enforced, always on, zero setup.** A peer's attached files can only
   land under their `root`; their tasks are stamped "confined to `<root>`"; and
   capability gating (kind, plus auto-run vs require-approval) is enforced at the
   daemon. Real, transport-level.
2. **OS-enforced where the platform allows.** When herald mediates task
   execution it wraps it in an unprivileged Linux filesystem jail so even a
   prompt-injected task physically cannot read outside `root`. The user
   configures none of this.
3. **Agent-honoured fallback.** Where an OS jail isn't available, the item's
   `confined to <root>` stamp instructs the agent to stay in scope. A guardrail,
   not a wall — the weakest tier, used only as a fallback.

## Interface

Change access through your agent (or the CLI it drives):

```bash
herald peer add farhan http://<ip>:8765 <token> --root ~/projects/hobby
herald peer scope simon --root ~/work --can task,file
herald peer revoke farhan        # rotates their token
```

Verify it with a read-only table — no mutation surface, no new attack surface:

```
$ herald access
PEER     DOMAIN   ROOT                 CAN            LAST SEEN
simon    work     ~/work               msg task file  2m ago
farhan   hobby    ~/projects/hobby     msg task       online
```

## Phasing

1. Per-peer inbound tokens (identity) + `herald access` audit table.
2. Per-peer `root` + herald-enforced file placement + capability gating.
3. OS-enforced filesystem jail for mediated task execution.
4. Named domains as a grouping shortcut.

## Open questions

- Which unprivileged sandbox mechanism for tier 2 (Landlock vs bubblewrap), and
  the fallback matrix per platform (WSL, native Linux, macOS).
- How the airtight agent-confinement case is wired: does the installer stand up
  a per-domain sandboxed listener, or does herald mediate task execution itself?
- Capability defaults for a newly added peer — message-only until widened, and
  tasks require approval by default?
