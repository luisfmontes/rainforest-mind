# Zerar as Issues abertas, rodada 8 — gate bash "$t" e bypass do for/do (#309), gêmeo Python do conferir-entrega (#303), eval de gatilho (#302)

## Objetivo
Fechar o bypass de palavra reservada nos gates de texto e o falso positivo de
`bash "$t"`, pôr o gêmeo Python de `conferir-entrega` de volta em equivalência
com o `.cjs` e travado no CI, e dar ao repo a primeira suíte de eval de gatilho
de skill, medida localmente antes de qualquer decisão de CI.

## Decisões fechadas
- **D1 — #309 entra inteira: o bypass de palavra reservada primeiro, o falso positivo de `"$t"` depois, na mesma entrega** — porquê: medido em 2026-09-22, `for t in x; do bash -c "gh issue close 12"; done` sai 0 no `gate-fechar-issue` enquanto `bash -c "gh issue close 12"` sai 2; `posicaoDeComando` (`hooks/lib/tokens-comando.cjs:206`) não pula `do`/`then`/`else`/`elif`/`!`/`{`, e o `bash` deixa de estar em posição de comando. Bypass pesa mais que falso positivo, e os dois mexem na mesma função e na mesma bateria.
- **D2 — Falso positivo: variável entre aspas duplas (`"$x"`/`"${x}"`) só é caminho de script quando é o ÚLTIMO argumento do wrapper (redirecionamentos não contam); sem aspas ou com argumento depois, continua ilegível** — porquê: com aspas não há word-splitting, mas `bash "$f" "gh issue close 1"` com `f=-c` vira `bash -c` escondido (caso perigoso nomeado na issue).
- **D3 — Bateria dos três gates de texto ganha: os casos da tabela da #309, o caso perigoso (→ 2), e o bypass por palavra reservada em `for/do`, `if/then`, `else`, `!`, `{ ...; }` (→ 2), mais mutação de cada conserto** — porquê: os dois consertos precisam ser vistos travando, e o bypass não tinha caso nenhum.
- **D4 — #303: portar, não aposentar — os quatro grupos (`--escopo`, exit 69 com `nao-verificavel:` no stderr, commit vazio, BOM) no `scripts/conferir-entrega.py`** — porquê: é o instrumento da regra 12, e o exit 69 é a diferença entre "reprovou" e "não sei". Pronto = `CONFERIR="python scripts/conferir-entrega.py" bash scripts/testa-conferir-entrega.sh` exit 0 com a mesma contagem de `ok` do `.cjs`.
- **D5 — Uma mutação por grupo portado no `.py`, e a linha do gêmeo vira passo próprio no workflow `baterias` (não dentro da bateria padrão)** — porquê: quatro garantias sumiram sem nada ficar vermelho; passo separado mantém a bateria padrão no tempo atual e ainda assim o CI roda as duas implementações.
- **D6 — #302 nesta rodada: suíte em `evals/` com os 7 pares de colisão da issue (positivos e negativos nomeando a skill dona), baseline pelo braço `--ablation with-without` do `claude plugin eval`, e um caso de mutação (description sabotada → eval reprova); rodada UMA vez localmente com o custo medido e registrado** — porquê: pôr credencial (`ANTHROPIC_API_KEY`) e custo recorrente no CI é decisão do Luís, e se toma melhor com o custo de uma rodada real na mão.
- **D7 — #302 fica aberta depois da entrega, pendente só do critério 3 (CI), com comentário trazendo o custo medido; #309 e #303 fecham pelo PR** — porquê: o critério 3 depende da decisão de secret/custo, que D6 deixou para depois.
- **D8 — Versão: bump de minor sobre o que estiver em `origin/main` no `fechar` (o #308 leva a main a 1.22.0)** — porquê: muda comportamento de gate e acrescenta suíte nova; o número exato depende da ordem dos merges.

## Avaliado e descartado
- Aposentar o gêmeo Python (alternativa honesta da #303): descartado porque o grupo do exit 69 não é cosmético e o `CONTRIBUTING.md` apresenta o gêmeo como a prova de que o port não perdeu garantia.
- Rodar o gêmeo dentro da bateria padrão (`testa-conferir-entrega.sh` executando as duas implementações): dobraria o tempo da bateria mais lenta do conferidor em toda execução local; o passo separado no CI dá a mesma trava.
- Tratar toda `"$x"` entre aspas como caminho: reabre o `bash "$f" "gh ..."` com `f=-c`.

## Fora de escopo
- Wiring da eval de gatilho no CI (critério 3 da #302): decisão separada, depois do custo medido.
- Reescrever as 16 `description` sem roteamento negativo: a própria #302 manda a régua antes do ajuste.
- O "backup externo falhou (exit 2)" do sentinela em `vigias/ERROS.md` (21 e 22/09): achado à parte, não desta rodada.

## Em aberto
