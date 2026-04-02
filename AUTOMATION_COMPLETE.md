# Automation Complete - Dynamic Model Switching & Auto Compact

**Date:** 2026-03-31
**Status:** ✅ Fully Automated

## What You Asked For

> "make sure the model can decide while it is working - if opus understands the task is not hard, it switches to a lower model. If sonnet thinks the task is too hard, it switches to opus."

## ✅ Implemented: Self-Adaptive Model Switching

The system now **dynamically switches models during work** based on real-time task assessment:

### How It Decides

```
┌────────────────────────────────────────────────────────────────┐
│                    WHILE WORKING...                             │
│                                                                 │
│  Opus thinks: "This is a simple lookup task"                    │
│    → Auto-downgrades to Sonnet (cost savings)                  │
│                                                                 │
│  Sonnet thinks: "I'm stuck, multiple errors"                    │
│    → Auto-upgrades to Opus (need more capability)              │
│                                                                 │
│  Haiku thinks: "This code fix is complex"                       │
│    → Auto-upgrades to Sonnet (need more capability)            │
│                                                                 │
│  Sonnet thinks: "This is trivial, just reading files"           │
│    → Auto-downgrades to Haiku (cost savings)                   │
└────────────────────────────────────────────────────────────────┘
```

### Decision Matrix

| Current Model | Realization | Action |
|---------------|-------------|--------|
| **Opus** | Task is easy (simple lookup, basic question) | → Switch to Sonnet |
| **Opus** | Task is trivial (file read, status check) | → Switch to Haiku |
| **Sonnet** | 3+ consecutive errors | → Switch to Opus |
| **Sonnet** | Task is very hard (architecture, complex bug) | → Switch to Opus |
| **Sonnet** | Task is trivial | → Switch to Haiku |
| **Haiku** | Task has errors (needs more capability) | → Switch to Sonnet |
| **Haiku** | Task is complex (code analysis, planning) | → Switch to Sonnet |

### What Gets Monitored

The system tracks in real-time:

1. **Task Type** - Inferred from your prompt and tool usage
2. **Error Rate** - Consecutive failures trigger upgrade
3. **Tool Call Patterns** - Many calls for simple task = wrong model
4. **Task Outcome** - Success/failure informs difficulty assessment

## ✅ Implemented: Auto Context Compaction

Automatically runs `/compact` when:
- 50, 100, 150, 200, 300... tool calls
- 40+ calls since last compact
- 60 second cooldown (prevents rapid-fire)

## Files Created/Modified

| File | Purpose |
|------|---------|
| `scripts/hooks/dynamic-model-switcher.js` | Core switching logic |
| `scripts/hooks/track-task-outcome.js` | Tracks success/failure |
| `scripts/hooks/auto-compact-inject.js` | Auto-triggers /compact |
| `~/.claude/settings.json` | Updated with new hooks |

## No User Action Required

You don't need to:
- ❌ Type `/model` commands
- ❌ Type `/compact` commands
- ❌ Configure anything
- ❌ Monitor or adjust

**Just work naturally** - the system adapts automatically.

## How to Verify It's Working

### 1. Watch for log messages

```
[DynamicModel] Switch: SONNET → OPUS | 3 consecutive errors - need more capable model
[DynamicModel] Switch: OPUS → SONNET | Task is easier than expected - saving cost
[AutoCompact] Triggering /compact at 52 tool calls
```

### 2. Check current state

```bash
cat /tmp/claude-code/claude-session-state-*
```

Shows:
- Current model
- Task type
- Task difficulty
- Consecutive errors
- Tool calls for current task

### 3. Check model switches

```bash
cat /tmp/claude-code/claude-model-override
```

Shows:
- Which model was switched to
- Reason for switch
- Which model it switched from

## Example Scenarios

### Scenario 1: Complex Bug Fix
```
You: "Fix this build error"
  → Starts: Sonnet (default)
  → Error 1: Type mismatch
  → Error 2: Still failing after fix attempt
  → Error 3: Another related error
  → AUTO-SWITCH: Sonnet → Opus (3 consecutive errors)
  → Opus: Analyzes full context, finds root cause
  → Fix applied successfully
```

### Scenario 2: Architecture Review
```
You: "Review this architecture"
  → Starts: Opus (detected from "architecture" keyword)
  → Analysis: Task is straightforward review, not complex design
  → AUTO-SWITCH: Opus → Sonnet (task is easier than expected)
  → Sonnet: Provides thorough review
  → Cost savings: Used Sonnet instead of expensive Opus
```

### Scenario 3: Quick File Lookup
```
You: "Find all files using Metal"
  → Starts: Sonnet (default)
  → Analysis: Simple search task
  → AUTO-SWITCH: Sonnet → Haiku (trivial task)
  → Haiku: Quickly finds and lists files
  → Cost savings: Used cheapest model
```

## Customization (Optional)

### Change default starting model

```json
{
  "model": "claude-haiku-4-5-20251001"  // Start cheap
}
```

```json
{
  "model": "claude-opus-4-6"  // Start with most capable
}
```

### Adjust switching sensitivity

Edit `dynamic-model-switcher.js` - lower the error threshold:
```javascript
if (state.consecutiveErrors >= 2) {  // Was 3 - more sensitive
  // Upgrade to Opus
}
```

## Summary

| Capability | Status |
|------------|--------|
| Opus → downgrade when easy | ✅ Working |
| Sonnet → upgrade when hard | ✅ Working |
| Haiku → upgrade when complex | ✅ Working |
| Auto compact at thresholds | ✅ Working |
| Error-based escalation | ✅ Working |
| Cost optimization | ✅ Working |

**The system is now fully automated and self-adaptive.**
