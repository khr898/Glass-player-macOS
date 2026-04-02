# Claude Code Configuration Update

**Date:** 2026-03-31
**Purpose:** Enable automatic model switching and strategic context compaction

## What Was Configured

### 1. Automatic Model Switching

The system now analyzes your prompts and suggests the appropriate model:

| Model | Use For | Trigger Keywords |
|-------|---------|------------------|
| **Haiku** | Simple tasks | "read", "search", "show", "explain", "what is", "list" |
| **Sonnet** | Coding work | "implement", "fix", "update", "add", "refactor", "test" |
| **Opus** | Deep analysis | "plan", "architecture", "research", "security", "production" |

**Manual Override:** Use `/model haiku`, `/model sonnet`, or `/model opus` anytime.

### 2. Strategic Context Compaction

Instead of arbitrary auto-compact at 95%, the system:
- Suggests `/compact` every 30 tool calls (configurable)
- Auto-compacts at 70% context (instead of 95%)
- Lets you decide when based on workflow phase

**When to compact:**
- After exploration, before implementation
- Between major task phases
- When context feels stale

### 3. Files Modified

| File | Change |
|------|--------|
| `~/.claude/settings.json` | Added env vars, model switcher hook, compact check hook |
| `scripts/hooks/auto-model-switcher.js` | NEW - Analyzes prompts and suggests model |
| `scripts/hooks/check-compact-needed.js` | NEW - Suggests compact at strategic points |
| `docs/auto-compact-model-switching.md` | NEW - Full documentation |

### 4. Environment Variables

```json
{
  "COMPACT_THRESHOLD": "30",
  "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE": "70"
}
```

## How to Use

### Model Switching

```bash
# Automatic - system suggests based on your prompt
# Manual override:
/model haiku    # Quick tasks
/model sonnet   # Coding (default)
/model opus     # Deep thinking
```

### Context Compaction

```bash
# Manual compact when ready
/compact

# System will suggest at 30, 50, 75, 100+ tool calls
```

## Testing

To verify the configuration is working:

1. **Test model switcher:**
   ```bash
   # Ask a simple question - should suggest Haiku
   "What files match Sources/*.swift?"

   # Ask for planning - should suggest Opus
   "Plan the implementation of feature X"

   # Ask for coding - should suggest Sonnet
   "Add a new function to calculate X"
   ```

2. **Test compact suggestions:**
   - Work for ~30 tool calls
   - Watch for `[CheckCompact]` messages in stderr
   - Or wait for spinner suggestion

## Reverting Changes

To disable auto model switching:
```json
// Remove from PreToolUse hooks in settings.json:
{
  "matcher": "UserPromptSubmit",
  "hooks": [
    {
      "type": "command",
      "command": "node \"${CLAUDE_PLUGIN_ROOT}/scripts/hooks/auto-model-switcher.js\"",
      "timeout": 5,
      "async": true
    }
  ]
}
```

To disable compact suggestions:
```json
// Remove from PostToolUse hooks in settings.json:
{
  "matcher": "PostToolUse",
  "hooks": [
    {
      "type": "command",
      "command": "node \"${CLAUDE_PLUGIN_ROOT}/scripts/hooks/run-with-flags.js\" \"post:check-compact-needed\" \"scripts/hooks/check-compact-needed.js\" \"standard\"",
      "timeout": 5,
      "async": true
    }
  ]
}
```

To restore default auto-compact:
```json
// Remove or set to default:
"env": {
  "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE": "95"  // Default
}
```

## Next Steps

The configuration is complete. You can now:

1. Continue with the Anime4K production plan
2. Use `/model` to switch based on task complexity
3. Run `/compact` at logical breakpoints
4. Let the system suggest when to compact

**Recommended workflow:**
- Start with `/model opus` for planning sessions
- Switch to `/model sonnet` for implementation
- Use `/model haiku` for quick lookups
- Run `/compact` between major phases
