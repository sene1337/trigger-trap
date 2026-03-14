# Runtime Integration

Trigger Trap is a runtime hard gate for behavior drift that can persist beyond bootstrap-file hard gates. Bootstrap policy text defines intent; this runtime integration enforces that intent at outbound send time.

## 1) Register the plugin hook
Use a pre-send hook (`message_sending`) that can:
- pass
- rewrite content
- cancel send

Recommended safety defaults:
- enable `dryRun` first during rollout so would-block decisions are logged safely,
- fail open on hook errors (fallback passthrough),
- scope explicitly to Telegram + specific target chat ID.

The runtime handler should:
1. Normalize config.
2. Pre-classify proven source bypasses:
   - `llm_input` with `ctx.trigger="cron"` -> `cron-origin`
   - `llm_input` with `ctx.trigger="heartbeat"` -> `heartbeat-origin`
   - `llm_input` with latest inter-session user provenance `sourceTool="subagent_announce"` -> `subagent-completion-origin`
   - bridge that source to the final outbound text via `before_message_write`
   - **TTL must be long enough for multi-step agent runs** (recommended ≥15 min / 900s). Cron-triggered jobs do real work (file scanning, report generation) that can take several minutes. A short TTL (e.g. 60s) causes the bypass to expire before the outbound message is sent.
   - **Preserve existing bypass entries across subsequent LLM calls.** When a follow-up `llm_input` fires without a trigger tag (e.g. during tool-use loops), do NOT delete the existing source bypass entry. Only overwrite when a new valid trigger is detected.
3. Classify outbound content (question, veiled ask, bypass, non-question).
4. Check short-TTL gate token (`ask-allowed.json`).
5. Return `rewrite`/`cancel` or pass.
6. Append audit line to `logs/ask-guard.log`.

## 2) Required config fields
- `enabled` (bool)
- `ownerChatId` (string)
- `mode` (`rewrite|cancel`)
- `dryRun` (bool)
- `tokenTtlSeconds` (number >= 1)
- `gateFilePath` (string)
- `auditLogPath` (string)
- `rewriteMessage` (string)

## 3) Token schema
Support canonical + legacy keys.
Canonical:
- `createdAtEpoch`
- `expiresAtEpoch`
Legacy fallback:
- `created_at`
- `expires_at`

Recommended payload extras:
- `topic`
- `lcmEvidence`
- `localEvidence`

## 4) Target matching
Normalize IDs before comparison so these resolve equivalently when intended:
- `<OWNER_CHAT_ID>`
- `telegram:<OWNER_CHAT_ID>`

## 5) Audit decisions
Write one-line decisions:
- `ALLOW`
- `ALLOW_BYPASS`
- `PASS_THROUGH`
- `DRY_RUN_BLOCK`
- `BLOCK_REWRITE`
- `BLOCK_CANCEL`

When the bypass is source-based, include the source label (`cron-origin`, `heartbeat-origin`, `subagent-completion-origin`) in the audit line.

## 6) Expand undesired-behavior coverage
Extend behavior controls without redesigning the gate by updating:
- veiled-ask/filler detection patterns,
- bypass classes,
- target scope (channel/recipient),
- action mode (`rewrite` vs `cancel`).

Treat expansion as configuration + detector evolution, then rerun the matrix and live smoke tests.

## 7) Mandatory log review
Do not claim success from config or script presence alone.
Review audit logs (`ask-guard.log`) to confirm real decisions match policy intent over actual conversations.
