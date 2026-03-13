# Validation Matrix

Run:
```bash
node scripts/ask-gate-runtime-proof.mjs
```

Expected minimum matrix:
1. blocked-question-no-token -> rewrite
2. allowed-cron-source-bypass -> pass
3. allowed-heartbeat-source-bypass -> pass
4. allowed-subagent-completion-source-bypass -> pass
5. allowed-question-valid-token -> pass
6. allowed-non-question-no-token -> pass
7. blocked-expired-token -> rewrite
8. allowed-non-target -> pass
9. allowed-heartbeat-status -> pass
10. allowed-explicit-131 -> pass
11. blocked-veiled-ask -> rewrite
12. dry-run-veiled-ask -> pass (dry-run)

## Live smoke checklist
- Send one veiled ask without token; confirm rewrite/cancel and audit line.
- Send one 1-3-1 message; confirm bypass and audit line.
- Verify gate token expiry behavior after TTL.
- Confirm no false positives on plain status updates.
