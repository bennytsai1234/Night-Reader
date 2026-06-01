# Technique: Design Grilling

A self-contained discipline for resolving an ambiguous design or decision before
acting. Pulled in by the change workflow's Decision Gate when a change has
several interdependent unresolved decisions or unclear requirements, and by the
investigate workflow for feasibility or approach questions ("should we do X",
"how should we design Y").

**Use it only for genuine ambiguity.** It interviews the user, which cuts
against the project's minimal-friction default — never grill a trivial or
clear-cut change. Stop the moment shared understanding is reached.

## The method

Interview the user about the design until you reach shared understanding. Walk
down each branch of the decision tree, resolving dependencies between decisions
one at a time.

- **One question at a time.** Wait for the answer before the next question;
  later questions often depend on earlier answers.
- **Recommend an answer to every question.** Never ask open-endedly without
  stating the option you would pick and why. The user is reacting to a proposal,
  not starting from blank.
- **Explore instead of asking when you can.** If a question can be answered by
  reading the atlas or the code, answer it yourself rather than spending a
  question on it.
- **Probe with concrete scenarios.** When a relationship or boundary is fuzzy,
  invent a specific scenario that forces a precise answer.

## Stay grounded in the atlas

Cross-reference each proposed decision against what the atlas already records,
and surface any contradiction immediately:

- **Against the index and module docs:** if a proposal conflicts with a module's
  recorded responsibility, boundary, or known risk, call it out — "the atlas
  says this module owns X; your proposal moves X out — is that intended?"
- **Against the Architecture Decisions table:** if a proposal re-litigates a
  recorded cross-module decision, name the prior decision and ask whether it is
  being reopened.
- **Sharpen vocabulary:** when the user uses a vague or overloaded term, propose
  the precise term the project already uses — keep the design's language
  consistent with the atlas.

## Output

The resolved decisions feed straight into the gate that called this technique:

- For a **Decision Gate**, they become the concrete options and recommendation,
  then the Before / After of the chosen option.
- For an **investigate** question, they become the plain-language answer about
  what to do and why.

Record decisions the same way the rest of the atlas does — cross-module
decisions as a row in the Architecture Decisions table, module-level decisions
as a note in the affected module's Known Risks or Do Not Do section. Do not
create separate decision-log files.
