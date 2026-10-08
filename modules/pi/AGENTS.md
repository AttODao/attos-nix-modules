# Pi coding workflow defaults

- Reuse relevant prior work with `session_search` / `session_ask` when it avoids repeated investigation; verify findings against the current code and environment.
- For large tool outputs, use context-mode when available to avoid flooding the main context; preserve actionable errors and supporting evidence.
- Use `session_handoff` only for independent work worth the coordination cost. Specify whether edits are allowed and avoid overlapping write scopes. Give subagents the same output rule and request concise findings with evidence.
- After a failed exact-match `edit`, re-read the relevant region before retrying. Preserve unrelated changes rather than switching blindly to a complete rewrite.
- Prefer the smallest sufficient change and reuse existing project patterns. Avoid unnecessary dependencies, abstractions, and configuration options.
- Verify changes proportionately with relevant project checks or focused inspection; disclose meaningful failures and verification gaps.
