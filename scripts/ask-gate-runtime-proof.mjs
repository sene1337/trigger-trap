#!/usr/bin/env node

import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { pathToFileURL, fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

function resolveAskGateCorePath() {
  const envPath = process.env.ASK_GATE_CORE_PATH;
  const candidates = [
    envPath,
    path.resolve(process.cwd(), ".openclaw/extensions/ask-gate-runtime/src/ask-gate-core.mjs"),
    path.resolve(__dirname, "../.openclaw/extensions/ask-gate-runtime/src/ask-gate-core.mjs"),
    path.resolve(__dirname, "../../../.openclaw/extensions/ask-gate-runtime/src/ask-gate-core.mjs"),
    path.resolve(__dirname, "../../.openclaw/extensions/ask-gate-runtime/src/ask-gate-core.mjs")
  ].filter(Boolean);

  for (const candidate of candidates) {
    if (fs.existsSync(candidate)) return candidate;
  }

  throw new Error(
    [
      "Could not find ask-gate-core.mjs.",
      "Set ASK_GATE_CORE_PATH or run from a workspace with .openclaw/extensions/ask-gate-runtime.",
      `Checked:\n- ${candidates.join("\n- ")}`
    ].join("\n")
  );
}

const askGateCorePath = resolveAskGateCorePath();
const {
  DEFAULT_ASK_GATE_CONFIG,
  createAskGateSourceTracker,
  evaluateAskGate
} = await import(pathToFileURL(askGateCorePath).href);

const OWNER_CHAT_ID = process.env.OWNER_CHAT_ID ?? "100000000";

function writeJson(filePath, value) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, JSON.stringify(value, null, 2));
}

function buildToken(nowEpoch, expiresOffsetSeconds) {
  return {
    version: 1,
    topic: "proof topic",
    createdAtEpoch: nowEpoch,
    expiresAtEpoch: nowEpoch + expiresOffsetSeconds,
    expiresAtIso: new Date((nowEpoch + expiresOffsetSeconds) * 1000).toISOString(),
    lcmEvidence: "memory/2026-03-12.md: relevant note",
    localEvidence: "ops/continuous-improvement/ask-gate/example.md"
  };
}

function buildSubagentHistory(message) {
  return [
    {
      role: "assistant",
      content: [{ type: "text", text: "Previous reply." }]
    },
    {
      role: "user",
      content: [{ type: "text", text: "Subagent completion ready." }],
      provenance: {
        kind: "inter_session",
        sourceSessionKey: "subagent:test",
        sourceChannel: "webchat",
        sourceTool: "subagent_announce"
      }
    },
    {
      role: "assistant",
      content: [{ type: "text", text: message }]
    }
  ];
}

function runCase(rootDir, definition) {
  const gateFilePath = path.join(rootDir, definition.id, "ask-allowed.json");
  const auditLogPath = path.join(rootDir, definition.id, "ask-guard.log");
  const nowEpoch = 1_762_987_200;
  const nowMs = nowEpoch * 1000;
  const sourceTracker = createAskGateSourceTracker();
  const sessionKey = definition.sessionKey ?? `session:${definition.id}`;

  if (definition.token === "valid") {
    writeJson(gateFilePath, buildToken(nowEpoch, 600));
  } else if (definition.token === "expired") {
    writeJson(gateFilePath, buildToken(nowEpoch - 1_200, 60));
  }

  const config = {
    ...DEFAULT_ASK_GATE_CONFIG,
    ownerChatId: OWNER_CHAT_ID,
    mode: definition.mode ?? "cancel",
    dryRun: definition.dryRun ?? false,
    tokenTtlSeconds: 600,
    gateFilePath,
    auditLogPath
  };

  if (definition.runSource) {
    sourceTracker.noteRun({
      sessionKey,
      trigger: definition.runSource.trigger,
      historyMessages: definition.runSource.historyMessages ?? [],
      nowMs
    });
    sourceTracker.noteAssistantMessage({
      sessionKey,
      nowMs,
      message: {
        role: "assistant",
        content: [{ type: "text", text: definition.message }]
      }
    });
  }

  const result = evaluateAskGate({
    event: {
      to: definition.to ?? OWNER_CHAT_ID,
      content: definition.message,
      metadata: {
        channel: "telegram",
        ...(definition.metadata ?? {})
      }
    },
    ctx: {
      channelId: definition.channelId ?? "telegram",
      conversationId: definition.to ?? OWNER_CHAT_ID
    },
    config,
    nowEpoch,
    sourceBypass: sourceTracker.consumeBypass({
      content: definition.message,
      metadata: definition.metadata,
      nowMs
    })
  });

  return {
    id: definition.id,
    expected: definition.expected,
    actual: result.action,
    dryRun: Boolean(result.dryRun),
    reason: result.reason,
    sourceBypass: result.sourceBypass ?? null
  };
}

const definitions = [
  {
    id: "blocked-question-no-token",
    message: "How should I handle the Kazuo position?",
    expected: "cancel"
  },
  {
    id: "allowed-cron-source-bypass",
    message: "How should I handle the Kazuo position?",
    runSource: {
      trigger: "cron"
    },
    expected: "pass"
  },
  {
    id: "allowed-heartbeat-source-bypass",
    message: "How should I handle the Kazuo position?",
    runSource: {
      trigger: "heartbeat"
    },
    expected: "pass"
  },
  {
    id: "allowed-subagent-completion-source-bypass",
    message: "How should I handle the Kazuo position?",
    runSource: {
      trigger: "user",
      historyMessages: buildSubagentHistory("How should I handle the Kazuo position?")
    },
    expected: "pass"
  },
  {
    id: "allowed-question-valid-token",
    message: "How should I handle the Kazuo position?",
    token: "valid",
    expected: "pass"
  },
  {
    id: "allowed-non-question-no-token",
    message: "The report is ready for review.",
    expected: "pass"
  },
  {
    id: "blocked-expired-token",
    message: "What is the current target?",
    token: "expired",
    expected: "cancel"
  },
  {
    id: "allowed-non-brad-target",
    message: "How should I handle the Kazuo position?",
    to: "999999",
    expected: "pass"
  },
  {
    id: "allowed-heartbeat-status",
    message: "DONE: hook\nBLOCKED: none\nHEARTBEAT_OK",
    expected: "pass"
  },
  {
    id: "allowed-explicit-131",
    message: "1-3-1\n1) problem\n2) options\n3) recommendation",
    expected: "pass"
  },
  {
    id: "blocked-veiled-ask",
    message: "I can send the full breakdown if you want.",
    expected: "cancel"
  },
  {
    id: "dry-run-veiled-ask",
    message: "Let me know if you want the detailed version.",
    dryRun: true,
    expected: "pass"
  }
];

const rootDir = fs.mkdtempSync(path.join(os.tmpdir(), "ask-gate-proof-"));
const results = definitions.map((definition) => runCase(rootDir, definition));

process.stdout.write(`${JSON.stringify(results, null, 2)}\n`);
