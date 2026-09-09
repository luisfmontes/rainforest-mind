# Plano — statusline com tempo até o reset; checkout principal na main

**Slug:** `statusline-reset-e-principal-na-main` · **Design:** `docs/rainforest/design/statusline-reset-e-principal-na-main.md`
**Base:** `origin/main` @ `58e8c37` · **Branch:** `fluxo/statusline-reset-e-principal-na-main`

Quatro tarefas. T1 e T2 são independentes e vão juntas; T3 documenta o que T2
implementou (o nome da chave e a forma da recusa saem do código, não do plano);
T4 fecha a versão depois de tudo.

**Restrição que vale para todas:** o repo é público — nenhum caminho desta
máquina em código, teste ou fixture. Bateria que precisa de repositório git
monta o seu em pasta temporária.

## O que não pode quebrar
- A barra nunca trava nem suja o harness: segmento que falhar simplesmente não aparece (`statusline.py`, docstring).
- `estado.cjs` fora de repositório git continua funcionando igual — a caixa de areia de `scripts/testa-estado.sh` não é repositório, e os 40+ casos dela seguem verdes sem edição.
- `conferir-invariantes.cjs` continua achando "nunca a `main`" no núcleo da regra 11.
- As baterias de `hooks/testa-config.sh` continuam verdes com a chave nova.

## Tarefas

### 1. Statusline: tempo até o reset ao lado de `5h`/`7d` [tipo: implementar]
atende: D1
arquivos: `statusline/statusline.py`, `statusline/testa-statusline-limites.py`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `statusline/statusline.py`
  de: o ramo que formata `<n>d<h>h` quando faltam 86400 segundos ou mais
  para: formatar sempre como `<h>h<mm>` (apagar o ramo de dias)
  bateria: `bash scripts/testa-statusline.sh`
  fixture: caso "7d com 3 dias e 4 horas" da bateria `testa-statusline-limites.py`
pronto quando: com o JSON do harness no stdin contendo `rate_limits.five_hour = {"used_percentage": 23.4, "resets_at": <agora + 7800 s>}` e `seven_day = {"used_percentage": 41.2, "resets_at": <agora + 3*86400 + 4*3600>}`, a barra imprime `5h 23% ↻2h10 7d 41% ↻3d4h` (sem ANSI) — provado por `python statusline/testa-statusline-limites.py statusline/statusline.py` devolvendo `OK` em todos os casos, inclusive `resets_at` ausente (sem `↻`), `resets_at` no passado (sem `↻`) e `resets_at` string (sem `↻`, sem exceção).

**Achado ao executar (2026-09-08), consertado aqui porque mora no mesmo arquivo e o caso ponta a ponta o pega:** o `main()` chamava `segmento_escada_intensidade()` e ela chamava `resolver_raiz_dados()` sem o `cwd` obrigatório — `TypeError`, barra inteira vazia, desde 27fcb1f (Tarefa 6 do dial de intensidade). Nenhuma das três baterias anteriores passava pelo `main()`, então nenhuma reprovou. A versão 1.8.1 instalada no cache tem o defeito: a barra do harness estava vazia em toda sessão. O caso "ponta a ponta pelo stdin" da bateria nova roda o `main()` de verdade e falha se qualquer segmento estourar.

### 2. `estado.cjs iniciar` recusa checkout principal fora da branch padrão [tipo: implementar]
atende: D3
arquivos: `scripts/estado.cjs`, `hooks/lib/config.cjs`, `scripts/testa-estado-principal.sh`, `hooks/testa-config.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `scripts/estado.cjs`
  de: a comparação "branch atual !== branch padrão" que dispara a recusa
  para: comparação sempre falsa (recusa nunca dispara)
  bateria: `bash scripts/testa-estado-principal.sh`
  fixture: caso "principal em fluxo/x sem chave → exit 2"
pronto quando: com um repositório git montado em pasta temporária (commit inicial em `main`, `git checkout -b fluxo/x` no checkout principal), `node scripts/estado.cjs iniciar --slug x` sai 2, imprime `RECUSADO` e a receita com `git worktree add` e `git checkout main`, e **não** grava `docs/rainforest/estado/x.json`; no mesmo repositório em `main` sai 0; num worktree linkado (`git worktree add ../wt fluxo/x`) rodando de dentro dele sai 0; com `.rainforest/config.json` contendo `{"principal-livre": true}` sai 0; fora de repositório git sai 0 — provado por `bash scripts/testa-estado-principal.sh` listando esses cinco casos com `ok` e saindo 0, e `bash scripts/testa-estado.sh` continuando verde. A branch padrão vem de `refs/remotes/origin/HEAD` quando existe, senão `main`, senão `master`. `exigir` no mesmo estado (principal fora da padrão, sem chave) sai 0 e escreve uma linha de aviso no stderr contendo `principal`.

### 3. Regra 11 e README: principal na main, trabalho em worktree [tipo: docs]
atende: D2, D3
arquivos: `skills/rainforest-mind/SKILL.md`, `skills/rainforest-mind/references/regra-11.md`, `skills/rainforest-mind/references/regra-11-principal.md`, `README.md`, `hooks/testa-contexto-sessao.sh`
depende de: 2

**Emenda ao executar:** `regra-11.md` estava a 658 B do teto de 10.500 B de um
reference, e o texto novo tinha 1.400 B — a elaboração nova foi para um arquivo
irmão, `regra-11-principal.md`, no mesmo padrão de `regra-10-portaria.md` e
`regra-12-acervo.md`. E o núcleo mudou de tamanho (388 → 386 B), então o contrato
`NUCLEO_ESPERADO` de `hooks/testa-contexto-sessao.sh` acompanha (5595 → 5593).
paralela: nao
mutacao: n/a
  motivo: texto de regra; não há comportamento a inverter, a coerência é conferida contra o código de T2
pronto quando: com o núcleo da regra 11 em `SKILL.md` dizendo que o checkout principal fica na branch padrão e trabalho nasce em worktree, a elaboração em `regra-11.md` descrevendo a recusa do `iniciar` e a chave que a desliga, e a tabela de regras do README refletindo a mesma frase — o nome da chave citado nos três arquivos é **o mesmo** que `hooks/lib/config.cjs` exporta em `CHAVES` (provado por `node -e "const k=Object.keys(require('./hooks/lib/config.cjs').CHAVES).filter(k=>k.startsWith('principal'));console.log(k)"` e `grep -c "<chave>" skills/rainforest-mind/SKILL.md skills/rainforest-mind/references/regra-11.md README.md` devolvendo ≥1 em cada), `node scripts/conferir-invariantes.cjs` sai 0, e `node scripts/medir-skill.cjs` mostra `regras=17` com o núcleo não maior que o teto que `hooks/testa-contexto-sessao.sh` impõe (bateria verde).

### 4. Versão 1.9.0 [tipo: configurar]
atende: D4
arquivos: `.claude-plugin/plugin.json`, `README.md`
depende de: 1, 2, 3
paralela: nao
mutacao: n/a
  motivo: número de versão; a divergência entre os dois lugares é o que `testa-versao.sh` já pega
pronto quando: com `plugin.json` e o badge do README em `1.9.0`, `bash scripts/testa-versao.sh` sai 0 e `node scripts/conferir-versao.cjs` sai 0 comparando com `origin/main`.
