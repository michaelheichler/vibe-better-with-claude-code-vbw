# Dijkstra Correctness Discipline

On-demand grounding for correctness-critical implementation work (Dev) and its verification (QA). Loaded when a task triggers the Correctness Discipline section in `templates/agent-roles/dev.md.tpl` or the Correctness Verification section in `templates/agent-roles/qa.md.tpl`.

## Purpose

Design programs the Dijkstra way: state the postcondition first, derive the program from it, and let the proof and the code grow together. The briefs in this directory are paraphrased summaries of two books:

- A Discipline of Programming (Dijkstra, 1976): weakest preconditions, guarded commands, invariants, variants, and 16 worked derivations.
- Structured Programming (Dahl, Dijkstra, Hoare, 1972): why testing cannot show the absence of bugs, stepwise refinement, data structuring by abstract type, and hierarchical program structure.

## Source boundary

Use the briefs as method guidance for design, derivation, review, and implementation decisions. Do not reproduce book prose or full derivations. When notation helps, write only the minimal generic form the task needs. Prefer the project's language and codebase idiom over book notation. Dijkstra's mini-language is a reasoning tool, not a coding target.

## Workflow

1. Classify the task: a loop or algorithm to derive, an existing loop to verify, a data-structure choice, or a program-structure question.
2. Load the one to three most relevant briefs from the routing table below. Never more. The briefs are progressive-disclosure depth, not required reading.
3. Write the postcondition R before any code. If R is vague, make the task's acceptance criterion precise first.
4. Derive, do not guess: choose an invariant P by weakening R, choose guards so that P and (not guards) implies R, choose a variant function to prove termination, then translate to the target language.
5. In review, run the same checks backward: find the invariant the loop maintains, the variant that bounds it, and the reason every guard case is covered. A loop with no nameable invariant is a finding.

## Routing table

Method core (load these for most tasks):

- Predicate transformers, weakest preconditions, states and predicates: `references/dijkstra/d02-states-and-semantic-characterization.md`
- wp rules for skip, abort, assignment, composition, if-fi, do-od, guarded commands, the two loop theorems: `references/dijkstra/d03-wp-semantics-of-the-language.md`
- Termination, variant (bound) functions, Euclid's gcd as invariant-driven design: `references/dijkstra/d04-termination-and-euclid.md`
- Deriving programs from postconditions, choosing invariants by weakening the postcondition: `references/dijkstra/d05-formal-treatment-of-small-examples.md`
- Testing versus proving, program size and our limited heads, abstraction, stepwise refinement: `references/dijkstra/s13-notes-on-structured-programming-i.md`
- Refinement worked end to end (eight queens), program families, layering: `references/dijkstra/s14-notes-on-structured-programming-ii.md`

Concepts and language design:

- Executional abstraction, role of programming languages: `references/dijkstra/d01-executional-abstraction-and-languages.md`
- Nondeterminacy and why it stays bounded, scope and initialization of variables: `references/dijkstra/d06-nondeterminacy-and-scope.md`
- Arrays as functions, array assignment semantics: `references/dijkstra/d07-array-variables.md`
- Manuals, implementations, and Dijkstra's own retrospect on the discipline: `references/dijkstra/d12-strong-components-manuals-retrospect.md`

Worked derivations (load the one matching the problem shape):

- Linear search, next permutation, Dutch national flag, sequential file update, merging: `references/dijkstra/d08-search-permutation-flag-file-merging.md`
- Hamming numbers, pattern matching, sum of two squares: `references/dijkstra/d09-hamming-pattern-matching-two-squares.md`
- Smallest prime factor, most isolated villages, shortest spanning tree: `references/dijkstra/d10-prime-factor-villages-spanning-tree.md`
- Union-find (Rem's algorithm), 3D convex hull: `references/dijkstra/d11-rem-equivalence-convex-hull.md`
- Strong components in a directed graph: `references/dijkstra/d12-strong-components-manuals-retrospect.md`

Data and program structure (Hoare, Dahl):

- Types, cartesian products, discriminated unions, arrays: `references/dijkstra/s15-notes-on-data-structuring-i.md`
- Powersets, sequences, recursive data structures, sparse representation: `references/dijkstra/s16-notes-on-data-structuring-ii.md`
- Classes, objects, coroutines, hierarchical decomposition: `references/dijkstra/s17-hierarchical-program-structures.md`

## Review heuristics

- Every loop names its invariant and its variant. No variant, no termination claim.
- The postcondition comes before the code. Code without a stated R is a guess.
- Case analysis is complete by construction: the disjunction of the guards must be provable, not assumed.
- Prefer the derivation that makes the proof short over the code that looks clever.
- Testing demonstrates presence of bugs, never absence. A passing test is evidence, not proof.
- Separate mathematical correctness concerns from efficiency concerns, in that order.

## Output style

State assumptions and the postcondition first. Show the invariant and variant as short annotations next to the loop, not as an essay. Translate guarded commands to the project's language idiomatically. When a derivation is the deliverable, show the key steps, not every algebraic line.

## Grounding line

When this discipline was engaged for a task, end the `## What Was Built` section of SUMMARY.md with one bullet:

`Grounding: <briefs read> - <postcondition stated, invariant/variant named>`

QA treats a correctness-flagged task whose SUMMARY lacks this line as a verification finding.
