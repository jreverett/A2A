# herald agent instructions

The full agent protocol lives in [skill/SKILL.md](skill/SKILL.md) — read that.
It covers sending (messages, files, tasks, threading), staying reachable
(`herald wait` as a background process), claiming items when several agent
sessions run at once, and triage rules for incoming work.

This file exists so harnesses that auto-load `AGENTS.md` find the protocol;
Claude Code users should install the skill instead (see `install.sh`).
