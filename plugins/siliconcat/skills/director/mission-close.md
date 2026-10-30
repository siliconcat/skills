# Closing a mission and reviewing rules

Read this when a mission closes, when the user asks for a rules review, or when `req lint` says `DIRECTOR.md` is over budget.

## Rules and roles review

Rules harden and start limiting the system.

1. List every rule across `DIRECTOR.md` and the role files, and propose which to drop, merge, or turn into a real check.
2. Review the roles with evidence: `director-audit` on the mission's sessions, `req stats` for which roles needed rework, and `grep workers: director/requests/closed/*.md` for which were used. Propose which background to move into a role file, which role to split by area, and which unused roles can go.
3. Change them only after the user says yes.

## Close the mission

Its outcome goes to the ticket, its open requests are closed or dropped, and its line in `DIRECTOR.md` is deleted. Then run the review above.

## Share a role with the team

The default is no: most roles serve one mission and stay local. Propose one only when all of these hold:

- it worked across several requests (`grep workers: director/requests/closed/*.md`), not one burst of work;
- its job keeps coming back in this repo after the mission (a crash triage or bug verifier, not a one-off upgrade or migration);
- a teammate's session would plausibly use it on its own;
- it has been stable: no corrections in its last few uses.

Name it in one line with the evidence. After the user says yes, rewrite it to stand on its own (no director, `DIRECTOR.md`, artifacts or the user's personal guardrails; a description any session understands) and open it as a normal PR. The local copy becomes a thin wrapper with only the director-specific parts, or goes.
