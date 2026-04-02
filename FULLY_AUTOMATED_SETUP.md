# Fully Automated Claude Code Setup

**Date:** 2026-03-31
**Status:** ✅ Complete - Zero Configuration Required

## What's Automated

### 1. 🧠 Dynamic Model Switching (Self-Adaptive)

The AI **automatically switches models while working** based on task difficulty:

| Current Model | Realization | Auto-Switches To |
|---------------|-------------|------------------|
| Opus | "This is simple" | Sonnet or Haiku |
| Sonnet | "Too hard, errors" | Opus |
| Haiku | "Too complex" | Sonnet or Opus |

**No user action needed** - switches happen automatically mid-session.

### 2. 🔄 Auto Context Compaction

Automatically runs `/compact` when:
- 50, 100, 150, 200, 300... tool calls
- 40+ calls since last compact
- 60 second cooldown

**No user action needed** - compact happens in background.

### 3. ✅ Never Stops Midway (Complete All Phases)

AI is instructed to:
- Complete ALL phases before stopping
- Auto-continue to next phase (no confirmation needed)
- Only end session when EVERYTHING is done
- Resume where left off if interrupted

**No user action needed** - AI continues until all work is done.

### 4. 🚀 Auto-Enable Everything-Code Features

All everything-claude-code agents/skills are always active:
- `planner` - Auto-invokes for planning tasks
- `tdd-guide` - Auto-invokes for test tasks
- `code-reviewer` - Auto-invokes after coding
- `security-reviewer` - Auto-invokes for security-sensitive code
- `build-error-resolver` - Auto-invokes on build failures
- All other agents and skills

**No user action needed** - features auto-trigger when relevant.

## Configuration Files

### `~/.claude/settings.json`

```json
{
  "env": {
    "CLAUDE_PLUGIN_ROOT": "/Users/user/.claude/plugins/cache/everything-claude-code/everything-claude-code/1.9.0",
    "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE": "70"
  },
  "model": "claude-sonnet-4-6",
  "hooks": {
    "PreToolUse": {
      "UserPromptSubmit": [
        {
          "type": "command",
          "command": "node \"${CLAUDE_PLUGIN_ROOT}/scripts/hooks/dynamic-model-switcher.js\"",
          "timeout": 5,
          "async": true
        }
      ]
    },
    "PostToolUse": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "node \"${CLAUDE_PLUGIN_ROOT}/scripts/hooks/auto-compact-inject.js\"",
            "timeout": 5,
            "async": true
          },
          {
            "matcher": "*",
            "hooks": [
              {
                "type": "command",
                "command": "node \"${CLAUDE_PLUGIN_ROOT}/scripts/hooks/ensure-continuation.js\"",
                "timeout": 5,
                "async": true
              }
            ]
          }
        ]
      }
    ],
    "PostToolUseFailure": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "node \"${CLAUDE_PLUGIN_ROOT}/scripts/hooks/track-task-outcome.js\"",
            "timeout": 5,
            "async": true
          }
        ]
      }
    ]
  }
}
```

### Hook Files (All Created)

| File | Purpose |
|------|---------|
| `dynamic-model-switcher.js` | Auto-switches model based on task difficulty |
| `track-task-outcome.js` | Tracks success/failure for model decisions |
| `auto-compact-inject.js` | Auto-triggers /compact at thresholds |
| `ensure-continuation.js` | Prevents stopping midway, continues phases |
| `auto-model-switcher.js` | Legacy model analyzer |
| `auto-execute.js` | Combined analyzer |

### Skills (All Created)

| Skill | Purpose |
|-------|---------|
| `auto-model-and-compact` | Model switching + compact automation |
| `complete-all-phases` | Never stop midway, finish all tasks |
| `auto-enable-everything` | Auto-enables all everything-claude-code features |
| `strategic-compact` | Suggests compact at logical breakpoints |
| `auto-execute` | Combined automation |

## How It Works

### Session Flow

```
┌─────────────────────────────────────────────────────────────────┐
│  SESSION START                                                  │
│    ↓                                                             │
│    Load phase state (what was completed last session)           │
│    ↓                                                             │
│    Identify remaining work                                      │
│    ↓                                                             │
│    START WORK IMMEDIATELY (no greeting)                         │
│    ↓                                                             │
│  WHILE WORKING:                                                 │
│    ↓                                                             │
│    ├─→ Dynamic Model Switcher                                   │
│    │   Analyzes task difficulty                                 │
│    │   Switches model automatically                             │
│    │   (Opus ↔ Sonnet ↔ Haiku)                                 │
│    │                                                             │
│    ├─→ Outcome Tracker                                          │
│    │   Records success/failure                                  │
│    │   Informs model decisions                                  │
│    │                                                             │
│    ├─→ Auto Compact                                             │
│    │   Monitors tool call count                                 │
│    │   Triggers /compact at thresholds                          │
│    │                                                             │
│    └─→ Continuation Check                                       │
│        Checks remaining phases/tasks                            │
│        Prevents premature session end                           │
│        Auto-continues to next phase                             │
│    ↓                                                             │
│  PHASE COMPLETE:                                                │
│    ↓                                                             │
│    Announce completion                                          │
│    ↓                                                             │
│    START NEXT PHASE IMMEDIATELY (no confirmation)               │
│    ↓                                                             │
│  ALL PHASES COMPLETE:                                           │
│    ↓                                                             │
│    Show summary                                                 │
│    ↓                                                             │
│    Session can now end                                          │
└─────────────────────────────────────────────────────────────────┘
```

## Monitoring

### Check Current State

```bash
# Current model and task state
cat /tmp/claude-code/claude-session-state-*

# Model switches
cat /tmp/claude-code/claude-model-override

# Remaining tasks/phases
cat /tmp/claude-code/claude-phase-state-*
cat /tmp/claude-code/claude-task-list-*

# Work in progress flag
cat /tmp/claude-code/claude-work-in-progress-*
```

### Watch Log Messages

```
[DynamicModel] Switch: SONNET → OPUS | 3 consecutive errors - need more capable model
[DynamicModel] Switch: OPUS → SONNET | Task is easier than expected - saving cost
[AutoCompact] Triggering /compact at 52 tool calls (52 since last)
[Continuation] 3 phases remaining - continuing automatically
```

## Example Session

```
User: "Implement the Anime4K production plan"

[Session starts]
  → Loads plan: 5 phases
  → Phase 1: Complete (from last session)
  → Phase 2: In progress, 2 tasks remaining
  → Starts immediately on Phase 2, Task 3

[Working on Phase 2, Task 3]
  → Model: Sonnet (default)
  → Build error encountered
  → Error 1: Fix attempt fails
  → Error 2: Still failing
  → Error 3: Another related error
  → [DynamicModel] Switch: SONNET → OPUS (3 consecutive errors)
  → Opus analyzes, fixes issue
  → Task 3 complete

[Task 4]
  → Model: Opus
  → Task is straightforward
  → [DynamicModel] Switch: OPUS → SONNET (task is easier)
  → Sonnet completes Task 4

[Phase 2 Complete]
  → [Continuation] Phase 2 complete, 3 phases remaining
  → Immediately starts Phase 3

[Working through Phase 3...]
  → Tool calls reach 50
  → [AutoCompact] Triggering /compact
  → Context compacted, state preserved
  → Continues working

[Session continues until ALL phases complete]
  → No stopping midway
  → No confirmation prompts
  → Just continuous work

[All Phases Complete]
  → Shows summary
  → Session ends
```

## Customization (Optional)

### Change Default Model

```json
{
  "model": "claude-haiku-4-5-20251001"  // Start cheap
}
```

### Adjust Compact Frequency

```json
{
  "env": {
    "COMPACT_THRESHOLD": "30"  // Compact more frequently
  }
}
```

### Disable Specific Features

Remove corresponding hook from settings.json.

## Troubleshooting

### Feature not working

1. Check hook is in settings.json
2. Verify script exists
3. Check temp files for state

### Model not switching

```bash
cat /tmp/claude-code/claude-model-override
cat /tmp/claude-code/claude-session-state-*
```

### Compact not triggering

```bash
cat /tmp/claude-code/claude-tool-count-*
ls -la /tmp/claude-code/claude-inject-input
```

### AI stopping midway

Check continuation hook:
```bash
cat /tmp/claude-code/claude-phase-state-*
cat /tmp/claude-code/claude-continuation-prompt
```

## Summary

| Feature | Status | User Action |
|---------|--------|-------------|
| Model Switching | ✅ Self-Adaptive | None |
| Auto Compact | ✅ Automated | None |
| Continue All Phases | ✅ Enforced | None |
| Auto-Enable Features | ✅ Always On | None |
| Error Tracking | ✅ Active | None |
| Cost Optimization | ✅ Downgrades when easy | None |
| Capability Escalation | ✅ Upgrades when hard | None |

**Everything is fully automated. Just work naturally.**
