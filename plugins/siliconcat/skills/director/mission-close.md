# Closing a mission and sharing a role

Read this when a mission closes, or when the user asks to share a role with the team.

## Close the mission

Its outcome goes to the ticket, its open requests are closed or dropped, and its line in `DIRECTOR.md` is deleted. Then run a retro on the mission (`retro.md`: `director-retro --mission NAME`), which includes the review of rules and roles.

## Share a role with the team

The default is no: most roles serve one mission and stay local. Propose one only when all of these hold:

- it worked across several requests (`grep workers: director/requests/closed/*.md`), not one burst of work;
- its job keeps coming back in this repo after the mission (a crash triage or bug verifier, not a one-off upgrade or migration);
- a teammate's session would plausibly use it on its own;
- it has been stable: no corrections in its last few uses.

Name it in one line with the evidence. After the user says yes, rewrite it to stand on its own (no director, `DIRECTOR.md`, artifacts or the user's personal guardrails; a description any session understands) and open it as a normal PR. The local copy becomes a thin wrapper with only the director-specific parts, or goes.
