# Provider compatibility research

Research snapshot: 2026-08-23.

This document distinguishes a currently observable vendor-client implementation from a provider-supported third-party API. Endpoint and OAuth constants below are compatibility facts, not a promise that QuotaGlance is authorized for App Store distribution or that the endpoints will remain available.

## Codex

### Current vendor-client path

The OpenAI Codex repository was inspected at commit `83d1fe0e67b1323f71febc2925817732b449f1d9` (2026-08-23).

- Authorization endpoint: `https://auth.openai.com/oauth/authorize`
- Token and refresh endpoint: `https://auth.openai.com/oauth/token`
- Public-client identifier used by Codex: `app_EMoamEEZ73f0CkXaXp7hrann`
- Flow: authorization code + PKCE S256 + state
- Registered CLI loopback redirects observed in source: `http://localhost:1455/auth/callback`, with `1457` as the allow-listed fallback
- Scopes used by current Codex: `openid profile email offline_access api.connectors.read api.connectors.invoke`
- Usage endpoint for ChatGPT auth: `GET https://chatgpt.com/backend-api/wham/usage`
- Headers: bearer access token and `ChatGPT-Account-Id`; the account ID comes from the ID-token claim and is stored with the credential in Keychain
- Refresh body: JSON containing `client_id`, `grant_type=refresh_token`, and `refresh_token`
- Usage schema: `rate_limit.primary_window` and `rate_limit.secondary_window`, each containing `used_percent`, `limit_window_seconds`, and epoch `reset_at`

Primary source pointers:

- [Codex OAuth login server](https://github.com/openai/codex/blob/83d1fe0e67b1323f71febc2925817732b449f1d9/codex-rs/login/src/server.rs)
- [Codex credential refresh and client ID](https://github.com/openai/codex/blob/83d1fe0e67b1323f71febc2925817732b449f1d9/codex-rs/login/src/auth/manager.rs)
- [Codex usage endpoint selection](https://github.com/openai/codex/blob/83d1fe0e67b1323f71febc2925817732b449f1d9/codex-rs/backend-client/src/client/rate_limit_resets.rs)
- [Codex generated usage response models](https://github.com/openai/codex/tree/83d1fe0e67b1323f71febc2925817732b449f1d9/codex-rs/codex-backend-openapi-models/src/models)
- [Codex app-server account/rateLimits contract](https://github.com/openai/codex/blob/83d1fe0e67b1323f71febc2925817732b449f1d9/codex-rs/app-server/README.md)

### Live, credential-safe observation

The locally installed `codex-cli 0.149.0-alpha.4.1` app-server was initialized as `quotaglance_research`, then queried with `account/rateLimits/read`. The response was obtained through the RPC so no token was read or printed. It returned a Codex rate-limit window with `usedPercent = 36`, `windowDurationMins = 10080`, and `secondary = null` for the signed-in account at that moment.

This proves three mapping rules used in `QuotaGlanceCore`:

1. `usedPercent` is not remaining; the corresponding displayed value is 64% remaining.
2. Window position is not enough to identify 5h versus weekly; duration must be inspected.
3. A missing 5h or weekly window must remain `nil`, not be synthesized as 0%.

It does **not** prove that the iOS loopback login is allow-listed or that a third-party App Store binary may reuse the Codex public client.

## Claude Code

### Current vendor-client path

Anthropic's public `anthropics/claude-code` repository does not publish the core client implementation. The official npm distribution `@anthropic-ai/claude-code@2.1.241` and its `win32-x64` native package were inspected. The native distribution contains its JavaScript protocol implementation and reports build SHA `c87e2742fc9ad269ec8920460d00a091b1e410f0`.

- Claude subscription authorization endpoint in 2.1.241: `https://claude.com/cai/oauth/authorize`
- Token and refresh endpoint: `https://platform.claude.com/v1/oauth/token`
- Claude Code public-client identifier: `9d1c250a-e61b-44d9-88ed-5944d1962f5e`
- Flow: authorization code + PKCE S256 + state
- Redirect: dynamic `http://localhost:{port}/callback`; current Claude Code also exposes a manual redirect at `https://platform.claude.com/oauth/code/callback`
- Normal Claude Code scopes are much broader. QuotaGlance limits its request to `user:profile user:inference`: `user:profile` is required by the usage endpoint, and current Claude subscription authentication is selected through the inference-capable Claude.ai OAuth path. No inference request is sent by QuotaGlance.
- Usage endpoint: `GET https://api.anthropic.com/api/oauth/usage`
- Usage headers: bearer access token and `anthropic-beta: oauth-2025-04-20`
- Current response families: `five_hour`, `seven_day`, optional model-specific windows, and a newer optional `limits` array
- Direct window schema: `utilization` is used percentage on a 0–100 scale; `resets_at` is ISO-8601
- Newer array schema: `kind`, `group`, `percent`, and `resets_at`; QuotaGlance maps `session` and `weekly_all`

Primary/provider-controlled pointers:

- [Official Claude Code npm package](https://www.npmjs.com/package/@anthropic-ai/claude-code)
- [Official Claude Code repository](https://github.com/anthropics/claude-code)
- [Anthropic report showing that `/usage` requires `user:profile`](https://github.com/anthropics/claude-code/issues/16749)
- [Anthropic report documenting `/api/oauth/usage` 429 behavior](https://github.com/anthropics/claude-code/issues/30930)
- [Anthropic guidance for third-party developer authentication](https://support.claude.com/en/articles/13189465-log-in-to-your-claude-account)

No Claude credential was available in the Windows environment, so no real Claude OAuth or HTTP response was claimed. The sanitized fixture follows the current official binary's embedded response validator and field names; it is not presented as a captured QuotaGlance login.

## Compatibility and distribution risks

| Risk | Consequence | Current mitigation |
| --- | --- | --- |
| OAuth clients belong to vendor applications | Redirect or consent can be rejected; reuse may be disallowed | Honest `QuotaGlance` user-agent/originator, prominent documentation, no claim of official support |
| Usage endpoints are undocumented for third parties | Schema, headers, or availability can change without notice | Strict decoders; schema errors never become 0%; last good cache is preserved |
| Claude usage endpoint may return 429 | Aggressive polling can make usage unavailable | Five-minute app freshness window, 15-minute widget timelines, no complication networking |
| iOS loopback callback is unverified | ASWebAuthenticationSession or provider redirect rules may block login | Fixed Codex allow-listed ports and dynamic Claude port; explicit real-device gate before release |
| Anthropic recommends API keys for products built for others | Subscription OAuth distribution may conflict with provider policy | Treat this repository as a technical PoC until written provider approval or a supported OAuth registration path exists |
| Provider tokens can rotate or be revoked early | Refresh can fail before local expiry | Retry once after 401; terminal auth errors preserve cached data and ask the user to reconnect |

## Release gate

QuotaGlance must not be described as meeting its end-to-end goal until all of the following are observed on Apple hardware or simulators as applicable:

- Codex OAuth completes inside the iPhone app and the usage response decodes.
- Claude OAuth completes inside the iPhone app and the usage response decodes.
- Provider approval/terms permit the chosen public-client usage for the intended distribution.
- iPhone, Watch, iPhone widget, and all three complication families build and render.
- A paired Watch receives a snapshot without any credential fields.
- Token refresh and disconnect behavior are tested for both providers.
