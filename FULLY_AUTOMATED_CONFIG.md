# Fully Automated Model Switching & Context Compaction

**Status:** ✅ Fully Automated - Zero User Interaction Required
**Date:** 2026-03-31

## How It Works

### 🧠 Dynamic Model Switching (Self-Adaptive)

The system **monitors task complexity in real-time** and automatically switches models:

```
┌─────────────────────────────────────────────────────────────────┐
│  Task Starts (default: Sonnet)                                  │
│          ↓                                                       │
│  Dynamic Model Switcher analyzes:                               │
│  - Task type (planning, coding, lookup)                         │
│  - Error rate (consecutive failures)                            │
│  - Tool call patterns                                           │
│  - Self-reported difficulty                                     │
│          ↓                                                       │
│  Decision Matrix:                                                │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │ Current Model │ Condition              │ Action          │    │
│  ├───────────────┼────────────────────────┼─────────────────┤    │
│  │ Opus          │ Task is easy           │ → Downgrade     │    │
│  │ Opus          │ 3+ errors              │ → Stay (debug)  │    │
│  │ Sonnet        │ Task is very hard      │ → Upgrade Opus  │    │
│  │ Sonnet        │ 3+ consecutive errors  │ → Upgrade Opus  │    │
│  │ Sonnet        │ Task is trivial        │ → Downgrade     │    │
│  │ Haiku         │ Task is complex        │ → Upgrade       │    │
│  │ Haiku         │ 2+ errors              │ → Upgrade       │    │
│  └─────────────────────────────────────────────────────────┘    │
│          ↓                                                       │
│  Model switched automatically - no user action needed           │
└─────────────────────────────────────────────────────────────────┘
```

### Switching Triggers

| Current Model | Trigger Condition | New Model | Reason |
|---------------|-------------------|-----------|--------|
| Opus | Task difficulty = 'easy' | Sonnet | Saving cost |
| Opus | Task type = 'simple' | Haiku | Overkill |
| Sonnet | 3+ consecutive errors | Opus | Need more capability |
| Sonnet | Task difficulty = 'very_hard' | Opus | Deep analysis needed |
| Sonnet | Task type = 'trivial' | Haiku | Cost optimization |
| Haiku | 2+ errors | Sonnet | Task too complex |
| Haiku | Task difficulty = 'hard' | Sonnet | Need more capability |
| Haiku | Task type = 'planning' | Opus | Strategic work |

### 🔄 Auto Context Compaction

Automatically runs `/compact` when:
- Tool calls reach thresholds: 50, 100, 150, 200, 300...
- At least 40 tool calls since last compact
- 60 second cooldown between compacts

## Configuration

### `~/.claude/settings.json`

```json
{
  "env": {
    "CLAUDE_PLUGIN_ROOT": "/Users/user/.claude/plugins/cache/everything-claude-code/everything-claude-code/1.9.0",
    "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE": "70"
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "UserPromptSubmit",
        "hooks": [
          {
            "type": "command",
            "command": "node \"${CLAUDE_PLUGIN_ROOT}/scripts/hooks/dynamic-model-switcher.js\"",
            "timeout": 5,
            "async": true
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "node \"${CLAUDE_PLUGIN_ROOT}/scripts/hooks/auto-compact-inject.js\"",
            "timeout": 5,
            "async": true
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
  },
  "model": "claude-sonnet-4-6"
}
```

## Hook Files

| File | Purpose | Trigger |
|------|---------|---------|
| `dynamic-model-switcher.js` | Analyzes task and switches model | PreToolUse (UserPromptSubmit) |
| `track-task-outcome.js` | Tracks success/failure for learning | PostToolUseFailure |
| `auto-compact-inject.js` | Auto-triggers /compact | PostToolUse |

## State Files

| File | Purpose |
|------|---------|
| `/tmp/claude-code/claude-session-state-{id}` | Current model, task type, difficulty |
| `/tmp/claude-code/claude-model-override` | Model switch decision |
| `/tmp/claude-code/claude-error-log-{id}` | Recent errors for analysis |
| `/tmp/claude-code/claude-outcomes-{id}.jsonl` | All tool outcomes |

## Monitoring

### Check current model state

```bash
cat /tmp/claude-code/claude-session-state-*
```

Example output:
```json
{
  "currentModel": "sonnet",
  "taskType": "coding",
  "taskDifficulty": "medium",
  "consecutiveErrors": 0,
  "toolCallsForTask": 12,
  "lastSwitchReason": null
}
```

### Check model switches

```bash
cat /tmp/claude-code/claude-model-override
```

Example output:
```json
{
  "model": "opus",
  "modelId": "claude-opus-4-6",
  "timestamp": 1743456789000,
  "autoSwitched": true,
  "reason": "3 consecutive errors - need more capable model",
  "from": "sonnet"
}
```

### Watch log messages

Model switches are logged to stderr:
```
[DynamicModel] Switch: SONNET → OPUS | 3 consecutive errors - need more capable model
[DynamicModel] Switch: OPUS → SONNET | Task is easier than expected - saving cost
[AutoCompact] Triggering /compact at 52 tool calls (52 since last)
```

## Example Scenarios

### Scenario 1: Bug Fix Escalation
```
User: "Fix this build error"
  → Starts with: Haiku (simple fix expected)
  → Error: Can't resolve type issue
  → Auto-switch to: Sonnet
  → Error: Still failing, complex type inference
  → Auto-switch to: Opus
  → Opus: Analyzes full context, fixes issue
  → Result: Issue resolved, model stays Opus for follow-up
```

### Scenario 2: Planning Session
```
User: "Plan the architecture for a new feature"
  → Starts with: Sonnet (default)
  → Analysis: Task type = 'planning', difficulty = 'hard'
  → Auto-switch to: Opus
  → Opus: Creates comprehensive architecture plan
  → User: "Now implement it"
  → Analysis: Task type = 'coding', difficulty = 'medium'
  → Auto-switch to: Sonnet
  → Sonnet: Implements the plan
```

### Scenario 3: File Search
```
User: "Find all Swift files that import Metal"
  → Starts with: Sonnet (default)
  → Analysis: Task type = 'search', difficulty = 'easy'
  → Auto-switch to: Haiku
  → Haiku: Quickly finds files
  → User: "Show me the content"
  → Haiku: Displays content
  → Result: Cost-optimized for simple lookup
```

## Customization

### Change default model

```json
{
  "model": "claude-haiku-4-5-20251001"  // Start cheap, upgrade if needed
}
```

Or for complex work:
```json
{
  "model": "claude-opus-4-6"  // Start smart, downgrade if easy
}
```

### Adjust switching sensitivity

Edit `dynamic-model-switcher.js`:

```javascript
// Lower threshold for upgrade (more sensitive)
if (state.consecutiveErrors >= 2) {  // Was 3
  decisions.push({ action: 'upgrade', to: 'opus' });
}

// Higher threshold for downgrade (less aggressive cost cutting)
if (state.currentModel === 'opus' && state.taskDifficulty === 'very_easy') {
  decisions.push({ action: 'downgrade', to: 'sonnet' });
}
```

### Disable auto-compact

Remove the PostToolUse hook from settings.json.

## Troubleshooting

### Model not switching

1. Check hook is registered:
   ```bash
   grep -A5 "dynamic-model-switcher" ~/.claude/settings.json
   ```

2. Check state file exists:
   ```bash
   cat /tmp/claude-code/claude-session-state-*
   ```

3. Check for errors in hook:
   ```bash
   ls -la /tmp/claude-code/claude-error-log-*
   ```

### Switching too aggressively

Increase error threshold in `dynamic-model-switcher.js`:
```javascript
if (state.consecutiveErrors >= 5) {  // Was 3
  // Upgrade to Opus
}
```

### Not switching when needed

Add more aggressive rules:
```javascript
// Add to decision logic in dynamic-model-switcher.js
if (state.toolCallsForTask > 30 && !taskComplete) {
  decisions.push({
    action: 'upgrade',
    to: 'opus',
    reason: 'Task taking too long - need more capability'
  });
}
```

## Summary

| Feature | Status | User Action |
|---------|--------|-------------|
| Model Switching | ✅ Self-Adaptive | None - automatic |
| Context Compaction | ✅ Automated | None - automatic |
| Error Tracking | ✅ Active | None - automatic |
| Cost Optimization | ✅ Downgrades when easy | None - automatic |
| Capability Escalation | ✅ Upgrades when hard | None - automatic |

**Just work naturally** - the system adapts to your tasks automatically.
