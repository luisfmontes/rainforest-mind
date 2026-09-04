# Plano: Régua absorve `bar.md` de mecanismos e preflight de renderização

Design: docs/rainforest/design/fluxo-12-regua.md

## O que não pode quebrar

- Os três freios da Fase 1 da `regua` (teto como abort e não como saída, commit
  por rodada, calibragem na rodada 1) continuam existindo e com o mesmo texto de
  justificativa — são o que a skill tem a mais que o original.
- O crítico continua **cego**: `Agent` novo toda rodada, sem rótulo, sem saber
  qual lado é o nosso, veredito binário e lacuna única. O `bar.md` entra como
  insumo dele, nunca como rubrica pontuada.
- O gate "quase sempre a resposta é não" (a seção que manda NÃO usar a skill
  quando existe teste) continua sendo a primeira coisa depois do título.
- `node scripts/orcamento.cjs` continua saindo 0 — a absorção não pode empurrar o
  plugin para fora do teto de 15.000 B.

## Tarefas

### 1. Absorver `bar.md` e preflight na skill `regua` [tipo: docs]
atende: D1, D2, D3, D4, D5, D6
arquivos: `skills/regua/SKILL.md`
depende de: nenhuma
paralela: nao
mutacao: n/a
  motivo: tarefa de prosa numa skill — não há ramo de código a inverter. A
  falsificação dela é coerência com as decisões do design, medida pela tarefa 3.
pronto quando: com a `regua` real lida por um leitor que não participou desta
sessão, as seis decisões estão implementadas como prescrição e não como menção —
provado por `node scripts/orcamento.cjs` devolvendo exit 0 (o teto de 15.000 B
não estourou) e pela tarefa 3, que é o critério de coerência desta.

### 2. README acompanha a mudança [tipo: docs]
atende: D2
arquivos: `README.md`
depende de: 1
paralela: nao
mutacao: n/a
  motivo: doc de superfície do plugin; sem comportamento a inverter.
pronto quando: com `git diff --name-only origin/main...HEAD`, todo caminho novo
que a tarefa 1 introduziu (`docs/rainforest/reguas/`) aparece no README, e nenhum
caminho citado no README deixou de existir — provado por
`node -e "const fs=require('fs');const r=fs.readFileSync('README.md','utf8');const faltando=['docs/rainforest/reguas'].filter(p=>!r.includes(p));if(faltando.length){console.error('faltando no README: '+faltando);process.exit(1)}console.log('ok')"`
devolvendo `ok` com exit 0.

### 3. Segunda opinião cross-model sobre a coerência com o design [tipo: teste]
atende: D1, D3, D4, D5
arquivos: `docs/rainforest/criterios/fluxo-12-regua.md`
depende de: 1, 2
paralela: nao
mutacao:
  arquivo: `skills/regua/SKILL.md`
  de: a frase que restringe o `bar.md` ao crítico (D1)
  para: a mesma frase dizendo que o builder também recebe o `bar.md`
  bateria: `node scripts/segunda-opiniao.cjs --base origin/main --head HEAD --criterio docs/rainforest/criterios/fluxo-12-regua.md --modelo codex`
  fixture: o item do arquivo de critério que afirma "o builder NÃO vê o `bar.md`"
  emenda 2026-09-04 (achado do `revisar`, rodada 2): a rodada 1 mutou esse item e
  saiu `discordo` nomeando o critério 1. A rodada 2 mutou **outro** alvo — a
  redação do preflight, critério 3 — porque foi essa a linha que o conserto
  mexeu, e mutação vale sobre o texto que mudou, não sobre um texto intocado. O
  `estado.json` guarda só o último bloco `executar`, então a prova da rodada 1
  vive no histórico (`git show 30d3840 -- docs/rainforest/estado/fluxo-12-regua.json`)
  e o campo `fixture` do estado passa a nomear as duas.
pronto quando: com o diff real `origin/main...HEAD` e o arquivo de critério
listando as seis decisões em forma falsificável, um modelo de outra família
devolve `concordo` — provado por
`node scripts/segunda-opiniao.cjs --base origin/main --head HEAD --criterio docs/rainforest/criterios/fluxo-12-regua.md --modelo codex`
devolvendo `concordo` na **última linha**. **O exit code não discrimina aqui**: o
script sai 0 tanto em `concordo` quanto em `discordo` (só recusa por uso errado,
diff vazio ou veredito fora do vocabulário) — medido em 2026-09-04, com a mutação
aplicada saindo `discordo` **e exit 0**. Quem julga é a última linha.
