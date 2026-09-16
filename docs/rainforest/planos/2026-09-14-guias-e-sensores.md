# Plano: Guias e sensores — cinco enxertos do Harness Engineering

Design: docs/rainforest/design/2026-09-14-guias-e-sensores.md

## O que não pode quebrar

- A portaria continua **fail-closed**: nenhuma mudança aqui pode fazer um agente
  passar onde hoje ele é negado. O campo `sensores` só acrescenta motivo de
  negação, nunca retira.
- `.rainforest/agentes.json` de um repo terceiro, escrito antes desta entrega e
  sem o campo `sensores`, continua sendo aceito (D13, D14).
- O payload de SessionStart não cresce: o sensor de idade e os avisos de teto só
  ocupam bytes quando disparam (D4).
- Nenhum estágio além de `verificar` passa a barrar (D3).
- A bateria inteira do repo continua verde: `bash scripts/testa-saude.sh`.

## Tarefas

### 1. Marca de categoria nas peças e conferidor que a exige [tipo: implementar]
atende: D2, D5, D10, D16, D19
arquivos: `scripts/conferir-categoria.cjs`, `scripts/testa-conferir-categoria.sh`, `hooks/codex-transfer-session-start.cjs`, `hooks/escada-subagente.cjs`, `hooks/ferramentas-consulta.cjs`, `hooks/foco-session-start.cjs`, `hooks/gate-agente-em-voo.cjs`, `hooks/gate-fechar-issue.cjs`, `hooks/gate-git-verificacao.cjs`, `hooks/gate-mensagem-commit.cjs`, `hooks/gate-publicacao-destino.cjs`, `hooks/gate-repo-alheio.cjs`, `hooks/gate-review-codex.cjs`, `hooks/gate-staging-total.cjs`, `hooks/gate-verificador-staged.cjs`, `hooks/gate-worktree.cjs`, `hooks/heartbeat.cjs`, `hooks/memoria-marca.cjs`, `hooks/memoria-session-start.cjs`, `hooks/portaria.cjs`, `scripts/observar.cjs`, `scripts/conferir-cobertura-fixtures.cjs`, `scripts/conferir-comparacao.cjs`, `scripts/conferir-divergencia.cjs`, `scripts/conferir-duplicacao.cjs`, `scripts/conferir-encoding.cjs`, `scripts/conferir-entrega.cjs`, `scripts/conferir-fluxo.cjs`, `scripts/conferir-invariantes.cjs`, `scripts/conferir-livro-de-repos.cjs`, `scripts/conferir-mutacao.cjs`, `scripts/conferir-ponte.cjs`, `scripts/conferir-publicacao.cjs`, `scripts/conferir-versao.cjs`, `vigias/ERROS.md`, `vigias/_comum.md`, `vigias/batedor-repos.md`, `vigias/jardineiro-ideias.md`, `vigias/livro-de-repos.md`, `vigias/revisao-bimestral.md`, `vigias/sentinela-foco.md`, `vigias/vigia-tickets.md`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `scripts/conferir-categoria.cjs`
  de: o `process.exit(1)` do ramo que reprova peça sem marca de categoria
  para: `process.exit(0)`
  bateria: `bash scripts/testa-conferir-categoria.sh`
  fixture: o caso que copia uma peça real para um diretório temporário, apaga a linha de marca e espera exit 1 com o caminho nomeado na saída
pronto quando: com o repositório real como entrada — os 19 hooks citados em `hooks/hooks.json`, os 13 `scripts/conferir-*.cjs` e os 8 `vigias/*.md` —, todo arquivo de peça carrega uma marca entre `guia`, `sensor` e `dado`, e apagar a marca de qualquer um deles reprova — provado por `node scripts/conferir-categoria.cjs; echo $?` devolvendo `0`, e por `bash scripts/testa-conferir-categoria.sh` devolvendo exit 0 com zero casos `skipped`

### 2. Agregado de SessionStart no orcamento.cjs [tipo: implementar]
atende: D7, D15
arquivos: `scripts/orcamento.cjs`, `scripts/testa-orcamento.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `scripts/orcamento.cjs`
  de: a leitura por regex de `MEMORIA_MAX_BYTES` em `hooks/lib/memoria-sessao.cjs`
  para: o literal `3000`
  bateria: `bash scripts/testa-orcamento.sh`
  fixture: o caso que edita `MEMORIA_MAX_BYTES` para outro valor numa cópia temporária da lib e exige que o teto agregado impresso acompanhe a edição
pronto quando: com os comandos de SessionStart reais declarados em `hooks/hooks.json` executados de fato, `scripts/orcamento.cjs` soma os bytes de `additionalContext` que eles emitem e compara com a soma dos tetos lidos das libs (`ORCAMENTO_BYTES` em `hooks/lib/contexto-sessao.cjs` mais `MEMORIA_MAX_BYTES` em `hooks/lib/memoria-sessao.cjs`), sem gravar arquivo nenhum — provado por `node scripts/orcamento.cjs --agregado; echo $?` devolvendo `0` e imprimindo uma linha com a soma medida e o teto agregado, e por `git status --porcelain` devolvendo vazio depois da execução

### 3. Cada hook de SessionStart trava o próprio teto [tipo: implementar]
atende: D4, D17
arquivos: `hooks/memoria-session-start.cjs`, `hooks/lib/memoria-sessao.cjs`, `hooks/testa-memoria-session-start.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `hooks/lib/memoria-sessao.cjs`
  de: a chamada que aplica o teto ao payload de memória antes de devolvê-lo
  para: o payload devolvido sem corte
  bateria: `bash hooks/testa-memoria-session-start.sh`
  fixture: o caso que injeta observações suficientes para passar de `MEMORIA_MAX_BYTES` e exige tanto o corte quanto o aviso no topo
pronto quando: com o JSON de SessionStart que o harness realmente envia no stdin (mesmo formato das fixtures já usadas por `hooks/testa-memoria-session-start.sh`) e uma base de memória cujo conteúdo excede `MEMORIA_MAX_BYTES`, o `additionalContext` emitido cabe no teto e traz no topo uma linha nomeando o que foi cortado — provado por `bash hooks/testa-memoria-session-start.sh` devolvendo exit 0 com zero casos `skipped`

### 4. Sensor de idade do FOCO.md na abertura [tipo: implementar]
atende: D11
arquivos: `hooks/lib/contexto-sessao.cjs`, `hooks/testa-contexto-sessao.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `hooks/lib/contexto-sessao.cjs`
  de: a comparação que dispara o aviso quando o último avanço passa de 7 dias
  para: uma comparação que nunca dispara
  bateria: `bash hooks/testa-contexto-sessao.sh`
  fixture: o caso que monta um FOCO.md cujo último avanço datado tem 8 dias e exige a linha de aviso no payload
pronto quando: com um `FOCO.md` no formato real (seção Ativo com linhas `- AAAA-MM-DD`, como o arquivo em uso) cujo avanço mais recente tem 8 dias, o payload da abertura traz uma linha nomeando o arquivo e os dias sem avanço; com avanço de 6 dias, o payload não ganha byte nenhum a mais — provado por `bash hooks/testa-contexto-sessao.sh` devolvendo exit 0 com zero casos `skipped`

### 5. Fechar `verificar` com ok exige sensor na evidência [tipo: implementar]
atende: D3, D6
arquivos: `scripts/estado.cjs`, `scripts/testa-estado.sh`
depende de: 1
paralela: nao
mutacao:
  arquivo: `scripts/estado.cjs`
  de: o ramo que recusa o fechamento de `verificar` quando a evidência não cita sensor
  para: o ramo que aceita
  bateria: `bash scripts/testa-estado.sh`
  fixture: o caso que fecha `verificar` com `comando` que não é sensor nem foi declarado e espera exit 2
pronto quando: com o mesmo `--json` que o fluxo já usa hoje para fechar (`{"comando": "...", "saida": "..."}`), `marcar --estagio verificar --status ok` aceita quando o `comando` casa com uma peça marcada `sensor` ou com um sensor externo declarado na tarefa do plano, e recusa com exit 2 quando não casa com nenhum dos dois; `executar`, `revisar` e os demais estágios continuam fechando como hoje, no máximo com aviso — provado por `bash scripts/testa-estado.sh` devolvendo exit 0 com zero casos `skipped`

### 6. Campo `sensores` no manifesto e portão na portaria [tipo: implementar]
atende: D9, D13, D14
arquivos: `.rainforest/agentes.padrao.json`, `hooks/portaria.cjs`, `hooks/testa-portaria-manifesto.cjs`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `hooks/portaria.cjs`
  de: o `negar()` do ramo em que o briefing exige sensor fora da lista declarada
  para: seguir para o allow
  bateria: `node hooks/testa-portaria-manifesto.cjs`
  fixture: o caso com manifesto que declara `sensores` e briefing pedindo um sensor de fora, esperando exit 2
pronto quando: com o payload de `PreToolUse` que o harness realmente envia para `Task`/`Agent`, agente cujo manifesto **não** traz `sensores` é despachado como hoje, agente que traz a lista é despachado quando o briefing só pede sensor dela, e é negado com exit 2 quando pede um de fora; manifesto com `versao: 1` e sem o campo novo continua aceito — provado por `node hooks/testa-portaria-manifesto.cjs` devolvendo exit 0 com zero casos `skipped`, e por `node scripts/conferir-encoding.cjs` devolvendo exit 0

### 7. Documentar a linha de declaração de sensor no briefing [tipo: docs]
atende: D18
arquivos: `skills/executar/SKILL.md`, `skills/plano/SKILL.md`
depende de: 5, 6
paralela: nao
mutacao: n/a
  motivo: a tarefa não muda comportamento — o parser vive em `hooks/portaria.cjs` (tarefa 6) e em `scripts/estado.cjs` (tarefa 5). O que ela pode errar é descrever forma diferente da que o código aceita, e isso se falsifica rodando o código contra a forma documentada.
pronto quando: a linha de declaração de sensor exatamente como o texto a escreve, copiada do SKILL.md e colada num briefing real, é aceita pelo parser do código — e uma linha na forma antiga, sem a declaração, produz a negação que o texto promete — provado por `node hooks/testa-portaria-manifesto.cjs` rodando um caso cujo briefing é montado a partir do trecho lido de `skills/executar/SKILL.md`, devolvendo exit 0

### 8. Medição: modelo do builder na régua [tipo: pesquisar]
atende: D1, D8, D12
arquivos: `relatorios/2026-09-14-modelo-no-builder-da-regua.md`
depende de: 1, 2, 3, 4, 5, 6, 7
paralela: nao
mutacao: n/a
  motivo: a tarefa produz medição, não comportamento — não há linha a inverter. A falsificação dela é a rastreabilidade: cada rodada relatada tem de ter commit correspondente na branch.
pronto quando: o relatório traz os dois braços (builder `haiku` e builder `sonnet`, crítico cego no mesmo modelo nos dois), o veredito binário do crítico por rodada e o número de rodadas até a vitória de cada braço, e cada rodada relatada corresponde a um commit real — provado por `git log --oneline --grep='regua: rodada'` listando uma linha para cada rodada citada no relatório, e por `node scripts/conferir-publicacao.cjs relatorios/2026-09-14-modelo-no-builder-da-regua.md` devolvendo exit 0

## Emenda de 2026-09-15 — depois do merge da main e da reprovação do `revisar`

O `revisar` reprovou com quatro achados (`docs/rainforest/estado/2026-09-14-guias-e-sensores.json`),
e três deles são de plano, não de código: um critério que a base mudou por baixo,
uma tarefa que existiu sem estar escrita, e uma peça nova que entrou pelo merge.
As emendas abaixo são o que destrava — justificar em prosa não destrava creep.

### 6. Campo `sensores` no manifesto e portão na portaria — CRITÉRIO SUBSTITUÍDO

atende: D9 e D13 **na redação da emenda de 2026-09-15 do design**, D14, D18
arquivos: `hooks/portaria.cjs`, `hooks/testa-portaria-manifesto.cjs`, `skills/executar/SKILL.md`, `skills/plano/SKILL.md`, `skills/rainforest-mind/references/regra-10-portaria.md`
depende de: nenhuma
paralela: nao (é a única tarefa desta rodada que toca a portaria)
mutacao:
  arquivo: `hooks/portaria.cjs`
  de: a escrita do campo que marca, no `despachos.jsonl`, que o briefing pediu sensor fora da lista declarada
  para: não escrever o campo (seguir para o allow sem registrar nada)
  bateria: `node hooks/testa-portaria-manifesto.cjs`
  fixture: o caso 7c — manifesto que declara `sensores` e briefing pedindo um de fora — que passa a exigir exit 0 **com** o campo no log; sem a escrita, o caso fica vermelho por ausência do campo, não por exit code
pronto quando: com o payload de `PreToolUse` que o harness realmente envia para `Task`/`Agent` — (a) agente cujo manifesto **não** traz `sensores` é despachado como hoje, sem campo novo no log; (b) agente que traz a lista e cujo briefing só pede sensor dela é despachado, e o log registra o sensor pedido; (c) agente que traz a lista e cujo briefing pede sensor **de fora** é **despachado com exit 0**, e o log carrega o campo que nomeia o sensor de fora; (d) linha `Sensor:` com valor ilegível é **despachada com exit 0**, e o log marca que a linha não foi lida; (e) `sensores` malformado no manifesto continua **negando com exit 2**, porque é forma de arquivo e não admissão — a mesma classe de `escreve` e `runtime` inválidos, que a #264 manteve negando; e (f) os três documentos citados em `arquivos:` descrevem (a)-(e) sem prometer negação que o código não faz — provado por `node hooks/testa-portaria-manifesto.cjs` devolvendo exit 0 com zero casos `skipped`, por `node scripts/conferir-encoding.cjs` devolvendo exit 0, e por `grep -n "exit 2" skills/executar/SKILL.md skills/plano/SKILL.md` não devolvendo nenhuma linha que descreva o caso (c) ou (d)

**Por que o critério anterior saiu:** ele exigia exit 2 no caso (c), e a `dd2e7ccd`
(issue #264) revogou essa classe de portão enquanto este fluxo estava aberto. O
critério velho não está errado por si — ele ficou incompatível com a base. Os
casos `7c`, `7c2` e `7g-fora` da bateria provam hoje a negação, verdes, e são
exatamente os que a nova redação inverte.

### 9. Fonte única de `cortarBytes` e varredura de `hooks/` no conferidor (Issue #259) [tipo: implementar]
atende: nenhuma decisão deste design — é a Issue #259, que entrou na branch durante o `executar`
arquivos: `hooks/lib/bytes.cjs`, `hooks/lib/memoria-sessao.cjs`, `hooks/lib/contexto-sessao.cjs`, `scripts/conferir-duplicacao.cjs`, `scripts/testa-conferir-duplicacao.sh`, `scripts/exporta-hooks-sessao-start.cjs`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `scripts/conferir-duplicacao.cjs`
  de: a inclusão de `hooks/` (e `hooks/lib/`) na varredura de `--funcoes`
  para: varrer só `scripts/`
  bateria: `bash scripts/testa-conferir-duplicacao.sh`
  fixture: o caso 6, que planta função duplicada dentro de `hooks/lib/` e espera que o conferidor a encontre
pronto quando: `cortarBytes` existe num arquivo só e é importado pelos dois consumidores, o `conferir-duplicacao --funcoes` acha duplicata plantada dentro de `hooks/lib/`, e `scripts/orcamento.cjs` consome `executarHooksSessionStart` exportada em vez de reimplementá-la — provado por `bash scripts/testa-conferir-duplicacao.sh`, `bash scripts/testa-orcamento.sh` e `bash hooks/testa-memoria-session-start.sh`, os três devolvendo exit 0 com zero casos `skipped`

**Por que esta tarefa é retroativa:** o trabalho foi feito (commits `0ef8cc97`,
`0730206d`, `ae681310`) e roda limpo, mas nasceu de uma Issue que apareceu no meio
do `executar` e nunca entrou no plano. Sem esta entrada, três arquivos do diff não
casam com `arquivos:` de tarefa nenhuma — é creep pela definição do `revisar`, e a
única saída é escrever a tarefa que faltava. A dependência que o plano não previu é
concreta e vale registrar: a tarefa 2 (`scripts/orcamento.cjs:112,121`) **não
poderia** ter sido implementada como foi sem extrair `executarHooksSessionStart` de
`scripts/exporta-hooks-sessao-start.cjs`.

### 1. Marca de categoria — ADENDO

A peça `hooks/titulo-sessao-end.cjs` entra na lista de `arquivos:` da tarefa 1, e a
contagem do critério passa de 41 para 42 peças (20 hooks), distribuição
14 guia / 25 sensor / 3 dado.

**Por que:** o hook chegou pelo merge da main (PR #274, commit `13b552c6`), depois
do `executar` ter fechado, sem marca `@categoria` — e o conferidor da tarefa 1
varre `hooks/hooks.json` dinamicamente, então a peça nova reprovou a bateria no
head. Isso não é defeito da tarefa 1: é ela funcionando, e pegando a primeira peça
que entrou no repo depois que a regra passou a existir. Classificada `sensor` pelo
precedente que o próprio conferidor documenta — `SessionEnd` fica do lado sensor,
como `heartbeat.cjs` e `memoria-marca.cjs`.

**Fica dito, e não entra nesta rodada:** o total é literal na bateria, então toda
peça nova que entrar pelo merge vai deixá-la vermelha até alguém atualizar o
número. É o argumento da D5 ("lista central diverge do diretório em silêncio")
apontado para o teste — mas trocar isso por uma contagem derivada é mudança de
escopo, e vira ideia plantada, não tarefa desta rodada.

## Emenda de 2026-09-16 — as baterias que as regras novas invalidaram

O `revisar` da rodada 2 aprovou o mérito e reprovou por rastreabilidade: sete
arquivos de bateria foram tocados para acompanhar regra nova desta branch, e
nenhum deles caía no `arquivos:` de tarefa alguma. Nenhum é regressão — o diff de
cada um só acrescenta campo ou linha de cópia, nunca remove asserção —, mas a
auditoria por `arquivos:` não os enxergava. A emenda de 2026-09-15 já tinha
aberto a Tarefa 9 por essa mesma razão e fechou três dos oito arquivos da mesma
causa raiz; estes são os que ficaram de fora.

### 5. Fechar `verificar` com ok exige sensor na evidência — `arquivos:` AMPLIADO

acrescenta: `hooks/testa-ledger-fluxos.sh`, `scripts/testa-portoes-gate.sh`, `scripts/testa-recibo-fechar.sh`
pronto quando (acréscimo ao critério existente): as três baterias acima, que fechavam `verificar` com `ok` sem citar sensor, passam a declarar `sensor_externo` com valor que aparece dentro de `comando` — e as três devolvem exit 0, provado por `bash hooks/testa-ledger-fluxos.sh`, `bash scripts/testa-portoes-gate.sh` e `bash scripts/testa-recibo-fechar.sh`

**Por que não é afrouxamento:** o conserto é a bateria declarar o que a regra
nova pede, não a regra parar de pedir. Nenhuma linha de `scripts/estado.cjs` foi
tocada para isto, e a recusa continua load-bearing — provada por mutação ao vivo
na seção 27 de `scripts/testa-estado.sh`.

### 9. Fonte única de `cortarBytes` — `arquivos:` AMPLIADO

acrescenta: `scripts/testa-backup-estado.sh`, `scripts/testa-ponte.sh`, `scripts/testa-ponte-entrevista.sh`, `scripts/testa-registrar-erro.sh`
pronto quando (acréscimo ao critério existente): as quatro baterias acima, que montam a caixa de teste copiando `hooks/lib/` arquivo a arquivo, passam a copiar também o `hooks/lib/bytes.cjs` de que `contexto-sessao.cjs` passou a depender — e as quatro devolvem exit 0

**O preço da extração, que não estava escrito em lugar nenhum:** extrair função
para arquivo novo cobra de toda caixa de teste que copia lib seletivamente. O
repo tem **nove** baterias nesse padrão; quatro quebraram agora, e as outras
cinco só não exercitam o caminho do `cortarBytes` ainda. Quem mexer em
`hooks/lib/` de novo deve conferir a lista antes:
`grep -rl "hooks/lib/contexto-sessao.cjs\|hooks/lib/memoria-sessao.cjs" scripts/testa-*.sh hooks/testa-*.sh`.
