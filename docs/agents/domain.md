# Domain Docs

How the engineering skills should consume this repo's domain documentation when exploring the codebase.

This repo holds reusable GitHub Actions workflows. It does not use ADRs: don't look for `docs/adr/`, don't create ADRs, and don't suggest recording decisions as ADRs. Design rationale belongs in the workflow's `README.md` section, its input descriptions, or the PR description.

## Before exploring, read this

- **`GLOSSARY.md`** at the repo root.

If it doesn't exist, **proceed silently**. Don't flag its absence; don't suggest creating it upfront. The `/domain-modeling` skill creates it lazily when terms actually get resolved.

## Use the glossary's vocabulary

When your output names a domain concept (in an issue title, a refactor proposal, a hypothesis, a workflow input name), use the term as defined in `GLOSSARY.md`. Don't drift to synonyms the glossary explicitly avoids.

If the concept you need isn't in the glossary yet, that's a signal: either you're inventing language the project doesn't use (reconsider) or there's a real gap (note it for `/domain-modeling`).
