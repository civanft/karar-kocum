# Security policy

## Reporting a vulnerability

Do not open a public issue for a suspected vulnerability. Use GitHub's private
security advisory form after this repository becomes public:

https://github.com/civanft/karar-kocum/security/advisories/new

Include the affected component, reproduction steps, impact, and any proposed
mitigation. Reports are reviewed on a best-effort basis.

## Secret handling

- The mobile Firebase configuration is public client metadata embedded in every
  released application. Its API keys are platform/API restricted; they are not
  server credentials.
- `OPENAI_API_KEY` is stored in Google Secret Manager and is accessible only to
  the dedicated `analyzeDecision` runtime service account. It must never be
  copied into Flutter, GitHub variables, a tracked `.env`, or documentation.
- Local `.env`, `.secret.local`, Android signing files, Apple certificates and
  service-account JSON files are Git-ignored. Only placeholder examples belong
  in Git.
- Production deployment uses managed service identities. Do not create a
  service-account JSON key.

Before publishing or opening a pull request, run:

```sh
python3 scripts/test_publication_guard.py
python3 scripts/check_publication.py
bash scripts/check_secrets.sh history
```

No automated review can guarantee the absence of future vulnerabilities. New
SDKs, external APIs, authentication providers, payments, or data exports require
a fresh threat-model review.
