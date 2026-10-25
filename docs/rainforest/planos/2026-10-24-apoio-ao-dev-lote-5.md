# Plano: Apoio ao dev, lote 5

Design: docs/rainforest/design/2026-10-24-apoio-ao-dev-lote-5.md

## O que não pode quebrar
- A catraca de mutação segue aprovando o vermelho legítimo e recusando o colapso nos casos de hoje (`scripts/testa-conferir-mutacao.sh`, inclusive 14c "colapso via placar AUSENTE"; `scripts/testa-conferir-mutacao-flaky.sh`; `scripts/testa-conferir-mutacao-no-lugar.sh`).
- `conferir-prova` continua recusando prova sem caso executado (`scripts/testa-conferir-prova.sh`, `scripts/testa-conferir-prova-sem-caso.sh`).
- `critica-do-revisor.cjs` mantém os exits de hoje: 0 crítica, 3 `[design]`, 4 sem reprovado ou sem achado, 69 transcrito ausente (`scripts/testa-critica-do-revisor.sh`); o hook `veredito-revisor` segue gravando (`hooks/testa-veredito-revisor.sh`).
- Os hooks de aviso nunca bloqueiam e falham abertos (`hooks/testa-aviso-duplicata.sh`, `hooks/testa-aviso-fluxo.cjs`, `hooks/testa-config.sh`).
- `conferir-ancoras` não reprova mapa antigo (`scripts/testa-conferir-ancoras.sh`, `scripts/testa-conferir-ancoras-regras.sh`).

## Tarefas

### 1. Placar legível na catraca de mutação [tipo: implementar]
atende: D2, D3
arquivos: `scripts/conferir-mutacao.cjs`, `scripts/conferir-prova.cjs`, `scripts/testa-conferir-mutacao-placar.sh`
depende de: nenhuma
busca:
- repo | grep -n "function extrairPlacar\|function mediuEFalhou\|extrairPlacarRecon" scripts/conferir-mutacao.cjs scripts/conferir-prova.cjs | extrairPlacar (:753) lê só `ok: N falhou: M` e `N ok, M falhou` e dá precedência à forma, não à posição; conferir-prova.cjs:47 tem um fallback próprio para `falha(s)`
- repo | gh issue view 589 | libtest `test result: FAILED. N passed; M failed` não é lido e o vermelho legítimo vira corte de shell
desfecho: estender
prova: `bash scripts/testa-conferir-mutacao-placar.sh`
mutacao:
  arquivo: `scripts/conferir-mutacao.cjs`
  de: const FALHA = 'falhou|falhas?|falha\\(s\\)';
  para: const FALHA = 'falhou';
  bateria: `bash scripts/testa-conferir-mutacao-placar.sh`
  fixture: testa-conferir-mutacao-placar.sh, caso "== resultado: 3 ok, 2 falha(s) == é lido como ok 3 falhou 2"
pronto quando: `extrairPlacar` (exportado por `scripts/conferir-mutacao.cjs`, chamado direto pela bateria com `require`) devolve `{ok:3,falhou:2}` para `== resultado: 3 ok, 2 falha(s) ==`, para `Resumo: 3 ok, 2 falhas`, para `Resultado: 3 OK, 2 FALHA`, para `== Resultado: 3 ok   2 falha(s) ==` (sem vírgula) e para `ok=3 falhou=2`; continua devolvendo os dois formatos de hoje; com `ok: 9 falhou: 0` numa linha do meio e `1 ok, 4 falha(s)` na última, devolve `{ok:1,falhou:4}` (a última por posição, qualquer forma); com duas linhas `test result: ok. 7 passed; 0 failed; ...` e `test result: FAILED. 0 passed; 1 failed; ...` devolve `{ok:7,falhou:1}` (soma do libtest); devolve `null` para saída sem placar; `mediuEFalhou` devolve true para a saída do libtest com `1 failed`, que é o caso da #589; e uma rodada real de `node scripts/conferir-mutacao.cjs` numa caixa `mktemp -d` (fonte de uma linha + bateria que imprime `== resultado: N ok, M falha(s) ==`) com baseline lento (`sleep 2`) e pós-mutação rápida que imprime `test result: FAILED. 0 passed; 1 failed` sai vermelho (exit 0 com a mutação aprovada), não `pulada (suspeita de corte de shell)`; uma bateria nessa mesma forma `falha(s)` que, mutada, morre antes de imprimir o placar sai 6 (colapso). `conferir-prova.cjs` passa a chamar só `extrairPlacar`, e `extrairPlacarRecon` não existe mais — provado por `bash scripts/testa-conferir-mutacao-placar.sh`, e `bash scripts/testa-conferir-mutacao.sh`, `bash scripts/testa-conferir-mutacao-flaky.sh`, `bash scripts/testa-conferir-prova.sh` e `bash scripts/testa-conferir-prova-sem-caso.sh` seguem verdes. Depois da mudança, `node scripts/conferir-fluxo.cjs mutacoes --slug <s>` para os slugs `2026-10-24-apoio-ao-dev-lote-2`, `-lote-3` e `-lote-4` tem a saída colada no relato (a mutação que virar colapso é achado, não se afrouxa a regra). A forma é a linha do `de:` (a palavra da falha numa constante usada pelas expressões, com `i` de caixa livre).

### 2. Voltas de revisão guardadas e comparadas [tipo: implementar]
atende: D2, D4
arquivos: `scripts/estado.cjs`, `hooks/lib/achados-revisor.cjs`, `scripts/critica-do-revisor.cjs`, `scripts/testa-critica-voltas.sh`
depende de: nenhuma
busca:
- repo | grep -n "vereditos: \[\]" scripts/estado.cjs | o exigir revisar zera a janela em :2953 e a volta anterior some
- repo | grep -n "function contarAchados\|module.exports" hooks/lib/achados-revisor.cjs | só conta; não lista severidade com arquivo
- livro | open-code-review session/compare.go:17-97 | new/persisting/resolved com chave sem número de linha
desfecho: estender
prova: `bash scripts/testa-critica-voltas.sh`
mutacao:
  arquivo: `scripts/critica-do-revisor.cjs`
  de: const marca = chavesAnteriores.has(a.arquivo) ? 'persiste (mesmo arquivo)' : 'novo';
  para: const marca = 'novo';
  bateria: `bash scripts/testa-critica-voltas.sh`
  fixture: testa-critica-voltas.sh, caso "achado no mesmo arquivo da volta anterior sai persiste"
pronto quando: numa caixa `mktemp -d` com `RFM_ESTADO_ROOT` apontado para ela (como `scripts/testa-critica-do-revisor.sh` monta o estado e os transcritos jsonl), `node scripts/estado.cjs exigir --slug S --estagio revisar` sobre um estado com `revisar.vereditos` de uma volta reprovada grava `revisar.voltas` com `{volta: 1, vereditos: [...]}` (os mesmos objetos, sem texto de crítica) e zera `vereditos` como hoje; um segundo `exigir revisar` acrescenta `{volta: 2, ...}` sem perder a 1; `listarAchados(texto)` de `hooks/lib/achados-revisor.cjs` devolve `[{sev:'media', arquivo:'scripts/a.cjs'}]` para `**[media]** scripts/a.cjs:12 — defeito` (a linha sai da chave) e `arquivo: null` quando o item não cita `caminho:linha`; com a volta 1 reprovada citando `scripts/a.cjs:12` e `scripts/b.cjs:3` e a volta atual reprovada citando `scripts/a.cjs:40` e `scripts/c.cjs:1`, `node scripts/critica-do-revisor.cjs --slug S` imprime a crítica atual seguida de `## Comparação com a volta anterior` com `scripts/a.cjs` marcado `persiste (mesmo arquivo)`, `scripts/c.cjs` marcado `novo` e `scripts/b.cjs` marcado `sumiu — confirmar se foi corrigido`, e sai 0; com o transcrito da volta anterior ausente, o bloco diz `transcrito da volta anterior ausente` e a crítica atual sai inteira; sem volta anterior, a saída é a de hoje, byte a byte; os exits 3, 4 e 69 não mudam — provado por `bash scripts/testa-critica-voltas.sh`, e `bash scripts/testa-critica-do-revisor.sh` e `bash hooks/testa-veredito-revisor.sh` seguem verdes. A forma é a linha do `de:`.

### 3. Orçamento medido em caixa vazia no auditor [tipo: implementar]
atende: D2, D5
arquivos: `scripts/testa-auditor-de-seguranca.sh`
depende de: nenhuma
busca:
- repo | grep -n "orcamento.cjs" scripts/testa-auditor-de-seguranca.sh scripts/testa-orcamento.sh | o caso 11 do auditor (:285) roda o orcamento.cjs na abertura real; testa-orcamento.sh:56 já usa RFM_ROOT numa raiz vazia
desfecho: reusar
prova-na-base: verde — o caso 11 passa isolado e no CI; só oscila com sessões abertas na máquina, que a caixa vazia tira da medida
mutacao: n/a
  motivo: a mudança é a própria bateria (o comando que ela roda), sem fonte de produção a inverter
pronto quando: o caso 11 de `scripts/testa-auditor-de-seguranca.sh` roda `node scripts/orcamento.cjs` com `RFM_ROOT` apontado para uma caixa `mktemp -d` vazia (a mesma receita de `scripts/testa-orcamento.sh:56`, com `trap` de limpeza), e a mensagem do caso diz que mede sem o radar da máquina; com uma sessão paralela aberta no checkout, a bateria sai verde três vezes seguidas — provado por `bash scripts/testa-auditor-de-seguranca.sh` (colar o placar das três rodadas) e `bash scripts/testa-orcamento.sh` verde.

### 4. Caminho real único nos hooks de aviso [tipo: implementar]
atende: D2, D6
arquivos: `hooks/lib/caminho-real.cjs`, `hooks/aviso-duplicata.cjs`, `hooks/aviso-fluxo.cjs`, `hooks/testa-caminho-real.sh`
depende de: nenhuma
busca:
- repo | grep -n "function caminhoReal\|const real = " hooks/aviso-duplicata.cjs hooks/aviso-fluxo.cjs | as duas cópias da mesma lógica (:133-143 e :62-65)
- repo | grep -n "hooks/lib/\$lib\|hooks/\*.cjs" scripts/testa-integrar-tarefa.sh scripts/testa-conferir-categoria.sh | baterias que copiam hooks para caixa de areia: conferir se alguma executa um dos dois hooks e precisa da lib nova
desfecho: estender
prova: `bash hooks/testa-caminho-real.sh`
mutacao:
  arquivo: `hooks/lib/caminho-real.cjs`
  de: return fs.realpathSync.native(p);
  para: return p;
  bateria: `bash hooks/testa-caminho-real.sh`
  fixture: testa-caminho-real.sh, caso "aviso-duplicata com cwd em nome curto 8.3 não acusa o próprio arquivo"
pronto quando: `hooks/lib/caminho-real.cjs` exporta `caminhoReal(p)` com a lógica de hoje (real do arquivo; se não existe, real da pasta + nome; se nem a pasta, o próprio `p`), e `hooks/aviso-duplicata.cjs` e `hooks/aviso-fluxo.cjs` a importam sem cópia local; em `aviso-duplicata`, o achado do `git grep` é descartado como "o próprio arquivo" quando casa o caminho relativo resolvido **ou** o relativo ao toplevel sem resolver; a bateria nova `hooks/testa-caminho-real.sh` prova a lib direto (arquivo existente, arquivo novo, pasta inexistente) e roda os dois hooks com payload montado como `hooks/testa-aviso-duplicata.sh` monta; tem o caso "aviso-duplicata com cwd em nome curto 8.3 não acusa o próprio arquivo" (no win32: repo de teste dentro de uma pasta de nome longo, o cwd do payload no nome curto obtido por `cygpath -d`; se `cygpath -d` devolve o nome longo, o caso sai `pulado: volume sem nome 8.3`; fora do win32, `pulado: só win32`) e o caso de junction (no win32, `cmd //c mklink /J` de uma pasta do repo de teste para outra; se o `git ls-files` não lista o arquivo pelo caminho da junction, o caso sai `pulado` com o motivo); e o caso 8.3 do `aviso-fluxo` (arquivo sob `docs/` com o cwd em nome curto continua isento); nenhuma bateria que copia hooks para caixa de areia fica vermelha por falta de `hooks/lib/caminho-real.cjs` — provado por `bash hooks/testa-caminho-real.sh`, e `bash hooks/testa-aviso-duplicata.sh`, `node hooks/testa-aviso-fluxo.cjs`, `bash hooks/testa-config.sh`, `bash hooks/testa-memoria-marca.sh`, `bash scripts/testa-integrar-tarefa.sh` e `bash scripts/testa-conferir-categoria.sh` seguem verdes. A forma é a linha do `de:`.

### 5. Travas que faltaram nos lotes 3 e 4 [tipo: implementar]
atende: D2, D7
arquivos: `scripts/conferir-ancoras.cjs`, `scripts/testa-conferir-ancoras-regras.sh`, `scripts/testa-baterias-do-diff.sh`, `hooks/testa-aviso-duplicata.sh`, `scripts/testa-memoria-proximidade.sh`
depende de: nenhuma
busca:
- repo | grep -n "novoParagrafo && atual === null" scripts/conferir-ancoras.cjs | parágrafo novo com regra aberta vira corpo dela (:271)
- repo | grep -n "name-status" scripts/baterias-do-diff.cjs | o ramo R (renomeação) do -z não tem caso na bateria
- repo | grep -n "semTeto" scripts/memoria.cjs | o caso 8 da bateria de proximidade só semeia 2 casamentos
desfecho: estender
prova-na-base: verde — os quatro casos entram em baterias que já existem e passam; o vermelho de cada um se prova pela mutação e pelas trocas em cópia descritas no pronto quando
mutacao:
  arquivo: `scripts/conferir-ancoras.cjs`
  de: } else if (novoParagrafo && (atual === null || RE_ABRE_NEGRITO.test(l))) {
  para: } else if (novoParagrafo && atual === null) {
  bateria: `bash scripts/testa-conferir-ancoras-regras.sh`
  fixture: testa-conferir-ancoras-regras.sh, caso "parágrafo em negrito sem id depois de regra R1 sai sem-id"
pronto quando: (a) num mapa com `**R1 — título**`, seus dois campos e, depois de linha em branco, um parágrafo `**Regra antiga sem id**`, `node scripts/conferir-ancoras.cjs <mapa>` imprime `regra sem-id: **Regra antiga sem id**` e a R1 continua `testada`, sem mudar o exit; parágrafo comum (sem `**` na abertura) depois da R1 segue corpo dela; (b) `scripts/testa-baterias-do-diff.sh` ganha o caso em que `git mv a.cjs a2.cjs` lista a bateria que cita `a2.cjs` (e a que cita `a.cjs`, se houver); (c) `hooks/testa-aviso-duplicata.sh` ganha o caso "payload sem definição de topo não sobe git", com `GIT_TRACE` apontado para um arquivo numa caixa `mktemp -d` que continua inexistente depois do hook; (d) o caso 8 de `scripts/testa-memoria-proximidade.sh` semeia 60 observações com o termo e confere que `--limite -1` devolve as 60 — provado por `bash scripts/testa-conferir-ancoras-regras.sh`, `bash scripts/testa-baterias-do-diff.sh`, `bash hooks/testa-aviso-duplicata.sh` e `bash scripts/testa-memoria-proximidade.sh`, com `bash scripts/testa-conferir-ancoras.sh` verde. Para (d), a prova de vermelho é trocar numa cópia `texto && !semTeto ? Math.max(limite, 50) : limite` por `texto ? Math.max(limite, 50) : limite` e ver o caso 8 falhar. A forma é a linha do `de:` (`RE_ABRE_NEGRITO = /^(?:[-*]\s+)?\*\*/`).

### 6. Versão 1.79.0, CHANGELOG e README [tipo: docs]
atende: D1, D8
arquivos: `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `CHANGELOG.md`, `README.md`
depende de: 1, 2, 3, 4, 5
mutacao: n/a
  motivo: metadado de versão e documentação, sem comportamento a inverter
pronto quando: com o diff real das tarefas 1 a 5, os dois `plugin.json` dizem `1.79.0`, o badge do README diz 1.79.0, o CHANGELOG tem a entrada `1.79.0 — 2026-10-25` com uma linha por decisão entregue (D3 a D7) citando o `arquivo:linha` do furo e a #589 no D3, e o README documenta os placares lidos pela catraca e a comparação de voltas no `critica-do-revisor` onde documenta os vizinhos — provado por `node -e "for (const f of ['.claude-plugin/plugin.json','.codex-plugin/plugin.json']) console.log(require('./'+f).version)"` devolvendo `1.79.0` duas vezes e pela leitura do revisor casando cada linha do CHANGELOG com o diff.

### 7. Baterias acusadas na varredura do executar [tipo: implementar]
atende: D7
arquivos: `hooks/testa-aviso-duplicata.sh`, `scripts/testa-backup-gravar.sh`, `scripts/testa-memoria-degradacao.sh`, `scripts/testa-memoria-migracao-atomica.sh`, `CHANGELOG.md`
depende de: 5, 6
desfecho: corrigir
prova-na-base: verde — a guarda só acusa quando outra sessão fecha o banco real no meio da bateria, e o idioma SANDBOXES só reprova depois da T5
mutacao: n/a
  motivo: a falha da guarda depende de outra sessão fechar o banco durante a bateria; o vermelho se prova por controle numa raiz falsa (apagar -shm/-wal não acusa, apagar FOCO.md acusa)
pronto quando: a varredura do executar acusou `scripts/testa-sandbox-com-trap.sh` (o caso 10 da T5 abriu um segundo `mktemp -d` sem o idioma SANDBOXES) e `scripts/testa-backup-gravar.sh` ("a bateria apagou da raiz real: rainforest.db-shm"); a caixa do caso 10 vira subpasta da `$SBP`, e a guarda da raiz real das três baterias que a têm deixa `-shm`, `-wal` e `-journal` fora da comparação — provado por `bash scripts/testa-sandbox-com-trap.sh`, `bash hooks/testa-aviso-duplicata.sh`, `bash scripts/testa-backup-gravar.sh`, `bash scripts/testa-memoria-degradacao.sh` e `bash scripts/testa-memoria-migracao-atomica.sh` verdes, e pelo controle da guarda numa raiz falsa.
