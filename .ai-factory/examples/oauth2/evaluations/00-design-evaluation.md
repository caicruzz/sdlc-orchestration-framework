# TDD Evaluation Report

## Metadata

| Field | Value |
|---|---|
| **TDD** | `.sdlc/examples/oauth2/00-tdd.md` |
| **Evaluator** | sdlc-evaluator |
| **Date** | 2026-04-21 |
| **Verdict** | needs-revision |

## Alignment Check

The core goal is clear: add Google and GitHub OAuth2 login to an existing
Express + TypeScript web application that currently uses email/password auth.
The TDD aims to reduce signup friction and password-reset support burden by
leveraging existing social identities.

Alignment is above 90%. The business goal, success metrics, and constraints are
well-defined. Proceeding with full evaluation.

## Executive Summary

The TDD proposes adding OAuth2 Authorization Code Grant flow for Google and
GitHub. It introduces a new `oauth_accounts` table, an `AuthProvider` interface
with concrete implementations for each provider, new Express routes for
initiating and handling OAuth callbacks, and modifications to the login view.
Session handling remains unchanged — the existing `req.session.userId` pattern
is reused.

## Critical Vulnerabilities & Blind Spots

### CSRF Protection on OAuth Callback Is Underspecified

- **Severity**: critical
- **Origin**: File Impact Map, routes
- **Description**: The TDD mentions "cryptographically random state parameter
  stored in session" in the Risks table but provides no architectural detail
  on HOW the state parameter is generated, stored, validated, or expired. This
  is the primary defense against CSRF in the OAuth flow.
- **Impact**: Without explicit state parameter handling in the architecture,
  the implementation may store it insecurely, skip validation, or fail to
  expire stale states — all of which enable CSRF attacks.

### Email Collision Handling Is Deferred Without a Default

- **Severity**: high
- **Origin**: Open Questions #1, Data Model
- **Description**: The TDD lists "Should we auto-link by email?" as an open
  question but does not define a default behavior. Meanwhile, the `oauth_accounts`
  table design assumes a link exists (it has a `user_id` FK). If a Google and
  a GitHub account share the same email, and no linking strategy is defined,
  the implementation will either silently create duplicate users or fail.
- **Impact**: Account takeover or user confusion if auto-linking is wrong.
  Data integrity issues if the FK constraint causes failures.

### No Token Revocation or Account Unlinking Strategy

- **Severity**: medium
- **Origin**: Missing from Architecture Overview and Data Model
- **Description**: The `oauth_accounts` table stores provider metadata but
  there is no mechanism described for a user to unlink an OAuth provider,
  revoke tokens, or handle a provider-reported deauthorization callback.
- **Impact**: Users who want to remove a linked provider have no path. Provider
  deauthorization callbacks (Google sends these) will go unhandled.

### Provider Configuration Validation Timing Is Ambiguous

- **Severity**: medium
- **Origin**: Architecture Overview, config changes
- **Description**: The TDD says "Provider configuration is managed via
  environment variables only" but does not specify WHEN validation occurs.
  The existing config uses Zod parsing at module load time. Adding optional
  OAuth env vars to the Zod schema means the app either crashes on missing
  vars (breaking existing installs) or marks them optional (no startup
  validation).
- **Impact**: Either a breaking change for existing deployments or silently
  misconfigured providers that fail at runtime when users click the login button.

### Login View Changes Are Not Specified

- **Severity**: medium
- **Origin**: File Impact Map — `src/views/login.html`
- **Description**: The only mention is "Add OAuth buttons to login page." No
  UX is described: button placement, loading states, error display after a
  failed callback, or accessibility requirements.
- **Impact**: Implementation will make ad-hoc UX decisions without design
  review, likely resulting in a poor or inconsistent login experience.

## Trade-off Analysis

| Decision | What You Gain | What You Sacrifice |
|---|---|---|
| Reuse existing session mechanism | Simplicity, no session layer changes | Cannot differentiate OAuth sessions from password sessions in logging/metrics |
| Authorization Code Grant (server-side) | Secure — tokens never exposed to browser | Requires server-side state management, more complex than implicit flow |
| Single `oauth_accounts` table with FK to `users` | Simple joins, referential integrity | Tight coupling — removing auth system requires data migration |
| No new runtime dependencies | Smaller attack surface, no supply chain risk | Must implement OAuth2 flow manually — more code to maintain and audit |
| Auto-linking by email (implied but undecided) | Seamless user experience | Account takeover risk if email provider is compromised |

## Alternative Approaches

### For: CSRF state parameter underspecification

Instead of leaving state parameter handling to implementation, define it
explicitly in the architecture:
- Generate a 256-bit cryptographically random token
- Store in session as `oauth_state.<provider>` with a 10-minute TTL
- Validate on callback: constant-time comparison, delete after use
- Reject callbacks with missing, mismatched, or expired states with HTTP 403

### For: Email collision handling

Instead of deferring the decision, adopt the safest default: **do not auto-link**.
If an OAuth provider returns an email that matches an existing user:
- Create the new `oauth_accounts` row with a NULL `user_id`
- Present an interstitial page asking the user to confirm the link
- If confirmed, set the `user_id` FK
- This makes `user_id` nullable in the schema, which affects the data model

### For: Token revocation and account unlinking

Add a `DELETE /auth/providers/:provider` route that removes the
`oauth_accounts` row and optionally calls the provider's token revocation
endpoint. This is a separate task from the initial OAuth implementation but
should be acknowledged in the TDD's scope as a follow-up.

## Hard Questions

1. **What is the exact user experience when an OAuth provider returns an email
   that already belongs to an existing user?** Walk through the happy path AND
   the edge case where the user denies the linking prompt.

2. **What happens if both `GOOGLE_CLIENT_ID` and `GITHUB_CLIENT_ID` are
   missing from the environment?** Does the app still boot? Does the login page
   render with no OAuth buttons? Or does it crash?

3. **What is the state parameter TTL and storage strategy?** Sessions can be
   in-memory, Redis, or database-backed. The TTL and storage choice affects
   the security model. Which session store is this project using?

4. **How will you handle the OAuth callback when the user's session has
   expired between clicking "Sign in with Google" and returning from the
   consent screen?** The state parameter is in the old session, but the
   callback arrives on a new session.

5. **What is the migration strategy for the `oauth_accounts` table?** Is this
   a reversible migration? What happens on rollback if users have already
   linked accounts?

## Verdict

**Verdict**: needs-revision

**Reasoning**: The TDD has a sound architectural direction but contains one
critical gap (CSRF state parameter underspecification) and one high-severity
unresolved decision (email collision handling) that will cause implementation
ambiguity. These must be resolved before the Planner can decompose into
well-scoped tasks. The other medium-severity items can be addressed during
implementation if acknowledged in the TDD.

**Required revisions**:
1. Add explicit state parameter lifecycle to the Architecture Overview
2. Resolve the email collision strategy and update the Data Model accordingly
3. Specify provider configuration validation behavior at startup
4. Add a Non-Goals entry for account unlinking (to be addressed in a future TDD)
