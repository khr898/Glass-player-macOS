# Automated Model Switching & Context Compaction

**Status:** Partially Automated
**Date:** 2026-03-31

## What's Fully Automated

### ✅ Auto Context Compaction

The system **automatically runs `/compact`** when:
- Tool calls reach thresholds: 50, 100, 150, 200, 300...
- At least 40 tool calls since last compact
- 60 second cooldown between compacts (prevents rapid-fire)

**How it works:**
1. PostToolUse hook (`auto-compact-inject.js`) checks tool call count
2. When threshold is crossed, writes `/compact` to inject file
3. Claude reads and executes the command automatically

**No user action needed** - compact happens automatically in the background.

### ⚠️ Model Switching (Suggestion Only)

The system **analyzes your prompts** and **suggests** the appropriate model:

| Your Prompt | Suggested Model |
|-------------|-----------------|
| "plan", "architecture", "research", "security" | Opus |
| "implement", "fix", "refactor", "/tdd" | Sonnet |
| "read", "search", "list", "git status" | Haiku |

**Limitation:** Claude Code doesn't allow hooks to change the model mid-session automatically.

**Workaround:** Set a default model in settings.json:
```json
{
  "model": "claude-sonnet-4-6"  // Default for most tasks
}
```

For complex planning sessions, manually switch before starting:
```bash
/model opus
```

## Configuration Files

### `~/.claude/settings.json`

```json
{
  "env": {
    "CLAUDE_PLUGIN_ROOT": "/Users/user/.claude/plugins/cache/everything-claude-code/everything-claude-code/1.9.0",
    "COMPACT_THRESHOLD": "50",
    "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE": "70"
  },
  "hooks": {
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
    ]
  },
  "model": "claude-sonnet-4-6"
}
```

### Hook Files

| File | Purpose |
|------|---------|
| `scripts/hooks/auto-compact-inject.js` | Auto-triggers /compact at thresholds |
| `scripts/hooks/auto-model-switcher.js` | Analyzes prompts (logs suggestions) |
| `scripts/hooks/auto-execute.js` | Combined analyzer (logs suggestions) |

## Customization

### Change compact frequency

Edit `~/.claude/settings.json`:
```json
{
  "env": {
    "COMPACT_THRESHOLD": "30"  // Compact more frequently
  }
}
```

Thresholds are: 30, 80, 130, 180, 280... (first threshold + 50 intervals)

### Disable auto-compact

Remove or comment out the PostToolUse hook in settings.json:
```json
{
  "hooks": {
    "PostToolUse": [
      // Comment out or remove this:
      // {
      //   "matcher": "*",
      //   "hooks": [
      //     {
      //       "type": "command",
      //       "command": "node \"${CLAUDE_PLUGIN_ROOT}/scripts/hooks/auto-compact-inject.js\"",
      //       "timeout": 5,
      //       "async": true
      //     }
      //   ]
      // }
    ]
  }
}
```

### Change default model

```json
{
  "model": "claude-haiku-4-5-20251001"  // Cheaper, faster
}
```

Or for deep work:
```json
{
  "model": "claude-opus-4-6"  // Most capable, expensive
}
```

## Monitoring

### Check if auto-compact is working

```bash
# Check last compact time
cat /tmp/claude-code/claude-last-compact-*

# Check tool call count
cat /tmp/claude-code/claude-tool-count-*

# Check for compact trigger
cat /tmp/claude-code/claude-inject-input
```

### Watch for log messages

Auto-compact logs to stderr:
```
[AutoCompact] Triggering /compact at 52 tool calls (52 since last)
```

## Troubleshooting

### Compact not triggering

1. Check hook is in settings.json
2. Verify script exists: `ls -la scripts/hooks/auto-compact-inject.js`
3. Check tool count file: `cat /tmp/claude-code/claude-tool-count-*`

### Compact happening too often

Increase threshold in settings.json:
```json
{
  "env": {
    "COMPACT_THRESHOLD": "100"  // Only compact at 100, 150, 200...
  }
}
```

### Model not appropriate for task

Manually switch before starting complex work:
```bash
/model opus    # For planning, architecture, security review
/model sonnet  # For coding, refactoring, bug fixes (default)
/model haiku   # For quick lookups, file searches
```

## Summary

| Feature | Status | User Action Required |
|---------|--------|---------------------|
| Auto Compact | ✅ Fully Automated | None |
| Model Switching | ⚠️ Suggestion Only | Set default model, manually switch for special cases |

**Recommended workflow:**
1. Set `"model": "claude-sonnet-4-6"` as your default (good for 80% of tasks)
2. Let auto-compact handle context management
3. Manually switch to Opus before planning sessions (`/model opus`)
4. Manually switch to Haiku for extended exploration (`/model haiku`)
