# Technical Design Document

## Metadata

| Field | Value |
|---|---|
| **Project** | Web Application |
| **Feature** | OAuth2 Social Login |
| **Author** | sdlc-architect |
| **Status** | draft |
| **Created** | 2026-04-21 |

## Problem Statement

Users currently authenticate with email and password only. This creates friction
during signup and increases support burden for password resets. We need to
support Google and GitHub as OAuth2 authentication providers to reduce signup
friction and leverage existing developer identities (our primary user base).

## Goals

1. Users can sign up and log in using Google or GitHub OAuth2
2. Existing email/password auth continues to work unchanged
3. OAuth-linked accounts are properly associated with existing users by email
4. Provider configuration is managed via environment variables only

## Non-Goals

- Support for additional providers (Twitter, Apple, etc.) — future work
- Migration of existing password users to OAuth-only — out of scope
- Admin UI for managing OAuth providers — use env vars

## Architecture Overview

```
┌──────────┐     ┌─────────────────┐     ┌──────────────┐
│  Browser  │────▶│  Express Server  │────▶│  PostgreSQL  │
└──────────┘     │                  │     └──────────────┘
                 │  /auth/:provider │────▶ users table
                 │  /auth/callback  │     oauth_accounts table
                 │                  │
                 │  session middleware│
                 └─────────────────┘
```

The OAuth flow follows the standard Authorization Code Grant:
1. User clicks provider button → redirect to provider
2. User authorizes → provider redirects to callback
3. Callback handler exchanges code for user info
4. System creates or links user account → creates session

New components:
- `AuthProvider` interface for provider implementations
- `GoogleProvider` and `GitHubProvider` concrete implementations
- New routes under `/auth/:provider` and `/auth/callback/:provider`
- New `oauth_accounts` table linking providers to users

## Data Model Changes

### New table: `oauth_accounts`

```sql
CREATE TABLE oauth_accounts (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  provider      VARCHAR(32) NOT NULL,  -- 'google' | 'github'
  provider_id   VARCHAR(255) NOT NULL,
  email         VARCHAR(255),
  display_name  VARCHAR(255),
  avatar_url    TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(provider, provider_id)
);
```

No changes to existing `users` table.

## API Surface Changes

### New routes

| Method | Path | Purpose |
|---|---|---|
| GET | `/auth/:provider` | Initiate OAuth flow, redirect to provider |
| GET | `/auth/callback/:provider` | Handle provider callback, create session |

### Modified routes

| Method | Path | Change |
|---|---|---|
| GET | `/login` | Add OAuth provider buttons to login page |

### Session

No changes to session structure. After OAuth login, `req.session.userId` is
set identically to password login.

## File Impact Map

| File | Action | Description |
|---|---|---|
| `src/auth/providers/types.ts` | create | AuthProvider interface |
| `src/auth/providers/google.ts` | create | Google OAuth implementation |
| `src/auth/providers/github.ts` | create | GitHub OAuth implementation |
| `src/auth/providers/index.ts` | create | Provider registry |
| `src/auth/routes.ts` | modify | Add OAuth routes |
| `src/auth/routes.ts` | modify | Add state parameter validation |
| `src/migrations/004_oauth_accounts.sql` | create | Database migration |
| `src/views/login.html` | modify | Add OAuth buttons |
| `src/config/index.ts` | modify | Add OAuth env var validation |
| `tests/auth/providers/` | create | Test files for providers |

## Risks & Mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| CSRF on OAuth callback | High | Use cryptographically random state parameter stored in session |
| Email collision between providers | Medium | Link by email with confirmation prompt in future iteration |
| Provider API changes | Low | Abstract behind provider interface, pin API versions |
| Token leakage in logs | High | Never log authorization codes or tokens |

## Open Questions

1. Should we prompt for confirmation when linking an OAuth account to an
   existing user by email, or auto-link?
2. Should the login page hide provider buttons when credentials are not
   configured, or show them as disabled?

## Approval

- [ ] Human has reviewed and approved this TDD
