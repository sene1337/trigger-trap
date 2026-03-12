# Validation Matrix

Run:
```bash
node scripts/ask-gate-runtime-proof.mjs
```

Expected minimum matrix:
1. blocked-question-no-token -> rewrite
2. allowed-question-valid-token -> pass
3. allowed-non-question-no-token -> pass
4. blocked-expired-token -> rewrite
5. allowed-non-target -> pass
6. allowed-heartbeat-status -> pass
7. allowed-explicit-131 -> pass
8. blocked-veiled-ask -> rewrite
9. dry-run-veiled-ask -> pass (dry-run)

## Live smoke checklist
- Send one veiled ask without token; confirm rewrite/cancel and audit line.
- Send one 1-3-1 message; confirm bypass and audit line.
- Verify gate token expiry behavior after TTL.
- Confirm no false positives on plain status updates.
