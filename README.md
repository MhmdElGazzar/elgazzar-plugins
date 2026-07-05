# elgazzar-plugins — a Claude Code plugin marketplace

A small marketplace of [Claude Code](https://docs.claude.com/en/docs/claude-code) plugins.

## Add this marketplace

```
/plugin marketplace add MhmdElGazzar/elgazzar-plugins
```

Then browse and install:

```
/plugin                                        # interactive browser
/plugin install agentex@elgazzar-plugins
```

## Plugins

| Plugin | What it does |
|--------|--------------|
| [`agentex`](https://github.com/MhmdElGazzar/agentex) | **Agentic test execution.** Plans and runs your tests for you — human-in-the-loop or fully autonomous — capturing screenshot/log evidence and a consolidated defect report instead of hours of manual click-through. Drives a real browser via `playwright-cli` today; API, DB, and Azure targets coming soon. |

## Adding a plugin to this marketplace

Each plugin lives in its **own** repository. To list a new one, add an entry to
[`.claude-plugin/marketplace.json`](./.claude-plugin/marketplace.json):

```json
{
  "name": "my-plugin",
  "source": { "source": "github", "repo": "MhmdElGazzar/my-plugin" },
  "description": "…"
}
```

Sources can also be a local path (`"./plugins/my-plugin"`), a full git `url`, a monorepo
`git-subdir`, or an `npm` package — see the Claude Code plugin docs.

## Maintainer

Mohamed Elgazzar · mhmd.elgazzar.sqe@gmail.com
