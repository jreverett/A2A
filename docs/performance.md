# Performance & streamlining (design)

Make a herald round-trip faster and cheaper in tokens, without losing the
agent-to-agent flexibility.

Status: phase 1 and the daemon-answered fast-path shipped in 0.5.0
(`herald ask`, `wait --read`, `herald ping`, skill trims). Remaining phases
below are still design.

## The insight

Transport (Tailscale HTTP) is milliseconds. Almost all the wall-clock — and
*all* the token cost — is **LLM inference at each hop**, and it scales with two
things:

- the **number of separate tool-call turns** an agent takes per action (each
  turn is a full inference round-trip), and
- **whether an LLM has to be involved at all** for a given message.

So the levers are: take fewer turns, generate less, and — for routine work —
don't wake a model in the first place.

## Principles

- **Don't think when you don't have to.** The fastest, cheapest message is one
  no agent has to reason about. Prefer deterministic handling for anything
  well-defined; escalate to the model only for genuinely open-ended work.
- **Fewer turns beats terser prose.** Collapsing five tool calls into one saves
  far more than trimming wording.
- **Right-size the model.** Light work (acks, status, dispatch) should run on a
  fast model; reserve the heavy model for real reasoning.

## Levers

### 1. Collapse tool-call turns (cheap, universal)

- **`herald ask <peer> -t/-m …`** — send + wait + return the result in a single
  command, so a synchronous request/reply is *one* tool call instead of
  send → wait → read (three turns).
- **`herald wait --read`** — return the item's content on wake, folding wait+read
  into one turn.
- **Skill: drop the preamble.** Stop making the agent run `herald status` /
  `herald peer list` to "confirm setup" before every action — assume it's set
  up and handle the error only if one occurs. Two turns gone immediately.
- **Single reply, not working→done** for quick tasks — one round-trip, not two.

### 2. Structured, terse messages

- Push context into structured `--meta` fields (repo, branch, action, paths);
  keep human prose to one line; attach detail as a file rather than generating
  paragraphs (and ASCII tables) inline. Fewer output tokens = faster generation
  on the sending side and cheaper reads on the receiving side.
- A documented `--meta` schema (and optional message templates) makes replies
  short *and* machine-parseable — which is also what makes lever 3 possible.

### 3. Deterministic fast-paths — no LLM in the loop (biggest token saver)

- **Daemon-answered `status` / `ping`** — a remote health/version query answered
  by the peer's *daemon*, not their agent. No wake, no inference, instant. A new
  authenticated read-only endpoint.
- **Registered action handlers** — a peer allowlists named actions
  (`action=run-tests → ./scripts/run-tests.sh`); a structured task with a known
  `action` is dispatched to that script and its result returned, with **no agent
  reasoning**. The model is only woken for tasks with no registered handler.
- **Security:** handlers run real code in response to remote input, so this is
  strictly an **allowlist of explicitly-registered actions**, and it must
  respect the per-peer scoping from [access-control.md](access-control.md) —
  same sandbox, same roots. Never a generic "run what you're told" path.

### 4. Right-size the model

- Run the **listener/triage on a fast model** (e.g. Haiku); escalate to the
  heavy model only when a task needs real reasoning. Keeps acks and dispatch
  cheap. herald's job is to keep triage simple enough that a small model can do
  it reliably — levers 1–3 all push in that direction.
- This is largely a "how you run the listener" choice, but herald should
  document the pattern and make the light path the default.

## Phased plan

1. **Turn-collapsing + skill trims** — DONE (0.5.0): `herald ask`, `wait --read`,
   drop the setup preamble, single-reply default. Small, pure wins, benefits
   every exchange. No new concepts.
2. **Deterministic fast-paths** — daemon-answered `ping` (version + liveness, no
   agent) DONE (0.5.0). Registered action-handler dispatch (allowlisted, per-peer
   scoped) DEFERRED — it runs remote-triggered code, so it must not ship before
   the access-control identity and sandbox exist. The big token saver, but it
   waits on that foundation.
3. **Structured message schema + templates** — the `--meta` schema and terse
   formats that make replies short and parseable.
4. **Fast-model listener pattern** — DOCUMENTED (README): run the listener on a
   fast, low-cost model, escalate to a stronger one for real work. herald can't
   pick the model (that's the harness's job), so this stays guidance, not code.

## Impact

- Phase 1 removes ~3–4 inference turns from a typical request/reply — the
  dominant cost — with no behavioural change.
- Phase 2 removes the model *entirely* from routine exchanges (status, known
  actions), which is both the largest latency and the largest token saving.
- Phases 3–4 shrink and cheapen whatever inference remains.

## Open questions

- Handler dispatch owner: does the daemon run registered handlers directly, or a
  separate lightweight worker process? Ties into the access-control sandbox
  decision.
- `herald ask` timeout/backpressure behaviour when the peer is slow or offline —
  fall back to the async queue, or error?
- Whether the fast/heavy model split is expressed in herald at all, or left
  entirely to how the user launches the listener.
