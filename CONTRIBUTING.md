# Contributing

Start with a research workflow, not a list of integrations. Discuss domain/schema changes and new dependencies in an issue before implementation.

1. Keep domain models and connectors independent of the macOS UI.
2. Build with `./scripts/build.sh --check`; use `./scripts/package.sh` for the native app.
3. Use a disposable `ACATERMINAL_DATA_DIR` for UI tests. Never change a personal Zotero profile or research database in an automated test.
4. Test meaningful failures: ambiguous identifiers, raw journal text, partial/paginated imports, throttling, offline access, migrations and credential boundaries.
5. Run the new workflow in light and dark mode. Preserve keyboard interaction and native controls. Do not introduce dashboard cards, AI chat or browser-login scraping into v0.1.
6. Document APIs, scopes, limits and compatibility in the connector guide. New integrations default to read-only and explicit user action.
7. Do not commit credentials, tokens, cookies, private fixtures, `.env` files, SQLite databases or bundled builds. Redact service errors; do not log requests or token responses.
8. Independently implement from official documentation. Before using third-party code, check its license, record provenance and compatibility, and obtain a review. A public GitHub repository without a license is not a reusable code source. Do not copy branding/UI/assets.

The project uses GNU GPL version 3 (`GPL-3.0-only`). Contributions should be original work you can license under these terms. Runtime dependencies currently consist entirely of Apple SDK frameworks and system SQLite; see `docs/DEPENDENCIES.md`.

Pull requests should state the concrete workflow change, behavior before/after, validation and known limits. Schema changes need a versioned migration and fixtures for old data; never “fix” load errors by deleting the database.
