# Plano: estado.cjs: escritores do arquivo do fluxo se excluem (#545)

Design: docs/rainforest/design/2026-10-15-estado-trava-unica.md

## O que não pode quebrar
- `bash scripts/testa-estado.sh` e `bash scripts/testa-estado-pendencia.sh` seguem verdes.
- `veredito` com slug inexistente continua saindo 0 sem gravar e sem stack trace.
- Sem `RFM_ESTADO_PAUSA_GRAVAR_MS`, nenhum comando espera.

## Tarefas

### 1. Trava única por fluxo e mescla por campo na gravação [tipo: implementar]
atende: D1, D2, D3, D4, D5, D6
arquivos: `scripts/estado.cjs`, `scripts/testa-estado-trava.cjs`, `.gitignore`
depende de: nenhuma
prova: `node scripts/testa-estado-trava.cjs`
mutacao:
  arquivo: `scripts/estado.cjs`
  de: const final = vivo === null ? estado : mesclarEstado(base, estado, vivo);
  para: const final = estado;
  bateria: `node scripts/testa-estado-trava.cjs`
  fixture: testa-estado-trava.cjs, caso "marcar pausado nao apaga decidir nem pendencia gravados durante a pausa"
pronto quando: com um fluxo real criado por `iniciar` num `RFM_ESTADO_ROOT` temporário, (a) um `marcar` rodando com `RFM_ESTADO_PAUSA_GRAVAR_MS=1500` e, durante a pausa, um `decidir` e um `pendencia` em processos separados terminam com os três efeitos no JSON: o status do `marcar`, o item em `decididos` e o texto em `pendentes`; (b) dois `decidir` concorrentes, sem pausa, deixam os dois itens em `decididos`; (c) um campo que o comando removeu (`em_voo` some no fechamento) continua removido depois da mescla, e um campo que só o outro processo criou continua lá; (d) nenhum arquivo `.veredito.lock`, `.flake.lock` ou `.decidir.lock` é criado e, terminado cada comando, `.<slug>.lock` não fica no disco; (e) um `.<slug>.lock` com PID morto não impede a gravação; (f) emenda D2: dois `pendencia` concorrentes, o primeiro com `RFM_ESTADO_PAUSA_GRAVAR_MS=1500`, deixam as duas pendências, e o mesmo vale para dois `liberar-teto` (os dois motivos); (g) com um `.<slug>.lock` de PID vivo segurado pela bateria, `marcar` e `pendencia` esperam a trava e, sem ela sair, recusam com exit ≠ 0 e "outra sessao esta escrevendo" sem gravar; (h) um `marcar` pausado e um `pendencia` no mesmo estágio terminam com o status do `marcar` e a pendência no mesmo bloco (mescla de segundo nível); (i) durante um `decidir`, um `registrar-flake` e um `marcar` pausados, a pasta do estado não contém `.veredito.lock`, `.flake.lock` nem `.decidir.lock`, e contém `.<slug>.lock`; (j) D6: `git check-ignore docs/rainforest/estado/.x.lock docs/rainforest/estado/x.json.tmp` lista os dois; (k) `process.exit` dentro da trava solta `.<slug>.lock`; (l) emenda D2 da 2ª revisão: com uma pendência já destinada, um `marcar --estagio design --status aprovado` pausado e um `pendencia B` durante a pausa terminam com o `marcar` saindo 2 com "RECUSADO: outro processo gravou", o design sem `aprovado` e `pendentes` = ["B"]; (m) dois `destinar` concorrentes, o primeiro pausado, deixam os dois destinos. Provado por `node scripts/testa-estado-trava.cjs` com zero falha e zero skipped, com um caso por letra (as mutações "trocar `comTravaDoFluxo(slug, () => gravarDentro(slug, estado))` por `gravarDentro(slug, estado)`" , "remover o ramo de segundo nível de `mesclarEstado`", "`if (conflitos.length > 0) {` vira `if (false) {`" e "tirar `destinar` de `TRAVA_NO_COMANDO`" deixam a bateria vermelha), e por `bash scripts/testa-estado.sh` e `bash scripts/testa-estado-pendencia.sh` verdes.

Forma do código: `ler(slug)` guarda a primeira leitura do processo como base. `gravar(slug, estado)` entra na trava `.<slug>.lock` (ou reaproveita a do processo, se já a segura), relê o arquivo vivo e calcula `const final = vivo === null ? estado : mesclarEstado(base, estado, vivo);` (linha exata), grava `final` como hoje (tmp + rename) e guarda `final` como nova base. `mesclarEstado` é pura, compara por `JSON.stringify` e desce um nível nos valores que são objeto. Os três comandos com trava própria passam a usar a trava única por um mesmo helper. Emenda 2026-10-16: a espera de `RFM_ESTADO_PAUSA_GRAVAR_MS` fica logo depois da leitura de cada comando (dentro da trava nos que travam o comando inteiro), e `gravarDentro` recusa com exit 2 quando `conflitosDaMescla` acha campo mudado nos dois lados. Nenhum caso de teste lê o texto do fonte.

### 2. CHANGELOG e versão [tipo: docs]
atende: D1, D2
arquivos: `CHANGELOG.md`, `README.md`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`
depende de: 1
mutacao: n/a
  motivo: entrada de CHANGELOG e número de versão; não há comportamento a inverter
pronto quando: com a tarefa 1 no repo, a entrada nova do CHANGELOG (PATCH sobre a versão da `origin/main` no momento) diz que os escritores do arquivo do fluxo passam a se excluir por uma trava só e que quem valida fora da trava mescla por campo, sem prometer exclusão durante a validação; as duas `plugin.json` e o selo do README batem — provado por `node scripts/conferir-versao.cjs` saindo 0 e pela leitura do revisor confrontando o texto com D1 e D2.
