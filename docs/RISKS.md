# RISK LOG — 10_BANDS

This risk log captures the current known risks and mitigation owners.

- ID: RISK-F1
  Title: No CI/CD pipeline
  Severity: Blocker
  Impact: High
  Owner: @DICKY1987 / Dev Lead
  Mitigation: Add `.github/workflows/quality.yml` (Phase 1). Require CI passing for merges.
  Status: Planned

- ID: RISK-F8
  Title: Hardcoded paths (C:\)
  Severity: Blocker
  Impact: High
  Owner: Security Lead
  Mitigation: Replace with per-user TEMP defaults; add validation to config loader (Phase 5).
  Status: Planned

- ID: RISK-F11
  Title: Unvalidated tool execution (RCE risk)
  Severity: Blocker
  Impact: High
  Owner: Dev Lead + Security
  Mitigation: Introduce tool whitelist, path validation, argument sanitization (Phase 2 & Phase 5).
  Status: Planned

- ID: RISK-F9
  Title: No secrets management
  Severity: Major
  Mitigation: Integrate SecretManagement (Phase 5).

Notes
- Add new risks as GitHub issues and reference phases/PRs where mitigations happen.
