# Plano — acoplar o ponytail de verdade

**Slug:** `aclopar-ponytail` · **Design:** `docs/rainforest/design/aclopar-ponytail.md`
**Base:** `origin/main` @ `39b012c` · **Branch:** `fluxo/aclopar-ponytail`

Sete tarefas, sete decisões. **Fan-out em duas ondas:** T1, T2, T4 e T7 são
independentes e vão juntas; T3, T5 e T6 dependem de T1 (as três tocam o texto
injetado ou o hook que o injeta) e vão na segunda onda.

## Levantamentos que mudaram o plano

Três fatos medidos depois do design, e os três encolhem trabalho:

1. **O padrão de D2 já existe neste repo, duas vezes.** `scripts/testa-perfil.sh`
   confere que o bloco de perfil de trabalho não diverge entre a fonte e os nove
   `agents/*.md`, e o cabeçalho dele aponta o precedente: `testa-versao.sh`, que
   nasceu porque *"em 2026-08-14 a versão do plugin estava em dois lugares,
   divergiu por uma entrega inteira, e cinco revisões independentes passaram por
   cima sem ver"*. T2 **não inventa desenho** — copia o desses dois e acrescenta
   a única checagem que nenhum dos dois faz: a frase sobrevive ao
   `extrairNucleo` e chega na sessão.

2. **`scripts/medir-skill.cjs` já importa o motor real** (`filtrarRegras`,
   `extrairNucleo`) de `hooks/lib/contexto-sessao.cjs`. T2 nasce ao lado dele,
   pelo mesmo `require` — não reimplementa parser.

3. **`hooks/lib/cli-externo.cjs` (`rodarCli`) já chama CLIs de outros modelos**,
   e é o que o `conselho.cjs` e o `segunda-opiniao.cjs` usam. T5 não precisa de
   promptfoo, de chave nova nem de infra de benchmark.

**Restrição que vale para todas:** o repo é público. **Nenhum caminho desta
máquina** em código, teste ou fixture — os testes que precisam de raiz usam
`RFM_ROOT`/`RFM_ESTADO_ROOT` apontando para pasta temporária, nunca um caminho
absoluto sob a home do usuário.

---

### 1. Hook SubagentStart injeta a escada [tipo: implementar]
atende: D1
arquivos: `hooks/escada-subagente.cjs`, `hooks/lib/escada.cjs`, `hooks/hooks.json`, `skills/modo-dev/SKILL.md`, `hooks/testa-escada-subagente.sh`
depende de: nenhuma
paralelizavel: sim

Hook novo em `SubagentStart` que injeta a escada em todos os subagentes.

**A forma da saída não é escolha.** No Claude nativo, `SessionStart` aceita
stdout cru, mas `SubagentStart` **exige**
`{"hookSpecificOutput":{"hookEventName":"SubagentStart","additionalContext":"..."}}`
— texto cru é descartado em silêncio. O fato vem de `ponytail-runtime.js`
(*"SubagentStart needs the hookSpecificOutput JSON form or the context is
dropped"*) e é o mesmo modo de falha já documentado em
`hooks/foco-session-start.cjs`, onde 32 KB de texto cru viraram 2,2 KB.

**O texto é extraído do `skills/modo-dev/SKILL.md`, nunca duplicado** —
`hooks/lib/escada.cjs` faz a extração, e é a fronteira que T2 depois cobre. O
`modo-dev` é editado nesta tarefa para: recuperar os dois degraus perdidos na
compressão original (o "cabe em uma linha?" e o formato de saída
`[código] → pulei: [X], entra quando [Y]`), e ganhar marcadores de seção
estáveis para a extração.

**Critério de pronto:**
- `bash hooks/testa-escada-subagente.sh` → exit 0.
- Caso nomeado na saída: o stdout do hook **parseia como JSON** e tem
  `hookSpecificOutput.hookEventName === "SubagentStart"` e um
  `additionalContext` não-vazio contendo os sete degraus.
- Caso nomeado: o texto injetado **casa com o `modo-dev/SKILL.md`** — sabotar a
  escada no SKILL.md muda o que o hook emite (prova de que extrai, não duplica).
- `hooks/hooks.json` continua JSON válido e registra o evento
  (`node -e "JSON.parse(require('fs').readFileSync('hooks/hooks.json','utf8'))"`).

mutacao:
  arquivo: `hooks/escada-subagente.cjs`
  de: a escrita em `hookSpecificOutput` JSON
  para: `process.stdout.write(texto)` cru, como o SessionStart faz
  bateria: `bash hooks/testa-escada-subagente.sh`

---

### 2. Invariantes de conteúdo das 17 regras [tipo: implementar]
atende: D2
arquivos: `skills/rainforest-mind/invariantes.json`, `scripts/conferir-invariantes.cjs`, `scripts/testa-conferir-invariantes.sh`, `scripts/portoes.cjs`
depende de: nenhuma
paralelizavel: sim

Copie o desenho de `scripts/testa-perfil.sh` e `scripts/testa-versao.sh` — o
repo já os tem, e o cabeçalho do primeiro explica por quê. Acrescente a
checagem que falta nos dois.

`invariantes.json`: lista de `{regra, frase, onde}`, onde `onde` é um
subconjunto de `["skill","referencia","nucleo"]`. Sementes, todas load-bearing:
`3.000` (regra 10), `exit ≠ 0 nunca é sucesso` (12), ``nunca a `main``` (11),
`printenv NOME` (15), ``pelo `ideias.cjs plantar`, nunca à mão`` (13).

`conferir-invariantes.cjs` importa `filtrarRegras` e `extrairNucleo` de
`hooks/lib/contexto-sessao.cjs` **pelo mesmo `require` que
`scripts/medir-skill.cjs` já usa** — sem parser paralelo, pelo motivo escrito em
`hooks/lib/estagio-ativo.cjs`: cópia sem teste ao lado do original é divergência
esperando data.

Três checagens por invariante:
1. a frase está no `skills/rainforest-mind/SKILL.md`;
2. a frase está na `skills/rainforest-mind/references/regra-<n>.md`;
3. **a frase sobrevive a `extrairNucleo(filtrarRegras(skill))`** — chega na
   sessão. É a checagem que não existe hoje: `extrairNucleo` corta cada regra na
   marca `↳`, então uma cláusula empurrada para depois da marca some da injeção
   sem nada acusar.

Entra em `scripts/portoes.cjs` para valer no CI.

**Critério de pronto:**
- `bash scripts/testa-conferir-invariantes.sh` → exit 0.
- `node scripts/conferir-invariantes.cjs` no repo íntegro → **exit 0**, e a
  saída nomeia quantos invariantes conferiu.
- Caso VERMELHO nomeado na saída: mover uma frase de invariante para **depois**
  da marca `↳` no SKILL.md (sem apagá-la) → exit ≠ 0, com mensagem dizendo que
  a frase existe no arquivo mas **não chega ao núcleo**. Este caso é o ponto da
  tarefa: sem ele, a bateria só repete o `testa-perfil.sh`.
- Caso VERMELHO nomeado: apagar a frase da `references/regra-<n>.md` → exit ≠ 0.

mutacao:
  arquivo: `scripts/conferir-invariantes.cjs`
  de: a terceira checagem (frase sobrevive ao `extrairNucleo`)
  para: sempre considerar a frase presente no núcleo
  bateria: `bash scripts/testa-conferir-invariantes.sh`

---

### 3. Convenção `atalho:` e coletor de ledger [tipo: implementar]
atende: D3
arquivos: `skills/modo-dev/SKILL.md`, `scripts/atalhos.cjs`, `scripts/testa-atalhos.sh`, `hooks/heartbeat.cjs`
depende de: 1
paralelizavel: nao

Serial após T1 porque as duas editam `skills/modo-dev/SKILL.md`.

Seção nova no `modo-dev` documentando o marcador
`atalho: <teto>, <caminho de upgrade>` — simplificação deliberada que corta um
canto real nomeia o teto e o gatilho de volta. Migrar a única ocorrência
existente (`hooks/heartbeat.cjs:75`, hoje `ponytail:`).

`scripts/atalhos.cjs` varre o repo (pulando `.git`, `node_modules`,
`.claude/worktrees`), agrupa por arquivo, e emite uma linha por marcador:
`<arquivo>:<linha>, <o que foi simplificado>. teto: <limite>. volta quando: <gatilho>.`
Fecha com `<N> marcadores, <M> sem gatilho.`

**A tag `sem-gatilho` é o ponto da tarefa**, não enfeite: marcador que não
nomeia condição de retorno é o que apodrece em silêncio, e é o que separa
adiamento de descarte. O regex aceita `atalho:` e `ponytail:` por alternância —
custo zero e não quebra o que já está escrito.

**Critério de pronto:**
- `bash scripts/testa-atalhos.sh` → exit 0.
- `node scripts/atalhos.cjs` no repo real → lista o marcador do `heartbeat.cjs`
  com teto e gatilho preenchidos, e a contagem final bate com
  `grep -rcE '(#|//) ?(atalho|ponytail):'`.
- Caso nomeado na saída: fixture com marcador **sem** caminho de upgrade sai
  taggeado `sem-gatilho` e entra na contagem `M`.

mutacao:
  arquivo: `scripts/atalhos.cjs`
  de: a marcação `sem-gatilho` para marcador sem caminho de upgrade
  para: nunca marcar (todo marcador conta como tendo gatilho)
  bateria: `bash scripts/testa-atalhos.sh`

---

### 4. Skill `enxugar` — revisão contra excesso [tipo: implementar]
atende: D4
arquivos: `skills/enxugar/SKILL.md`, `scripts/testa-enxugar-estrutura.sh`
depende de: nenhuma
paralelizavel: sim

Uma skill, dois modos (diff e repo inteiro), tags fechadas: `apagar:`,
`stdlib:`, `nativo:`, `yagni:`, `encolher:`. Uma linha por achado no formato
`<arquivo>:L<n>: <tag> <o que cortar>. <o que entra no lugar>.`, ranqueado pelo
maior corte primeiro, fechando com `líquido: -N linhas`. Nada a cortar:
`Já está enxuto.`

**A fronteira é o que impede a skill de virar um segundo `revisar`**, e vai
escrita: correção, segurança e performance estão **fora de escopo** e vão para
o `revisar` e o `auditor-de-seguranca`; o mínimo de um check executável (regra
do próprio `modo-dev`) **nunca** é marcado para deleção; a skill lista e não
aplica.

`scripts/testa-enxugar-estrutura.sh` confere o que é falsificável num arquivo de
prosa: frontmatter válido, `name` casando com a pasta, nome não colidindo com
skill existente (`poda` está ocupado por `scripts/poda.cjs`, que é proxy HTTP), e
as cinco tags presentes.

**Critério de pronto:**
- `bash scripts/testa-enxugar-estrutura.sh` → exit 0.
- Caso nomeado: `name:` do frontmatter é `enxugar` e existe `skills/enxugar/`.
- Caso VERMELHO nomeado: apagar uma das cinco tags do SKILL.md → exit ≠ 0.

mutacao:
  arquivo: `skills/enxugar/SKILL.md`
  de: a tag `encolher:` na lista de tags
  para: removida do arquivo
  bateria: `bash scripts/testa-enxugar-estrutura.sh`

---

### 5. Régua medida da escada, com fronteira de honestidade [tipo: implementar]
atende: D5
arquivos: `scripts/medir-escada.sh`, `scripts/fixtures/escada/`, `scripts/testa-medir-escada.sh`, `skills/regua/SKILL.md`, `scripts/dubliador-llm-codigo-ok.cjs`
depende de: 1
paralelizavel: nao

Serial após T1: mede o efeito da injeção que T1 cria.

`medir-escada.sh` roda um conjunto fixo de tarefas pequenas contra o mesmo CLI
**com e sem** o `additionalContext` de T1, e mede duas coisas por tarefa:
linhas de código produzidas, e um **gate de correção** — um `assert` que falha
se o código estiver errado.

**O gate não é opcional.** Sem ele "menos linhas" não significa nada; é o ponto
do `benchmarks/correctness.js` do ponytail (*"proves 'less code' is not 'broken
code'"*). Uma resposta errada é errada por menos linhas que tenha.

Usa `hooks/lib/cli-externo.cjs` (`rodarCli`). Quais CLIs entram sai da config do
`/setup` desta máquina, lida em runtime — sem CLI declarado, o script **pula e
diz que pulou**, nunca inventa número.

A **fronteira de honestidade** vai escrita em `skills/regua/SKILL.md`: nunca
imprimir número de economia estimado sobre um repo vivo, porque a versão não
construída nunca foi escrita e não há baseline de onde subtrair. Número só sai
da bateria (baseline medido) ou do ledger de T3 (contagem).

**Critério de pronto:**
- `bash scripts/testa-medir-escada.sh` → exit 0, com dublê de CLI (o repo já tem
  o padrão: `scripts/dubliador-llm-ok.cjs` e `dubliador-llm-fail.cjs`).
- Caso nomeado: dublê devolvendo código **errado e curto** → o script reporta a
  tarefa como **reprovada no gate**, e ela não conta como ganho de linhas.
- Caso nomeado: sem nenhum CLI declarado na config → exit 0 dizendo
  explicitamente que pulou, sem imprimir número.
- `grep` em `skills/regua/SKILL.md` acha a fronteira de honestidade escrita.

mutacao:
  arquivo: `scripts/medir-escada.sh`
  de: o gate de correção que reprova código errado
  para: contar toda resposta como correta
  bateria: `bash scripts/testa-medir-escada.sh`

---

### 6. Dial de intensidade e mostrador [tipo: implementar]
atende: D6
arquivos: `hooks/escada-subagente.cjs`, `hooks/lib/escada.cjs`, `statusline/`, `scripts/setup.cjs`, `hooks/testa-escada-subagente.sh`
depende de: 1
paralelizavel: nao

Serial após T1: mesmo hook, mesma lib.

Três níveis lidos de `config.json` da pasta de dados, filtrando o texto que o
hook injeta. Nível ausente ou inválido cai no padrão, nunca em erro — o hook é
best-effort e não pode derrubar spawn de subagente. Nível ativo aparece na
statusline (`statusline/`, `scripts/instalar-statusline.sh`).

**O dial governa a escada, não as 17 regras** — elas já têm dimensionamento
medido e testado (`montarContexto`, `TETOS`, `testa-medir-injecao.sh`).

**Critério de pronto:**
- `bash hooks/testa-escada-subagente.sh` → exit 0, com **mais casos** que ao fim
  de T1 (cole os dois números).
- Caso nomeado por nível: o `additionalContext` emitido no nível mais enxuto é
  **estritamente menor em bytes** que no mais completo, e o mais enxuto ainda
  contém as carve-outs de segurança (onde a escada não desce).
- Caso nomeado: `config.json` com nível inválido → hook emite o padrão e sai 0.
- Statusline mostra o nível ativo (cole a linha renderizada).

mutacao:
  arquivo: `hooks/lib/escada.cjs`
  de: o filtro por nível de intensidade
  para: devolver sempre o texto completo, ignorando o nível
  bateria: `bash hooks/testa-escada-subagente.sh`

---

### 7. Crédito do ponytail no README [tipo: doc]
atende: D7
arquivos: `README.md`
depende de: nenhuma
paralelizavel: sim

Duas linhas na seção **Créditos**, no formato das que já estão lá (projeto,
licença, o que foi acoplado e onde mora): `dietrichgebert/ponytail` (MIT) — a
escada do `modo-dev`, a convenção de marcador de T3, a fronteira de escopo do
`enxugar` de T4, e o hook de `SubagentStart` de T1; e `superpowers`, também
citado como fonte no `modo-dev/SKILL.md:9-10` e ausente da lista.

O `modo-dev/SKILL.md:9-10` promete "procedência item a item no README" e hoje a
promessa é falsa para os dois.

**Critério de pronto:**
- `grep -ci "ponytail" README.md` ≥ 1 e a linha está dentro da seção
  `## Créditos` (cole a linha).
- `grep -ci "superpowers" README.md` ≥ 1.
- Cada fonte citada em `skills/modo-dev/SKILL.md:9-10` aparece no README —
  a promessa "procedência item a item" passa a ser verdadeira.

mutacao: n/a
  motivo: tarefa de atribuição em documento; não há comportamento executável a
  inverter. O critério é verificável por `grep` e está escrito acima, e o gate
  de cobertura do próprio fluxo confere que a tarefa existe para D7.

---

### 8. Checador de creep enxerga pasta e portão datado [tipo: implementar]
atende: D8
arquivos: `scripts/conferir-fluxo.cjs`, `scripts/testa-conferir-fluxo.sh`
depende de: 5
paralelizavel: nao

Serial: o defeito só apareceu ao tentar fechar o `revisar` deste fluxo, com os
arquivos de T5 e T6 no diff.

Dois consertos em `conferir-fluxo.cjs`:

1. **Barra no fim é pasta.** `globMatches` ganha um caso antes da comparação
   literal: padrão terminado em `/` casa por prefixo. `scripts/fixtures/escada/`
   passa a cobrir os dez arquivos abaixo dela, que é o que o plano sempre quis
   dizer.
2. **Portão datado é isento.** A isenção vira
   `docs/rainforest/portoes/*<slug>.md`. O `*` de `globMatches` não cruza `/`,
   então continua preso à pasta de portões e casa só o prefixo de data.

**Critério de pronto:**
- `bash scripts/testa-conferir-fluxo.sh` verde, com dois casos novos: um que
  prova que `pasta/` cobre arquivo abaixo dela, outro que prova que o portão
  datado do slug não conta como creep.
- `node scripts/estado.cjs marcar --slug aclopar-ponytail --estagio revisar
  --status ok` deixa de recusar por creep (cole a saída).

mutacao:
  arquivo: `scripts/conferir-fluxo.cjs`
  de: return arquivo.startsWith(glob);
  para: return false;
  bateria: `bash scripts/testa-conferir-fluxo.sh`

---

## Ordem de execução

**Onda 1 (paralela):** T1, T2, T4, T7.
**Onda 2 (após T1):** T3, T5, T6 — as três tocam o hook ou o `modo-dev`.

Cada tarefa vai para um worktree próprio a partir de `39b012c` (regra 11), e a
volta passa por `node scripts/conferir-entrega.cjs` antes de qualquer aceite
(regra 12): **`entrada(s) nao commitada(s)` é reprovação, não aviso**.
