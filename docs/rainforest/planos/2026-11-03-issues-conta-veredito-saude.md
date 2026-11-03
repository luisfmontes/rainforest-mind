# Plano: Issues #642 e #641, e o falso verde do /saude nos vigias

Design: docs/rainforest/design/2026-11-03-issues-conta-veredito-saude.md

## O que não pode quebrar
- `testa-conta.sh`: os casos #585 (órfão ao voltar para casa, arquivamento que falha, aviso uma vez por hora) seguem verdes.
- `testa-veredito-revisor.sh`: briefing sem `Repo:` se comporta como hoje, inclusive os stderr `nao encontrado` e `ambiguo`.
- `/saude`: tarefa `Ready` com próxima execução segue `ok`; gatilho vencido segue `alerta`; sem PowerShell segue o `aviso` de hoje.
- `skills/revisar/SKILL.md` fica abaixo de 16 KB.
- O repo é público: nenhum caminho desta máquina em código, teste ou fixture.

## Tarefas

### 1. Órfão do estacionado detectado pelo estado [tipo: implementar]
atende: D1
arquivos: `scripts/conta.cjs`, `scripts/testa-conta.sh`
depende de: nenhuma
busca:
- repo | rg "orfaoPendente|arquivarOrfao|retentarOrfao" scripts | scripts/conta.cjs já arquiva e reaproveita retentarOrfao; só a condição muda
- livro | pulado: conserto interno de uma condição
desfecho: estender
prova-na-base: verde — o caso novo nasce na bateria desta tarefa; a bateria da base não o contém, e a catraca da mutação mede o vermelho
mutacao:
  arquivo: `scripts/conta.cjs`
  de: `if (sobTrava && info.conta === info.casa && estacionadoPronto(c, P)) retentarOrfao(c, P, info.conta);`
  para: `if (sobTrava && info.conta === info.casa && false) retentarOrfao(c, P, info.conta);`
  bateria: `bash scripts/testa-conta.sh`
  fixture: `testa-conta.sh, casos "#642"`
pronto quando: com a pasta em casa, login da casa confirmado pelo servidor, `estacionado-trabalho.json` presente e nenhum evento `reconciliado` no histórico, `conta.cjs vigiar` deixa o arquivo como `estacionado-trabalho.orfao-<carimbo>.json` de mesmo conteúdo, e `conta.cjs trocar pessoal --pasta trabalho` sai 0 em vez de `saida_ocupada` — provado por `bash scripts/testa-conta.sh` imprimindo as linhas `ok   #642:` e `falhou: 0`.

### 2. Linha Repo: no briefing do revisor [tipo: implementar]
atende: D2, D3, D4
arquivos: `hooks/veredito-revisor.cjs`, `scripts/lib/primeiro-prompt-jsonl.cjs`, `scripts/estado.cjs`, `hooks/testa-veredito-revisor.sh`, `skills/revisar/SKILL.md`
depende de: nenhuma
busca:
- repo | rg "extrairSlug|raizComEstadoDoSlug" hooks scripts | extrairSlug em scripts/lib/primeiro-prompt-jsonl.cjs e a busca em hooks/veredito-revisor.cjs são o molde
- livro | pulado: conserto interno do hook
desfecho: estender
prova-na-base: verde — o caso novo nasce na bateria desta tarefa; a bateria da base não o contém, e a catraca da mutação mede o vermelho
mutacao:
  arquivo: `hooks/veredito-revisor.cjs`
  de: `const raizEstado = (raizDeclarada && raizComEstadoDoSlug(raizDeclarada, slug))`
  para: `const raizEstado = (false && raizComEstadoDoSlug(raizDeclarada, slug))`
  bateria: `bash hooks/testa-veredito-revisor.sh`
  fixture: `testa-veredito-revisor.sh, casos "#641"`
pronto quando: com o payload real do `SubagentStop` (cwd no repositório A, transcrito com `Slug: <s>` e `Repo: <B>`) e o estado só em B, o veredito é gravado em `revisar.vereditos` de B e A fica sem arquivo; sem o slug em lugar nenhum, o stderr nomeia as raízes procuradas; e a recusa do `marcar revisar` sem veredito cita `Repo:` — provado por `bash hooks/testa-veredito-revisor.sh` imprimindo as linhas `ok    (#641)` e `0 falha(s)`, com `bash scripts/testa-teto-skills.sh`, `bash hooks/testa-abertura-mod-config.sh` e `bash scripts/testa-plugin-codex.sh` saindo 0.

### 3. /saude lê o estado das tarefas de vigia [tipo: implementar]
atende: D5
arquivos: `scripts/saude.cjs`, `scripts/testa-saude-vigias.sh`
depende de: nenhuma
busca:
- repo | rg "RFM_CONTA_SCHTASKS|tarefasDeVigia" scripts | RFM_CONTA_SCHTASKS em conta.cjs é o molde do executável falso, só com RFM_TEST=1
- livro | pulado: conserto interno do checador
desfecho: estender
prova: `bash scripts/testa-saude-vigias.sh`
mutacao:
  arquivo: `scripts/saude.cjs`
  de: `const desabilitadas = tarefas.filter((t) => t.estado === 'Disabled');`
  para: `const desabilitadas = [];`
  bateria: `bash scripts/testa-saude-vigias.sh`
  fixture: `testa-saude-vigias.sh, caso "desabilitada com proxima preenchida"`
pronto quando: com a consulta devolvendo tarefa `Disabled` e `NextRunTime` preenchido, o `/saude` imprime `aviso vigias` com o nome dela e o remédio, e nunca `todas com proxima execucao` — provado por `bash scripts/testa-saude-vigias.sh` saindo 0 e, nesta máquina, por `node scripts/saude.cjs` imprimindo `aviso vigias` com as quatro tarefas desabilitadas.

### 4. Versão, CHANGELOG, README e .gitignore [tipo: docs]
atende: D6, D7
arquivos: `.gitignore`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `CHANGELOG.md`, `README.md`
depende de: 1, 2, 3
mutacao: n/a
  motivo: versão, notas e padrão de ignore não têm comportamento a inverter; o critério confere coerência entre os arquivos e o efeito no git
pronto quando: com o checkout real, `git check-ignore -v .claude/fixtures/qualquer` casa a linha nova do `.gitignore`, os dois `plugin.json`, o README e a entrada nova do CHANGELOG dizem a mesma versão 2.3.2, e a entrada do CHANGELOG descreve as três correções de D1, D2 e D5 do ponto de vista de quem usa — provado por `git check-ignore -v .claude/fixtures/qualquer` e `node scripts/conferir-versao.cjs` saindo 0.
