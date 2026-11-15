# Plano: Rodada 13 — fechar pós-squash (#714), busca: com continuação (#709), revisor que roda código do projeto (#697) e preexistente que vira Issue

Design: docs/rainforest/design/2026-11-15-zerar-issues-13.md

## O que não pode quebrar
- Na branch do fluxo (HEAD contém o `verificar.head`), `exigir fechar` e `marcar fechar ok` medem exatamente como na base: os casos (i), (q) e (s) de `scripts/testa-estado-reabrir.sh` seguem verdes.
- Código commitado depois do `verificar ok` e mergeado continua recusando o `marcar fechar ok`, também pelo caminho do PR mergeado.
- Plano com todos os itens de `busca:` numa linha só continua aceito pelo `conferir-busca` (as seções existentes de `scripts/testa-conferir-busca.sh` seguem verdes).
- Achado `[preexistente]` continua não reprovando sozinho; a marca recusada pelo diff continua bloqueando como hoje.

## Tarefas

### 1. `marcar fechar ok` fora da branch do fluxo compara com a ponta do PR mergeado [tipo: implementar]
atende: D1
arquivos: `scripts/estado.cjs`, `scripts/testa-estado-reabrir.sh`
depende de: nenhuma
paralela: sim
busca:
- repo | rg -n "headRefOid|pr view" scripts/estado.cjs scripts/publicar-branch.cjs | o publicar-branch.cjs consulta o state do PR no confirmarMerge; o estado.cjs não consulta PR nenhum
- catalogo | listar --raiz scripts | estendo a função arquivosDeCodigoDesde de scripts/estado.cjs:750 com o parâmetro do alvo, e a função recusaCodigoDepois de scripts/estado.cjs:845
desfecho: estender
mutacao:
  arquivo: `scripts/estado.cjs`
  de: const alvoFechar = alvoDoFechar(estado, extra, refCodigo.head);
  para: const alvoFechar = 'HEAD';
  bateria: `bash scripts/testa-estado-reabrir.sh`
  timeout: `1200000`
  fixture: testa-estado-reabrir.sh, seção "(t) #714: marcar fechar ok numa branch nova da main depois do squash compara com a ponta do PR"
prova-na-base: verde — o cenário exige repositório com PR squash-mergeado e um gh falso no PATH; quem o monta é a seção nova da bateria
Implementação: `arquivosDeCodigoDesde(head, slug, estado, alvo = 'HEAD')` troca o `'HEAD'` fixo do diff, do `merge-base` e do `ls-tree` por `alvo`. O `git status` (sujos) só entra quando `alvo === 'HEAD'`. `recusaCodigoDepois` ganha o mesmo parâmetro e o repassa. No bloco do `marcar` que monta `refCodigo`, para `estagio === 'fechar'` entra exatamente a linha do `de:` acima. Ela usa uma função nova `alvoDoFechar(estado, extra, head)` com estas saídas:
- `'HEAD'` quando `git merge-base --is-ancestor <head> HEAD` sai 0, o caso da branch do fluxo. Nada muda nele.
- Quando não é ancestral e há `pr` (de `extra.pr`, senão de `estado.fechar.pr`): roda `gh pr view <pr> --json state,headRefOid` com `caminhoExecutavel('gh')`. Com `state` `MERGED`, garante o commit local (`git cat-file -e <oid>`; se faltar, `git fetch origin pull/<pr>/head`) e devolve o `headRefOid`.
- Quando não é ancestral e não há `pr`, ou o PR não está `MERGED`: devolve `{ recusa: <texto> }`. O texto diz que o HEAD não contém o código verificado (`<head curto>`) e manda rodar o `marcar` na branch do fluxo ou passar `"pr":<n>` do PR mergeado no `--json`. Não contém "Reabra o executar".
- `gh` ausente, sem auth ou sem rede: devolve `{ ambiente: <texto> }`, que o chamador transforma em `process.exit(69)` com `nao-verificavel: <texto>` no stderr.

A recusa de código mudado (`recusaCodigoDepois`) roda contra o alvo devolvido. O `exigir fechar` não muda. Na bateria, a seção nova (t) monta: um repo com `origin` bare; a branch `fluxo/x` com o verificar gravado em A; um `git merge` de uma `main` que mudou o `CHANGELOG.md`; o squash na `main`; uma branch nova da `main` com o estado; e um `gh` falso em caminho POSIX conferido por `command -v gh`, que imprime `{"state":"MERGED","headRefOid":"<ponta de fluxo/x>"}`. Nada do teste chama o `gh` real.
pronto quando: com `bash scripts/testa-estado-reabrir.sh`, a seção (t) mostra:
- (t1) `marcar --estagio fechar --status ok --json '{"acao":"merge","pr":7}'` na branch nova sai 0;
- (t2) o mesmo comando, com um `src/a.js` diferente entre A e a ponta do PR, sai 2 e nomeia `src/a.js`;
- (t3) sem `pr` no `--json` e sem `estado.fechar.pr`, sai 2 (comparação contra o HEAD, como na base), e o stderr contém a dica `"pr"` do PR mergeado;
- (t4) com o `gh` falso respondendo `"state":"OPEN"`, sai 2 pelo mesmo caminho do (t3);
- (t5) com o `gh` falso saindo 4, sai 69;
- (t6) emenda da revisão 1: na branch do fluxo rebaseada sobre a `main` depois do `verificar`, com `--json '{"acao":"pr","pr":7}'` e o `gh` falso respondendo `"state":"OPEN"`, sai 0, como na base.

O placar final da bateria tem 0 falhas, e os casos (i), (q) e (s) seguem verdes.

### 2. Linha de continuação dentro de `busca:` vira recusa [tipo: implementar]
atende: D2
arquivos: `scripts/conferir-fluxo.cjs`, `scripts/conferir-busca.cjs`, `scripts/testa-conferir-busca.sh`, `skills/plano/references/campo-busca.md`
depende de: nenhuma
paralela: sim
busca:
- catalogo | listar --raiz scripts | estendo a função extrairBusca de scripts/conferir-fluxo.cjs:604 e a função recusar de scripts/conferir-busca.cjs:224
desfecho: estender
mutacao:
  arquivo: `scripts/conferir-fluxo.cjs`
  de: continuacoes.push(k); continue;
  para: break;
  bateria: `bash scripts/testa-conferir-busca.sh`
  fixture: testa-conferir-busca.sh, seção 9, caso "(v) linha de continuação dentro de busca: é recusada (#709)"
prova: `node -e "const fs=require('fs'),p=require('path'),cp=require('child_process');const f=p.join(process.cwd(),'tmp-prova-709.md');fs.writeFileSync(f,'# P\n\n## Tarefas\n\n### 1. x [tipo: implementar]\natende: D1\narquivos: \x60scripts/estado.cjs\x60\nbusca:\n- catalogo | listar --raiz scripts | nada equivalente, ver\n  nada.js:99\ndesfecho: estender\n');const r=cp.spawnSync(process.execPath,['scripts/conferir-busca.cjs','plano','--slug','s','--plano',f],{encoding:'utf8'});fs.unlinkSync(f);process.exit(r.status===2&&/continua/.test(r.stderr)?0:1)"`
Implementação: em `extrairBusca`, dentro do laço do bloco, antes do `break`, entra a checagem da linha de continuação. A linha conta como continuação quando está fora de cerca, não está vazia, começa com espaço ou tab e não começa com `- `. Ela entra com a forma exata `continuacoes.push(k); continue;`, sobre um array `continuacoes` declarado no início da função. A função devolve `{ presente, linhas, desfecho, continuacoes }`, e `continuacoes` traz o texto de cada linha. No `cmdPlano` do `conferir-busca.cjs`, cada continuação vira uma recusa: `<tarefa>; bloco \`busca:\` com linha de continuação: "<texto aparado>". Cada item cabe numa linha só. Formato: <FORMATO_LINHA>.`. O `campo-busca.md`, seção "Linha", ganha uma linha: o item cabe numa linha só, e a linha indentada sem hífen depois dele é recusada.
pronto quando: com o cenário da #709 (o plano da `prova:` acima, e a variante `nada equivalente, ver` seguida de `  nada.js:99`), `node scripts/conferir-busca.cjs plano --slug s --plano <arq>` sai 2, com "continuação" no stderr, nos dois casos. Com o mesmo plano, mas `- catalogo | listar --raiz scripts | reaproveito a de scripts/estado.cjs:750` numa linha só, sai 0. Emenda da revisão 1: com `desfecho:` depois do `busca:`, também saem 2 o item depois de linha em branco com `nada.js:9999` inexistente (conferido e recusado), `-catalogo ...` sem espaço depois do hífen, e a continuação encostada na margem. Isso é provado pela seção 9 de `bash scripts/testa-conferir-busca.sh`, com os casos novos e a linha de placar sem vermelha.

### 3. `critica-do-revisor` separa o preexistente do arquivo da entrega [tipo: implementar]
atende: D4
arquivos: `hooks/lib/achados-revisor.cjs`, `scripts/critica-do-revisor.cjs`, `scripts/testa-achado-preexistente.sh`
depende de: nenhuma
paralela: sim
busca:
- catalogo | listar --raiz hooks/lib | estendo a função preexistentesNoDiff de hooks/lib/achados-revisor.cjs:183, que já monta o mapa de arquivos do diff por linhasAdicionadas
desfecho: estender
mutacao:
  arquivo: `scripts/critica-do-revisor.cjs`
  de: (noDiff(x) ? secaoEntrega : secao).push(
  para: (false ? secaoEntrega : secao).push(
  bateria: `bash scripts/testa-achado-preexistente.sh`
  fixture: testa-achado-preexistente.sh, caso "(#697/D4) preexistente em arquivo que o diff toca sai na seção da entrega, não na de Issue"
prova: `node -e "process.exit(typeof require('./hooks/lib/achados-revisor.cjs').arquivosTocadosPeloDiff === 'function' ? 0 : 1)"`
Implementação: `hooks/lib/achados-revisor.cjs` exporta `arquivosTocadosPeloDiff(cwd)`. Ela devolve um `Set` com os caminhos de `git diff --name-only --no-renames <baseDoDiff(cwd)> HEAD`, ou `null` sem base. Ela também exporta `arquivoDoAchado(texto, item)`, com o arquivo citado no item pela mesma regra que o `preexistentesNoDiff` já usa: o caminho seguido de `:linha`, num limite de palavra, ou `item.arquivo`. Em `scripts/critica-do-revisor.cjs`, `noDiff(x)` é verdadeiro quando `arquivosTocadosPeloDiff(RAIZ)` contém `arquivoDoAchado(critica, x)`. O laço das `aceitas` usa exatamente a linha do `de:` acima. As duas seções saem no stderr, a nova antes da antiga, com o título `## Preexistentes no arquivo da entrega (corrigir nesta branch ou registrar no design como resíduo aceito, nunca Issue)`. Elas saem nos dois `return` (o do exit 3 e o do 0). A seção antiga mantém o título. Sem base (`null`), tudo continua na seção antiga. O comentário do topo do script descreve as duas seções.
pronto quando: com um estado de fluxo cujo último `reprovado` aponta para um transcrito com dois achados `[preexistente]`, a crítica separa os dois. O primeiro cita uma linha não alterada de um arquivo que o diff da fixture altera em outra linha. O segundo cita um arquivo que o diff não toca. `node scripts/critica-do-revisor.cjs --slug <slug>` sai 0, põe o primeiro sob `## Preexistentes no arquivo da entrega` e o segundo sob `## Preexistentes (não são da entrega — Issue, não correção)`, e nenhum dos dois aparece no stdout. Emenda da revisão 1: com o diff tocando `README.md` e `scripts/estado.cjs`, um preexistente que cita `docs/sub/README.md:10` ou `hooks/scripts/estado.cjs:10` sai na seção antiga (o sufixo depois de `/` ou `\` não casa com o arquivo do diff). Isso é provado pelo caso novo em `bash scripts/testa-achado-preexistente.sh`, com a linha `== resultado: N ok, 0 falha(s) ==`.

### 4. Texto: revisor e tester com a pasta pessoal desviada, preexistente da entrega não vira Issue, versão 2.15.0 [tipo: docs]
atende: D3, D4, D5
arquivos: `agents/revisor.md`, `agents/tester.md`, `skills/revisar/SKILL.md`, `skills/revisar/references/laco.md`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `README.md`, `CHANGELOG.md`
depende de: 3
paralela: nao
mutacao: n/a
  motivo: texto de método e número de versão; não há comportamento a inverter. A coerência se confere lendo o texto contra D3 e D4 e pelas baterias de teto e de versão.
pronto quando:
- `agents/revisor.md` e `agents/tester.md` dizem que código do projeto fora da bateria roda com `HOME`, `USERPROFILE`, `APPDATA` e `LOCALAPPDATA` num `mktemp -d`, e que "fora do repositório" não é isolamento. `grep -c "LOCALAPPDATA"` dá ≥ 1 em cada um.
- O molde do briefing em `skills/revisar/SKILL.md` traz a mesma linha.
- `agents/revisor.md`, `skills/revisar/SKILL.md` e `skills/revisar/references/laco.md` não dizem mais que todo preexistente aceito "vira Issue": nomeiam as duas seções da tarefa 3. `grep -n "para virar Issue" agents/revisor.md skills/revisar/SKILL.md` não devolve nada.
- Os manifestos dizem 2.15.0 e o selo do README também. O CHANGELOG ganha a entrada `## 2.15.0 — 2026-11-15`, que descreve D1 a D4 e não promete fechar a família do tokenizador.

As baterias `bash scripts/testa-teto-skills.sh`, `bash scripts/testa-abertura-mod-config.sh`, `bash scripts/testa-plugin-codex.sh` e `bash scripts/testa-versao.sh` saem com 0 falhas.
