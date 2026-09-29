# ORCID authentication boundary

The official [ORCID tutorial](https://info.orcid.org/documentation/api-tutorials/api-tutorial-get-and-authenticated-orcid-id/) documents authorization code exchange using client ID + secret. We did not find a documented public-client PKCE flow sufficient to ship a secretless native integration. Do not assume adding PKCE parameters makes such a flow supported.

A shared developer secret must not appear in a repository, binary or bundled configuration. AcaTerminal v0.1 therefore exposes a **personal developer-client flow**, not production-ready one-click ORCID sign-in:

1. The developer registers a Public API client and exact HTTPS redirect URI through ORCID.
2. In the developer setup sheet, enter that client ID, personal client secret and registered redirect. This is not the ORCID account password.
3. The secret goes into Keychain, and the official ORCID authorize page opens in the system browser with `/authenticate` and a fresh state.
4. After authorization, paste the complete callback URL into the secure callback field. For a registered `https://localhost/` redirect without a server, the browser may show an unavailable page; copy the URL without bypassing certificate warnings. Use a redirect under your own control.
5. AcaTerminal validates the exact scheme, host, port and path, unique state/code values and ten-minute lifetime; then exchanges the code at ORCID over HTTPS. OAuth errors are rejected. The UI consumes the pending flow once before exchange.
6. The resulting access token is stored only in Keychain. Only a successful token exchange produces `authenticated = true`.

Public profile preview takes an ORCID iD and queries the corresponding OpenAlex author. It does not authenticate ORCID ownership and never displays “connected” for that action. Refresh preserves an authenticated identity only when the ORCID exactly matches.

Disconnect removes the local token and clears the authentication flag; it does not revoke the upstream ORCID authorization or delete cached research. Users can revoke access in ORCID account settings. The personal developer secret has a separate removal action.

## Before a public release

Obtain an appropriate application registration and a supported callback/deployment design with ORCID. Replace manual callback entry with a platform adapter using system browser authentication and a registered callback. If a confidential exchange service is necessary, keep it limited to OAuth; never upload the research database, and document consent and token handling. Alternatively implement a public-client flow only when ORCID officially supports it. Do not package a shared secret or promote the personal developer flow as consumer-ready authentication.

Authorization token expiry/revocation/refresh and a sandbox integration test with a registered client remain release gates. This machine had no registered ORCID test client or real credentials; only synthetic exchange/callback tests were run.
