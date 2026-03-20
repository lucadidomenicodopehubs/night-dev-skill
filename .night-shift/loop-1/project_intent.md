# Night Shift — Project Intent (Night Dev Skill)

## Scopo del software
Night Dev e' uno skill per Claude Code che implementa un agente di sviluppo software evolutivo autonomo. Lavora in loop: analizza il codice, pianifica miglioramenti, li implementa, e mantiene solo le modifiche che migliorano uno score numerico basato su test passing, coverage, e tempo di esecuzione.

## Componenti
1. **SKILL.md** — Definizione principale dello skill con 8 fasi (FASE 0-7)
2. **scripts/night-dev.sh** — Script bash wrapper (~1085 righe) che orchestra i loop, gestisce worktree git, calcola score, circuit breaker
3. **references/** — 5 prompt template per sub-agent (analyze, implementation, planner, report, research)
4. **commands/night-dev.md** — Interfaccia utente interattiva per setup
5. **Makefile** — Test suite (syntax, structure, help validation)

## Obiettivi dichiarati
- Sviluppo autonomo notturno con selezione evolutiva (solo miglioramenti accettati)
- Score function: `(passing*10) + (count*2) + (coverage*5) - (failing*20) - (time*0.1)`
- Batch-first con fallback sequenziale
- Circuit breaker e stagnation detection
- Support per GitHub URL clone, follow mode, inline mode

## Standard di qualita
- Test via Makefile: syntax (bash -n), structure (FASE 0-6b presenti), CLI (--help documenta tutti i flag)
- File reference richiesti dal Makefile: analyze-prompt.md, planner-prompt.md, implementation-prompt.md, risk-gate-prompt.md, report-prompt.md, research-prompt.md, codeintel-reference.md

## Feature mancanti / Incongruenze
1. **risk-gate-prompt.md** — Listato nei REQUIRED_REFS del Makefile ma NON presente in references/ (il test usa SKIP)
2. **codeintel-reference.md** — Listato nei REQUIRED_REFS del Makefile ma NON presente in references/ (il test usa SKIP)
3. **research-prompt.md** — Presente nel Makefile ma NON viene mai referenziato con `~/.claude/skills/night-dev/references/research-prompt.md` nello SKILL.md (lo SKILL.md lo referenzia correttamente)
4. Lo score calculation in bash usa integer math con *10 scale, che puo perdere precisione per valori decimali di coverage/time
5. Il `parse_test_results` ha pattern matching limitato — non gestisce Go test output (`ok/FAIL` format)
6. La funzione `follow_night_dev` cerca `.night-dev/` ma usa `find` con maxdepth 4 che potrebbe essere lento su filesystem grandi
