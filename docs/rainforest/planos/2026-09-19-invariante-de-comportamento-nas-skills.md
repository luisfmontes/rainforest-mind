# Plano: Invariante de comportamento nas skills de ação, com assertiva negativa

Design: docs/rainforest/design/2026-09-19-invariante-de-comportamento-nas-skills.md

Base: `4f714ef69` (`origin/main` no momento da abertura do fluxo). O hash corrente
se deriva com `git rev-parse`, nunca se copia desta linha.

## O que não pode quebrar

- As 5 invariantes já existentes de `skills/rainforest-mind/` continuam verdes, nas mesmas regras 10, 11, 12, 13 e 15, com a mesma semântica de `onde: ["skill","nucleo"]`.
- `scripts/testa-conferir-invariantes.sh` continua sendo descoberto pelo glob `scripts/testa-*.sh` do `varrer-baterias.sh`, e continua verde em Node 22 e 24.
- Os dois mutantes que aquela bateria já tem continuam existindo e continuam ficando vermelhos.
- Nenhum `SKILL.md` das seis skills tem o corpo alterado por este trabalho — o que entra é arquivo de invariante ao lado, nunca edição da skill.
- `node scripts/conferir-livro-de-repos.cjs` continua saindo 0.

## Tarefas

### 1. Estender o conferir-invariantes: N skills, `onde` opcional, `nao_deve` e ocorrência única [tipo: implementar]
atende: D2, D3, D4, D5, D8, D11
arquivos: `scripts/conferir-invariantes.cjs`, `scripts/testa-conferir-invariantes.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `scripts/conferir-invariantes.cjs`
  de: `const proibidaPresente = tipo === 'nao_deve' && corpo.includes(inv.frase);`
  para: `const proibidaPresente = false;`
  bateria: `bash scripts/testa-conferir-invariantes.sh`
  fixture: `testa-conferir-invariantes.sh, secao "nao_deve: frase proibida presente no corpo reprova"`
pronto quando: com uma cópia de caixa de areia onde `skills/fechar/invariantes.json` declara `{"frase": "CONFIRMO fechar issue", "tipo": "nao_deve"}` e a string `CONFIRMO fechar issue` foi plantada dentro de `skills/fechar/SKILL.md`, `node scripts/conferir-invariantes.cjs` sai **2** e o stderr contém `fechar` e `CONFIRMO fechar issue`; com a mesma string ausente do corpo, sai **0**; e com um `deve` cuja frase aparece **duas** vezes no corpo, sai **2** citando a contagem — provado por `bash scripts/testa-conferir-invariantes.sh` terminando em `falhou=0`

### 2. Escrever os seis arquivos de invariante das skills de ação [tipo: configurar]
atende: D1, D6, D10
arquivos: `skills/fechar/invariantes.json`, `skills/limpar/invariantes.json`, `skills/executar/invariantes.json`, `skills/revisar/invariantes.json`, `skills/verificar/invariantes.json`, `skills/plano/invariantes.json`
depende de: 1
paralela: nao
mutacao:
  arquivo: `skills/limpar/SKILL.md`
  de: `**Nunca entra na remoção**`
  para: `**Entra na remoção**`
  bateria: `bash scripts/testa-conferir-invariantes.sh`
  fixture: `testa-conferir-invariantes.sh, secao "skill de acao: frase obrigatoria removida do corpo reprova"`
pronto quando: com os seis arquivos na árvore e nenhum `SKILL.md` alterado, `node scripts/conferir-invariantes.cjs` sai **0** e relata **15** invariantes conferidas (as 5 da `rainforest-mind` mais as 10 aprovadas); e com a frase `Nunca entra na remoção` removida de `skills/limpar/SKILL.md` numa cópia de caixa de areia, sai **2** nomeando `limpar` — provado por `bash scripts/testa-conferir-invariantes.sh` terminando em `falhou=0`

As dez frases aprovadas pelo usuário em 2026-09-19, sem corte, estão na tabela
"Frases propostas" do design. Nenhuma delas usa `--confirmo` como frase de
`nao_deve`, pela D6: o token é obrigatório no `limpar` e aparece dentro da
própria frase que o proíbe no `fechar`.

### 3. Migrar as 5 invariantes da rainforest-mind para o formato novo [tipo: configurar]
atende: D7
arquivos: `skills/rainforest-mind/invariantes.json`
depende de: 1
paralela: nao
mutacao:
  arquivo: `skills/rainforest-mind/SKILL.md`
  de: `3.000+ tokens`
  para: `3.000 tokens`
  bateria: `bash scripts/testa-conferir-invariantes.sh`
  fixture: `testa-conferir-invariantes.sh, secao "(1) MUTACAO: mover a frase \"3.000+ tokens\" para DEPOIS de <!-- detalhe --> no SKILL.md"`
pronto quando: com o arquivo migrado, as cinco entradas mantêm `regra` 10, 11, 12, 13 e 15 e mantêm `onde: ["skill","nucleo"]` — conferido por `node -e` lendo o JSON e comparando com os valores desta linha — e `node scripts/conferir-invariantes.cjs` continua saindo **0**; com `3.000+ tokens` trocado por `3.000 tokens` em `skills/rainforest-mind/SKILL.md` numa cópia de caixa de areia, sai **2** na regra 10 — provado por `bash scripts/testa-conferir-invariantes.sh` terminando em `falhou=0`

### 4. Registrar o openai-developers-for-claude no livro de repos [tipo: docs]
atende: D9
arquivos: `vigias/livro-de-repos.md`
depende de: nenhuma
paralela: sim
mutacao: n/a
  motivo: linha de tabela num documento de registro — não há comportamento a inverter. A falsificação dela é outra e está no critério: a sintaxe da célula é validada por peça marcada `sensor`, e o conteúdo tem de casar com o que foi medido no repo de terceiro.
pronto quando: com a linha nova na tabela "Avaliados", `node scripts/conferir-livro-de-repos.cjs` sai **0** e conta uma linha a mais que antes; e a linha registra, casando com o que foi medido em 2026-09-19, o caminho `Enxertar: enxerta`, o último push visto `2026-07-13`, a licença Apache-2.0 como fato e não como veredito, e a âncora `gate-do-p1-e-hook-nao-texto` — conferido lendo a célula contra a seção "Objetivo" do design, que traz os mesmos quatro dados

## Nota sobre a ordem

As tarefas 1 e 4 são paralelas entre si: tocam árvores disjuntas
(`scripts/` contra `vigias/`) e nenhuma lê o resultado da outra. As tarefas 2 e
3 dependem da 1 porque seus critérios rodam o checador com o formato novo — sem
a tarefa 1 na árvore, o `onde` ausente e o campo `tipo` são campo desconhecido,
não formato aceito.

A tarefa 3 vem depois da 2 na numeração, mas não depende dela: as duas dependem
só da 1. A ordem entre elas é indiferente e foi fixada para manter a leitura do
plano linear.
