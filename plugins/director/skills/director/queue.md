# Working a ticket queue

Read this when the user points you at a board, a JQL filter or a backlog.

- The queue becomes a mission in `DIRECTOR.md`: the filter, how done is judged, and how many tickets may be in flight (two or three).
- Intake goes to `tracker`: a ranked shortlist with a readiness check per ticket (acceptance criteria, not blocked, which repo and files it touches), grouped so tickets on the same code sit together. A ticket that isn't ready gets a question on the ticket instead of a build. The user approves the shortlist once.
- One request per ticket: `req new --mission <name>` with the ticket key and text.
- The next ticket goes to the existing builder when it is the same thread (`SKILL.md` section 3): a stacked slice, a follow-up to that builder's PR. Otherwise a fresh builder. Verifiers are always fresh.
- Gates join only when triggered. The first one in the mission writes a baseline file the later ones read (the budgeter's current bill by service, the auditor's accepted findings), so no gate rebuilds it.
- When a ticket closes, take the next one from the approved list and report it in one line. Stop when the list is done, a hard rule needs the user, or a ticket fails twice.
