# 🔐 Security Policy

HexStrike AI is offensive-security tooling: by design it runs real security tools and, when explicitly enabled, arbitrary commands. This document covers how to report vulnerabilities in HexStrike itself, and how this fork is hardened so it can be run safely.

## Reporting a Vulnerability

Please report privately — do **not** open a public issue for an unfixed vulnerability.

- **Preferred:** GitHub private vulnerability reporting on this repository (**Security → Report a vulnerability**). This opens a private advisory only the maintainers can see.
- **Email (optional):** set a security contact for your fork here (e.g. `security@yourdomain`) and replace this line before publishing.

Include:

- A clear description of the issue.
- Exact steps/commands to reproduce.
- Impact and risk assessment.
- Any suggested mitigation or fix.

Reports are acknowledged within **72 hours** where possible, with a remediation timeline to follow.

### Please do not

- Publicly disclose an unfixed vulnerability.
- Test against systems you do not own or are not authorized to test.

---

## Threat model (read this first)

HexStrike is **not** a hardened multi-tenant service. It is single-operator tooling that executes security tools against targets you are authorized to test. The Flask API has no user model; access control is a single shared token plus network placement. Treat any host running it as sensitive:

- Anyone who can reach the API **and** holds the token can drive every tool.
- With the raw-exec endpoints enabled, that includes arbitrary command/code execution as the server's user.
- An AI agent driving the API can be steered by injected instructions in content it scrapes; scope enforcement and the raw-exec opt-in exist to contain that.

Run it bound to loopback (or behind an authenticating reverse proxy), one container per engagement, with a scope file set.

---

## Security controls in this fork

| Control | Default | How |
|---|---|---|
| API authentication | **required** | Server refuses to start without `HEXSTRIKE_API_TOKEN`; every request must send `X-HexStrike-Token` (constant-time compare). |
| Network bind | **loopback** | Defaults to `127.0.0.1`; warns loudly if bound to `0.0.0.0`. |
| Command-injection defense | on | Client-supplied values are `shlex`-quoted; `additional_args` is tokenized and quoted across `/api/tools/*`. |
| File-sandbox containment | on | `/api/files/*` operations are confined to the sandbox directory; `../` and absolute paths are rejected. |
| Raw command/code exec | **off** | `/api/command` and `/api/python/execute` return `403` unless `HEXSTRIKE_ALLOW_RAW_EXEC=1`. |
| Engagement scope | opt-in | Set `HEXSTRIKE_SCOPE_FILE` to restrict targets to authorized domains/CIDRs. |
| Audit log | opt-in | Set `HEXSTRIKE_AUDIT_LOG` to record actions to a JSONL file. |
| Container isolation | recommended | Lean non-root single container, or the full compose stack — see the Docker section of the README. |

### Environment variables that matter

- `HEXSTRIKE_API_TOKEN` — **required.** The shared auth token; use a long random value and set the same value as `X-HexStrike-Token` in your MCP client.
- `HEXSTRIKE_ALLOW_RAW_EXEC` — set to `1` only if you specifically need `/api/command` / `/api/python/execute`.
- `HEXSTRIKE_SCOPE_FILE` — path to a JSON scope file; keeps tools within authorization.
- `HEXSTRIKE_AUDIT_LOG` — path to an audit log (JSONL).

---

## Operator hardening checklist

- [ ] Set a strong `HEXSTRIKE_API_TOKEN`; use the same value in your MCP client.
- [ ] Keep the server bound to `127.0.0.1` (or front it with an authenticating reverse proxy).
- [ ] Leave `HEXSTRIKE_ALLOW_RAW_EXEC` unset unless you specifically need raw exec.
- [ ] Set `HEXSTRIKE_SCOPE_FILE` for any real engagement.
- [ ] Run in Docker, one container per engagement, mapped `-p 127.0.0.1:PORT:8888`.
- [ ] Keep `alwaysAllow: []` in the MCP client so tool calls stay gated (per-call approval).

---

## Recent security fixes (this fork)

| Ref | Issue | Fix |
|---|---|---|
| #135 | Path traversal in the file sandbox (`/api/files/*`) allowed reads/writes/deletes outside the sandbox → RCE. | Added path containment (`_safe_path`) rejecting `../` and absolute paths across all file operations. |
| #261 | Threat-intel endpoint under-scored CVEs (a key mismatch disabled the exploit boost) and returned hardcoded IP/hash verdicts as if real. | Fixed the scoring key; placeholder results are now marked `"simulated": true` with `threat_level: UNKNOWN`. |
| #124 | `/api/command` (and `/api/python/execute`) exposed arbitrary code execution. | Now authenticated (see above) and disabled by default behind `HEXSTRIKE_ALLOW_RAW_EXEC`. |

Prior hardening carried in from integrated PRs: required token auth (#226), loopback-default bind (#178), and command-injection sanitization (#264, #266).

> Note on #204 ("RCE via unsafe deserialization"): the command-execution vector is covered by the fixes above. The "deserialization" claim does not hold against the current code — there is no server-side `pickle.loads` / `yaml.load` / `marshal.loads` of request input (the `pickle` code is the offensive payload generator, not input handling).

---

## Supported versions

Security fixes are applied to **`master`** of this fork.

| Version | Supported |
|---------|-----------|
| `master` | Yes |
| Older tags | No — please track `master` |

---

## Disclosure policy

After a fix ships, we may publish a GitHub Security Advisory or release note. Researchers who wish to remain anonymous will be respected.

---

## Acknowledgements

Thanks to the researchers who filed the upstream issues (#115, #122, #124, #135, #204, #261, #263, #265) that informed this fork's hardening.
