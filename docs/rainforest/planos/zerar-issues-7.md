# Plano: Zerar as Issues abertas, rodada 7 — rota com emoji por etapa (#299)

Design: docs/rainforest/design/zerar-issues-7.md

## O que não pode quebrar
- Núcleo injetado cresce só os 4 B do ` ↳` da regra 4 (5895 → 5899 B, medido ao vivo pelo planejamento); nenhuma outra frase do núcleo muda.
- A regra 1 continua mandando renumerar respostas a pedidos; a exceção vale só para etapas de uma rota.
- Baterias que leem esses arquivos seguem verdes: `hooks/testa-contexto-sessao.sh`, `scripts/testa-mapa-regras.sh`, `scripts/testa-conferir-invariantes.sh`, `scripts/testa-ponte.sh`, `scripts/testa-conferir-ponte.sh`.

## Tarefas

### 1. Regra 4 ganha elaboração com o formato de rota [tipo: docs]
atende: D1, D2, D3, D4
arquivos: `skills/rainforest-mind/SKILL.md`, `skills/rainforest-mind/references/regra-04.md`, `hooks/testa-contexto-sessao.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `hooks/testa-contexto-sessao.sh`
  de: `NUCLEO_ESPERADO=5899`
  para: `NUCLEO_ESPERADO=5895`
  bateria: `bash hooks/testa-contexto-sessao.sh`
  timeout: `300000`
  fixture: `testa-contexto-sessao.sh, assercao "D7: nucleo emitido mede exatamente"`
pronto quando: (`de:` é trecho NOVO.) Em `SKILL.md`, logo após o parágrafo da regra 4 (texto intocado), entram `<!-- detalhe -->` e `Elaboração: references/regra-04.md`. `regra-04.md` perde o stub "auto-suficiente" e passa a prescrever: rota declarada no início com as etapas numeradas; a cada checkpoint a rota INTEIRA re-renderizada (D2), linhas ✅ reduzidas ao rótulo e as demais com o fato concreto em `código`; exatamente quatro estados ✅ feito · 🔄 rodando · ⏳ não começou · ❌ reprovado/bloqueado (D3); numeração original estável, com a ressalva explícita de que isso é o oposto da renumeração da regra 1 e por quê — regra 1 numera pedidos, esta numera etapas (D4); um exemplo com as quatro marcas. Entrada real: o hook de abertura com o SKILL.md do worktree — a injeção traz `**4. Checkpoint no meio, não só no fim.**` terminando em ` ↳` e o núcleo mede 5899 B; `NUCLEO_ESPERADO` vai para 5899 — provado por `bash hooks/testa-contexto-sessao.sh` saindo 0 (295/0) e por `node scripts/conferir-mutacao.cjs --arquivo hooks/testa-contexto-sessao.sh --de "NUCLEO_ESPERADO=5899" --para "NUCLEO_ESPERADO=5895" --bateria "bash hooks/testa-contexto-sessao.sh"` saindo 0 (`vermelho`, D7 falha com 5895). Coerência com o design: os estados listados são os quatro de D3, sem quinto; o texto não põe o formato no núcleo (D1).

### 2. Exceção na regra 1 e ponteiro no modo-dev [tipo: docs]
atende: D4, D5
arquivos: `skills/rainforest-mind/references/regra-01.md`, `skills/modo-dev/SKILL.md`
depende de: nenhuma
paralela: sim
mutacao: n/a
  motivo: texto de elaboração e de skill sob demanda, fora do núcleo injetado; nenhuma bateria mede prosa dessas linhas.
pronto quando: `regra-01.md`, junto da frase "renumeram a partir do 1", ganha UMA frase dizendo que etapas de uma rota (regra 4) NÃO renumeram e apontando `regra-04.md`; `modo-dev/SKILL.md` item 3 ganha UMA frase dizendo que a rota `→ verifica:` é a mesma lista que o acompanhamento com emoji da regra 4 re-renderiza. Provado por `git diff origin/main -- skills/rainforest-mind/references/regra-01.md skills/modo-dev/SKILL.md --stat` mostrando só esses dois arquivos com poucas linhas, e por leitura: a exceção não contradiz a regra de pedidos (continua renumerando) e cita a regra 4 pelo caminho real. `bash scripts/testa-mapa-regras.sh` e `bash scripts/testa-conferir-invariantes.sh` saem 0.

### 3. Versão 1.19.1 no plugin.json e no badge do README [tipo: configurar]
atende: D6
arquivos: `.claude-plugin/plugin.json`, `README.md`
depende de: nenhuma
paralela: sim
mutacao: n/a
  motivo: troca de número de versão; a falsificação mecânica é o `conferir-versao.cjs` contra a `origin/main`.
pronto quando: com a `origin/main` em 1.19.0, `node scripts/conferir-versao.cjs` sai exit 0 dizendo que 1.19.1 supera a `origin/main`, e o badge do `README.md` mostra o mesmo número do `plugin.json` — provado por `node scripts/conferir-versao.cjs` e `bash scripts/testa-versao.sh` saindo 0.
