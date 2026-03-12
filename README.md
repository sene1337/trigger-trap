# Trigger Trap

Trap your agent’s undesired behaviors **before they trigger you**.

Trigger Trap is a runtime hard gate for behavior drift that persists even when bootstrap rules and policy files already exist.

## Why this exists

Built from a real operator pain pattern observed on 2026-03-12:
- bootstrap hard gates alone were not reliably preventing recurring behavior regressions,
- low-quality asks still slipped through under pressure,
- style regressions (for example filler or veiled asks like “if you want…”) reappeared,
- trust required enforcement at outbound send-time, not reminders.

This skill adds mechanical enforcement and auditable logs so behavior quality can be measured and tuned.

## What it enforces

- Evidence-first ask behavior before question-form outbound messages
- Detection of veiled asks (including patterns without `?`)
- Explicit bypasses for structured operational formats (for example `1-3-1`, `DONE/BLOCKED`, `HEARTBEAT_OK`)
- Runtime actions: `rewrite` or `cancel`
- Dry-run mode for safe rollout tuning
- Fail-open passthrough on hook error to avoid delivery outages

## Core idea

- **Bootstrap files define policy**
- **Trigger Trap enforces policy at runtime (`message_sending`)**

## How to know it works

Do not trust configuration alone.
Review `ask-guard.log` and validate decision lines over real traffic:
- `ALLOW`
- `ALLOW_BYPASS`
- `PASS_THROUGH`
- `DRY_RUN_BLOCK`
- `BLOCK_REWRITE`
- `BLOCK_CANCEL`

If logs don’t show expected decisions, the trap is not yet tuned.

## Repository layout

- `SKILL.md` — skill definition and workflow
- `scripts/pre-ask-gate.sh` — short-TTL evidence token minting
- `scripts/send-guard.sh` — outbound guard helper
- `scripts/ask-gate-runtime-proof.mjs` — proof matrix harness
- `references/runtime-integration.md` — runtime wiring/config details
- `references/validation-matrix.md` — expected test matrix and smoke checklist

## Notes

This repo packages the skill for experimentation and adaptation. Start in `dryRun`, tune patterns from logs, then enforce with `rewrite` (or `cancel` if required).
