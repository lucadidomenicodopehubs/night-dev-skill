---
name: night-dev
description: Launch autonomous evolutionary software development loop
---

# Night Dev — Setup Interattivo

Quando l'utente invoca questa skill, NON eseguire subito lo script. Conduci un'intervista rapida per raccogliere le impostazioni.

## Step 1: Raccogli le preferenze

Se l'utente ha gia fornito alcuni parametri nel messaggio (es. `/night-dev /path/to/project`), usali come default e chiedi conferma per il resto. Se non ha specificato nulla, chiedi tutto.

Fai UNA SOLA domanda che copre tutte le impostazioni, presentandole come lista con i default gia suggeriti:

```
Configuro il Night Dev (sviluppo evolutivo). Confermi queste impostazioni o vuoi cambiare qualcosa?

1. Progetto: [path rilevato dalla working directory corrente, oppure "da specificare"]
2. Numero loop: 5
3. Ore massime: 8
4. Web research: attiva
5. Branch: [default del repo]
6. Auto-push: no
7. Verbose (output live): no

Nota: Night Dev e' DIVERSO da Night Shift.
- Night Shift = manutenzione conservativa (fix bug, patch sicurezza, qualita)
- Night Dev = sviluppo aggressivo con selezione evolutiva (nuove feature, test, refactoring)

Ogni modifica viene accettata SOLO se migliora lo score del software:
  score = (test_passing * 10) + (test_count * 2) + (coverage * 5) - (test_failing * 20) - (time * 0.1)

Rispondi "ok" per confermare, oppure indica cosa cambiare (es. "10 loop, push attivo, verbose").
```

### Logica di rilevamento progetto

- Se l'utente ha specificato un path o URL, usalo
- Se la working directory corrente e' un repo git con un test runner riconosciuto, suggeriscilo come default
- Se ci sono repo in `~/night-dev-repos/` o `~/night-shift-repos/`, menzionali come opzioni
- Se nulla e' rilevabile, chiedi esplicitamente

## Step 2: Costruisci il comando

Dopo la conferma dell'utente, costruisci la riga di comando con i flag appropriati:

```bash
bash ~/.claude/skills/night-dev/scripts/night-dev.sh <project-path-or-url> [--max-loops N] [--hours H] [--skip-research] [--branch BRANCH] [--push] [--verbose] [--follow] [--inline]
```

Mapping delle risposte ai flag:
- Progetto -> primo argomento (path locale o GitHub URL)
- Numero loop -> `--max-loops N`
- Ore massime -> `--hours H`
- Web research disattivata -> `--skip-research`
- Branch specifico -> `--branch BRANCH`
- Auto-push attivo -> `--push`
- Verbose/output live -> `--verbose`
- Inline mode -> `--inline`

## Step 3: Mostra anteprima score

Prima di lanciare, esegui una lettura veloce del test runner per mostrare lo score iniziale:

```bash
cd <project-path> && <test-runner> 2>&1 | tail -20
```

Mostra il punteggio calcolato:
```
Score iniziale stimato: {score}
  - Test passing: {N} (x10 = {N*10})
  - Test count: {N} (x2 = {N*2})
  - Coverage: {N}% (x5 = {N*5})
  - Test failing: {N} (x-20 = {N*-20})
  - Exec time: {N}s (x-0.1 = {N*-0.1})

Night Dev cerchera di alzare questo score ad ogni loop.
```

## Step 4: Esegui

Mostra il comando che stai per eseguire, poi lancialo.

## Parametri supportati

| Parametro | Flag | Default |
|-----------|------|---------|
| Progetto | primo argomento | working directory |
| Loop massimi | `--max-loops N` | 5 |
| Ore massime | `--hours H` | 8 |
| Web research | `--skip-research` (per disattivare) | attiva |
| Branch | `--branch BRANCH` | default del repo |
| Auto-push | `--push` | disattivato |
| Output live | `--verbose` | disattivato |
| Inline mode | `--inline` | disattivato |
| Attach a istanza | `--follow [path]` | - |
