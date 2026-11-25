# btw

`/btw <question>` — a quick side question to a fresh subagent, seeded with the
recent conversation. Like Claude Code's `/btw`: ask an aside without touching
the session you are in.

## How it works

Built on the [nodecode-subagents](https://github.com/nodecode-ai/cells) cell.
Each `/btw`:

1. reads the last `btw.context_messages` user/assistant messages of this
   session from the kernel event log (clipped to ~11k characters, newest kept),
2. opens a one-worker detached team via `subagents:task` with that transcript
   tail as shared context and the question as the assignment,
3. waits for the worker (up to `btw.timeout` seconds),
4. shows the worker's answer inline. This session's transcript is untouched.

The worker is told to answer directly: no file edits, no new agents, no board
posts. Every run is a normal subagent team, visible to `/agents list`.

## Usage

```
/btw what was the name of that function we renamed earlier?
/btw why does SBCL package-lock error on intern?
```

The command blocks until the answer lands or the timeout passes; on timeout
it reports the worker's status instead.

## Settings (/settings)

| setting | default | meaning |
|---|---|---|
| `btw.timeout` | 120 | seconds to wait for the side answer (max 300) |
| `btw.context_messages` | 10 | recent parent messages given as context (2–50) |

## Requires

The `nodecode-subagents` cell (and its `nodecode-board` dependency) installed
and running. `/btw` workers use the configured auxiliary model; if none is
configured, they use the parent session's model at its weakest reasoning effort.
Other subagent workers are unaffected.

## License

MIT
