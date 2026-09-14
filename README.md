# Life Manager — Agents API curl app

This runnable shell application starts an OpenAI Agents API session for the saved **Life Manager** agent and streams every SSE event, including output, errors, and tool-call events.

It uses the requested session overrides:

- Model: `gpt-5.6-luna`
- Instructions: `Официальный тон, пунктуальность, память, остроумие и критическое мышление.`
- Reasoning: low / auto summary
- Text: text format / low verbosity
- Environment: OpenAI-hosted

## Setup

Use `curl`, `jq`, and Bash. The project key is loaded from `OPENAI_API_KEY` or `.env.local`.

```bash
chmod +x run-life-manager.sh
```

## Run

```bash
./run-life-manager.sh "What should I focus on today?"
```

The command prints the raw Server-Sent Events stream as it arrives. Errors are returned by curl and turn failures/cancellations are identified in the status output.

The implementation follows the current [Agents API overview](https://developers.openai.com/api/docs/guides/agents-api/overview), [quickstart](https://developers.openai.com/api/docs/guides/agents-api/quickstart), and [session streaming guide](https://developers.openai.com/api/docs/guides/agents-api/sessions).
