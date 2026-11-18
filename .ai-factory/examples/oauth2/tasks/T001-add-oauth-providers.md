# T001: Add OAuth Provider Infrastructure

## Objective

Users can sign in with Google or GitHub; the app has a pluggable provider model
that OAuth routes can delegate to.

## Dependencies

None — this is the first task. Other tasks depend on this one.

| Depends On | Needed for |
|---|---|
| — | — |

## Acceptance Criteria

### Feature: AuthProvider Interface

#### Scenario: Provider exposes required interface
- Given a concrete AuthProvider implementation exists
- When the provider registry looks up a provider by name
- Then the provider has a `name` string property
- And the provider has a `getAuthUrl(state: string)` method that returns a URL string
- And the provider has a `handleCallback(code: string)` method that returns a Promise of AuthProviderUser

### Feature: Google OAuth Provider

#### Scenario: Generate Google OAuth authorization URL
- Given Google OAuth credentials are configured
- And a state parameter is provided as "random-state-123"
- When `getAuthUrl` is called
- Then the returned URL starts with "https://accounts.google.com/o/oauth2/v2/auth"
- And the URL contains the correct client_id query parameter
- And the URL contains "state=random-state-123"
- And the URL contains "response_type=code"
- And the URL contains the correct redirect_uri

#### Scenario: Handle Google OAuth callback successfully
- Given Google OAuth credentials are configured
- And the Google token endpoint returns a valid access token
- And the Google userinfo endpoint returns user data with id "google-123", email "user@example.com", name "Test User"
- When `handleCallback` is called with a valid authorization code
- Then the result contains an AuthProviderUser with provider "google"
- And the providerId is "google-123"
- And the email is "user@example.com"
- And the displayName is "Test User"

#### Scenario: Handle Google OAuth callback with error response
- Given Google OAuth credentials are configured
- And the Google token endpoint returns a 400 error
- When `handleCallback` is called with an authorization code
- Then an error is thrown with a descriptive message

#### Scenario: Google env vars are missing
- Given GOOGLE_CLIENT_ID is not set in environment variables
- When the provider module is loaded
- Then the Google provider is NOT registered in the provider registry
- And a warning is logged

### Feature: GitHub OAuth Provider

#### Scenario: Generate GitHub OAuth authorization URL
- Given GitHub OAuth credentials are configured
- And a state parameter is provided as "random-state-456"
- When `getAuthUrl` is called
- Then the returned URL starts with "https://github.com/login/oauth/authorize"
- And the URL contains the correct client_id query parameter
- And the URL contains "state=random-state-456"
- And the URL contains "redirect_uri" with the correct callback URL

#### Scenario: Handle GitHub OAuth callback successfully
- Given GitHub OAuth credentials are configured
- And the GitHub token endpoint returns a valid access token
- And the GitHub user API returns user data with id 12345, login "testuser", email "user@example.com"
- When `handleCallback` is called with a valid authorization code
- Then the result contains an AuthProviderUser with provider "github"
- And the providerId is "12345"
- And the email is "user@example.com"
- And the displayName is "testuser"

#### Scenario: GitHub env vars are missing
- Given GITHUB_CLIENT_ID is not set in environment variables
- When the provider module is loaded
- Then the GitHub provider is NOT registered in the provider registry
- And a warning is logged

### Feature: Provider Registry

#### Scenario: Get a configured provider
- Given Google and GitHub providers are registered
- When the registry is queried for "google"
- Then the Google provider instance is returned

#### Scenario: Get an unconfigured provider
- Given only the Google provider is registered
- When the registry is queried for "twitter"
- Then undefined is returned (not an error — routes handle missing providers)

#### Scenario: OAuth token exchange returns invalid JSON
- Given the provider token endpoint returns a non-JSON response
- When `handleCallback` is called
- Then an error is thrown with a descriptive message about invalid response

## Dev Notes

Auth module lives in `src/auth/`. Express + TypeScript, Vitest for tests.

**Existing types — `src/auth/types.ts`:**
```typescript
export interface User {
  id: string;
  email: string;
  displayName: string;
  avatarUrl?: string;
}

export interface AuthResult {
  user: User;
  isNewUser: boolean;
}
```

**Config — `src/config/index.ts`:** OAuth env vars will be added here (Zod schema).

**HTTP helper — `src/utils/http.ts`:** use existing `fetchJson` — no new runtime dependencies.

**Route pattern — `src/auth/routes.ts` (line 47):** follow existing handler style.

**Tests:** `tests/auth/` mirroring `src/auth/`, Vitest (`describe`, `it`, `expect`, `vi`).

**Constraints:**
- Provider secrets from environment variables only
- Backwards compatible with existing session-based auth
- TypeScript strict mode — no `any` types

## Test Mapping

<!-- Filled by the Coder during implementation -->

| Scenario | Test File | Test Name |
|---|---|---|

## Review & Verification

### Review
- Status: pending
- Reviewed by: —
- Report: —

### Verification
- Status: pending
- Verified by: —
- Report: —

## Status: draft
