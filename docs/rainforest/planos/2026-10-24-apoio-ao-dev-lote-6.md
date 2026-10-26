# Plano: Apoio ao dev, lote 6

Design: docs/rainforest/design/2026-10-24-apoio-ao-dev-lote-6.md

## O que não pode quebrar
- O contrato do veredito do revisor: última linha `VEREDITO: ok|reprovado`, `ok` com `[alta]` e `reprovado` sem achado seguem incoerentes (`hooks/testa-veredito-revisor.sh`, `hooks/testa-veredito-coerente.sh`, `scripts/testa-estado.sh`).
- `critica-do-revisor.cjs` mantém os exits de hoje: 0 crítica, 3 `[design]`, 4 sem reprovado ou sem achado, 69 transcrito ausente (`scripts/testa-critica-do-revisor.sh`, `scripts/testa-critica-voltas.sh`).
- Executor despachado fora de fluxo nunca é bloqueado no `SubagentStop`; os hooks falham abertos com payload ilegível (`hooks/testa-config.sh`).
- `conferir-ancoras` não reprova mapa antigo: os degraus novos são aviso (`scripts/testa-conferir-ancoras.sh`, `scripts/testa-conferir-ancoras-regras.sh`).
- `conferir-fluxo cobertura` e `camadas` mantêm recusas e exits (`scripts/testa-camadas.sh`, `scripts/testa-conferir-fluxo*.sh`).
- A consolidação segue atômica e não duplica resumo (`scripts/testa-memoria.sh`, casos 14 a 16); nunca toca o banco real (`RFM_ROOT` em `mktemp -d`).
- O gate de publicação segue barrando o dado sensível novo em Write, Edit e commit (`hooks/testa-gate-publicacao-destino.sh`).

## Tarefas

### 1. Achado preexistente e comparação para o revisor [tipo: implementar]
atende: D2, D3, D9, D10
arquivos: `hooks/lib/achados-revisor.cjs`, `hooks/veredito-revisor.cjs`, `scripts/critica-do-revisor.cjs`, `agents/revisor.md`, `skills/revisar/SKILL.md`, `skills/revisar/references/laco.md`, `scripts/testa-achado-preexistente.sh`, `scripts/testa-critica-voltas.sh`, `scripts/estado.cjs`
depende de: nenhuma
busca:
- repo | grep -n "ABERTURA\|function incoerencia" hooks/lib/achados-revisor.cjs | vocabulário fechado alta/media/baixa/design (:21) e a coerência (:57-62) não têm marca de preexistente
- repo | grep -n "blocoComparacao" scripts/critica-do-revisor.cjs | a comparação sai no stdout padrão (:167-169), que o laco.md manda colar no briefing do executor
- repo | grep -n "merge-base" scripts/estado.cjs | a base do diff da branch é merge-base HEAD origin/<padrão> (:2117)
desfecho: estender
prova: `bash scripts/testa-achado-preexistente.sh`
mutacao:
  arquivo: `hooks/lib/achados-revisor.cjs`
  de: const bloqueia = !PREEXISTENTE.test(tags);
  para: const bloqueia = true;
  bateria: `bash scripts/testa-achado-preexistente.sh`
  fixture: testa-achado-preexistente.sh, caso "VEREDITO: ok com **[alta]** [preexistente] é coerente"
pronto quando: `[preexistente]` é aceito pela `ABERTURA` junto da severidade, em qualquer ordem (`**[alta]** [preexistente] a.cjs:3 — ...` e `[preexistente] [media] ...`); `contarAchados` devolve também `preexistente` (quantos itens têm a marca) e conta em `alta`, `media` e `baixa` só os itens sem a marca (a forma é a linha do `de:`, com `PREEXISTENTE = /\[preexistente\]/i`), e `total` também só os sem a marca; `incoerencia('ok', ...)` com um único `[alta] [preexistente]` devolve null, e `incoerencia('reprovado', ...)` só com preexistentes devolve a regra "reprovado sem achado marcado". `listarAchados` devolve `preexistente: true|false` em cada item. `preexistentesNoDiff(texto, cwd)` (exportada) devolve os itens `[preexistente]` cujo `arquivo:linha` cai numa linha adicionada ou alterada de `git diff -U0 <base>..HEAD`, com `<base>` = `git merge-base HEAD origin/<padrão>` (padrão de `git symbolic-ref refs/remotes/origin/HEAD`, ou `main`); sem base resolvível devolve null. No hook `veredito-revisor`, os itens que `preexistentesNoDiff` devolve perdem a marca antes da coerência (um `[alta] [preexistente]` numa linha do diff com `VEREDITO: ok` vira incoerente e devolve a vez). `critica-do-revisor.cjs` tira da crítica os preexistentes aceitos e os imprime depois, sob `## Preexistentes (não são da entrega — Issue, não correção)`; os recusados pelo diff ficam na crítica e o stderr diz `marca [preexistente] recusada: <arquivo:linha> está no diff`; sem base, stderr `marca [preexistente] não conferida: sem base`. A comparação de voltas sai do stdout padrão e passa a sair só com `--comparacao` (que imprime apenas o bloco e sai 0, também com veredito ok; sem volta anterior imprime `(sem volta anterior)`). `agents/revisor.md`, `skills/revisar/SKILL.md` e `skills/revisar/references/laco.md` documentam a marca, a conferência por `git show <base>:<arquivo>` e que o bloco de `--comparacao` vai no briefing do revisor da volta seguinte, nunca no do executor. A bateria nova roda num repo de `mktemp -d` com remoto bare (para o `origin/main`), commit base com `a.cjs` de 5 linhas e commit na branch que altera a linha 3, e cobre: ok com `[alta] [preexistente] a.cjs:5` coerente; o mesmo citando `a.cjs:3` recusado (incoerente, hook devolve a vez); reprovado só com preexistente incoerente; a crítica com a seção de preexistentes e sem eles no corpo; `--comparacao`. `scripts/testa-critica-voltas.sh` passa a ler o bloco por `--comparacao`. Emenda da 1ª revisão: a conferência acha a citação pelos caminhos do próprio diff (caminho com espaço e acento, cabeçalho `+++` com tabulação ou aspas); `[preexistente]` sem `arquivo:linha` é recusado; e `transcritoConfirmaVeredito` em `scripts/estado.cjs` aplica a mesma recusa, para o `invalido` da segunda parada gravar — provado por `bash scripts/testa-achado-preexistente.sh`, com `bash scripts/testa-critica-voltas.sh`, `bash scripts/testa-critica-do-revisor.sh`, `bash hooks/testa-veredito-revisor.sh`, `bash hooks/testa-veredito-coerente.sh` verdes.

### 2. Relato do executor com fim declarado [tipo: implementar]
atende: D4, D9
arquivos: `hooks/relato-executor.cjs`, `hooks/lib/transcrito-subagente.cjs`, `hooks/veredito-revisor.cjs`, `hooks/hooks.json`, `hooks/lib/config.cjs`, `skills/setup/SKILL.md`, `agents/executor.md`, `hooks/testa-relato-executor.sh`
depende de: 1
busca:
- repo | grep -n "function caminhoTranscritoSubagente\|agent_type\|decision: 'block'" hooks/veredito-revisor.cjs | o SubagentStop só olha o revisor (:198-199); caminhoTranscritoSubagente (:171) mora no hook
- repo | grep -n "SubagentStop" -A8 hooks/hooks.json | um bloco com um hook só (:283)
- repo | grep -n "contrato-veredito" hooks/lib/config.cjs skills/setup/SKILL.md | a chave de config tem declaração e linha na tabela do setup
desfecho: construir
prova: `bash hooks/testa-relato-executor.sh`
mutacao:
  arquivo: `hooks/relato-executor.cjs`
  de: const SENTINELA = /^entrega: (completa|parcial)$/;
  para: const SENTINELA = /^/;
  bateria: `bash hooks/testa-relato-executor.sh`
  fixture: testa-relato-executor.sh, caso "executor em fluxo sem a linha ENTREGA devolve a vez"
pronto quando: `hooks/lib/transcrito-subagente.cjs` exporta `caminhoTranscritoSubagente` (movida de `hooks/veredito-revisor.cjs`, que passa a importá-la, sem mudar comportamento); `hooks/relato-executor.cjs` entra como segundo hook do bloco `SubagentStop` de `hooks/hooks.json`; para `agent_type` `executor` ou `rainforest-mind:executor` cujo primeiro prompt tem `Slug:` (via `primeiroPrompt`/`extrairSlug` de `scripts/lib/primeiro-prompt-jsonl.cjs`), lê a última mensagem (payload `last_assistant_message`, com `ultimaMensagemAssistente` do transcrito como reserva) e compara a última linha normalizada (`extrairUltimaLinha` de `scripts/lib/extrair-veredito.cjs`, que tira negrito e põe em minúsculas) com a forma da linha do `de:`; sem casar e com `stop_hook_active !== true`, imprime `{"decision":"block","reason":...}` pedindo o relato completo terminando em `ENTREGA: completa` ou `ENTREGA: parcial`; na segunda parada, sem prompt com `Slug:`, com outro `agent_type`, com payload ilegível ou com `contrato-relato-executor` desligado (chave nova em `hooks/lib/config.cjs`, boolean, padrão true, e linha na tabela de `skills/setup/SKILL.md`), sai 0 sem imprimir nada. Não grava estado. `agents/executor.md` documenta a linha final e que é `parcial` quando há item NÃO FEITO. A bateria monta payloads com `node` (nunca printf) e transcritos jsonl numa caixa `mktemp -d` e cobre os seis casos (sem linha → block; `ENTREGA: completa` e `**ENTREGA: parcial**` → nada; segunda parada → nada; sem `Slug:` → nada; revisor → nada; chave desligada por `RFM_ROOT` com config → nada) — provado por `bash hooks/testa-relato-executor.sh`, com `bash hooks/testa-veredito-revisor.sh`, `bash hooks/testa-veredito-coerente.sh` e `bash hooks/testa-config.sh` verdes.

### 3. Âncora que confere o teste e o commit [tipo: implementar]
atende: D5, D10
arquivos: `scripts/conferir-ancoras.cjs`, `scripts/testa-conferir-ancoras-degraus.sh`, `scripts/testa-conferir-ancoras-regras.sh`, `skills/arqueologia/SKILL.md`, `agents/arqueologo.md`
depende de: nenhuma
busca:
- repo | grep -n "regra.estado = 'testada'" scripts/conferir-ancoras.cjs | testada só olha se o campo Teste: existe (:305-307)
- repo | grep -n "novoParagrafo && (atual === null" scripts/conferir-ancoras.cjs | o lote 5 fecha a regra em qualquer parágrafo em negrito, inclusive antes dos campos (:274)
- repo | grep -n "raiz = process.cwd()\|--repo" scripts/conferir-ancoras.cjs | a raiz do repo mapeado vem do --repo, padrão cwd (:45,94)
desfecho: estender
prova: `bash scripts/testa-conferir-ancoras-degraus.sh`
mutacao:
  arquivo: `scripts/conferir-ancoras.cjs`
  de: regra.estado = citaRegra(alvo, regra.n) ? 'testada' : 'teste-sem-id';
  para: regra.estado = 'testada';
  bateria: `bash scripts/testa-conferir-ancoras-degraus.sh`
  fixture: testa-conferir-ancoras-degraus.sh, caso "Teste: que existe e não cita R1 sai teste-sem-id"
pronto quando: com `Teste: <caminho>` não `nenhum`, o arquivo é procurado sob a raiz do `--repo`: ausente sai `regra R<n> teste-ausente`; presente e sem o id (`R<n>` como palavra inteira, de modo que `R10` não cita `R1`) sai `regra R<n> teste-sem-id`; presente e citando sai `testada` (a forma é a linha do `de:`). `Verificada em: <sha>` que não resolve por `git cat-file -e <sha>^{commit}` na raiz do `--repo` acrescenta a linha `regra R<n> sha-desconhecido`; raiz sem git não confere nem avisa. Os três avisos novos não mudam o exit e entram no sufixo de contagem. Parágrafo em negrito sem id entre o marcador `**R<n> — ...**` e o primeiro campo dele (`Verificada em:` ou `Teste:`) é corpo da regra (o mapa da revisão do lote 5, com `**Atenção:** ...` antes dos campos, volta a sair `regra R1 testada` com exit 0); depois dos campos, segue saindo `regra sem-id`. `skills/arqueologia/SKILL.md` e `agents/arqueologo.md` dizem que o teste citado nomeia a regra pelo id. A bateria nova monta, num repo de `mktemp -d` com um commit, mapas com: teste ausente; teste que não cita; teste que cita `R10` mas não `R1`; teste que cita; sha inexistente; sha real; o caso `**Atenção:**` antes dos campos — provado por `bash scripts/testa-conferir-ancoras-degraus.sh`, com `bash scripts/testa-conferir-ancoras-regras.sh` e `bash scripts/testa-conferir-ancoras.sh` verdes.

### 4. Acoplamento por require entre tarefas da mesma camada [tipo: implementar]
atende: D6
arquivos: `scripts/lib/camadas.cjs`, `scripts/conferir-fluxo.cjs`, `scripts/testa-camadas-acoplamento.sh`
depende de: nenhuma
busca:
- repo | grep -n "globMatches(arq1, arq2)" scripts/lib/camadas.cjs | a colisão compara só arquivos declarados (:100-116), nada lê require
- repo | grep -n "calcularCamadas(tarefasDag)" scripts/conferir-fluxo.cjs | a cobertura imprime recusas e avisos de camada (:383-390)
desfecho: estender
prova: `bash scripts/testa-camadas-acoplamento.sh`
mutacao:
  arquivo: `scripts/lib/camadas.cjs`
  de: const alvos = alvosDeRequire(texto, path.dirname(arquivo));
  para: const alvos = [];
  bateria: `bash scripts/testa-camadas-acoplamento.sh`
  fixture: testa-camadas-acoplamento.sh, caso "require(path.join(__dirname, 'lib', 'x.cjs')) entre tarefas da mesma camada avisa"
pronto quando: `scripts/lib/camadas.cjs` exporta `acoplamentos(camadas, arquivosDe, raiz)`, que para cada par de tarefas da mesma camada lê na árvore os arquivos declarados de uma (os que existem; glob fica fora) e devolve `{camada, a, b, arquivo, alvo}` quando um deles faz `require`/`import` de um arquivo declarado pela outra; reconhece `require('./x')`, `require('../x.cjs')`, `import y from './x'`, `import('./x')` e `require(path.join(__dirname, '<lit>', ..., '<lit>'))` com todos os argumentos literais, resolvendo relativo ao diretório do arquivo e casando com ou sem a extensão `.cjs`/`.js`/`.mjs`/`.ts`; `require` com variável e módulo de pacote ficam fora. `conferir-fluxo.cjs cobertura` imprime no stderr, para cada um, `aviso: tarefa B (<arquivo>) faz require de <alvo>, da tarefa A, na mesma camada N — declare depende de: A se a tarefa A muda o que <alvo> exporta`, sem mudar o exit; `camadas` inclui `acoplamentos` no JSON. A bateria monta um plano e uma árvore numa caixa `mktemp -d` e cobre: as cinco formas avisam; tarefas em camadas diferentes não avisam; require de variável e de pacote não avisam; o exit da cobertura segue 0 — provado por `bash scripts/testa-camadas-acoplamento.sh`, com `bash scripts/testa-camadas.sh` verde.

### 5. Consolidação que não pula calada [tipo: implementar]
atende: D7
arquivos: `scripts/memoria.cjs`, `scripts/observar.cjs`, `scripts/testa-memoria-consolidar-pulo.sh`
depende de: nenhuma
busca:
- repo | grep -n "LLM falhou, pedaço intacto\|registrar('consolidar: fim')" scripts/memoria.cjs | o pulo vira console.log (:1802-1805) e a passada grava fim (:2472-2479)
- repo | grep -n "TETO_ARGUMENTO" scripts/memoria.cjs scripts/observar.cjs | o pedaço acima de 16.000 caracteres devolve null sempre (:1517-1522); observar.cjs já trunca (:573-586)
- repo | grep -n "TESTADOR_CHAMAR_LLM\|TESTADOR_LLM_FALHAR" scripts/testa-memoria.sh | o dublê de LLM da bateria (casos 14 a 16)
desfecho: corrigir
prova: `bash scripts/testa-memoria-consolidar-pulo.sh`
mutacao:
  arquivo: `scripts/memoria.cjs`
  de: if (pulados > 0) houveFalha = true;
  para: if (false) houveFalha = true;
  bateria: `bash scripts/testa-memoria-consolidar-pulo.sh`
  fixture: testa-memoria-consolidar-pulo.sh, caso "LLM que falha deixa a manutenção completa com falhas"
pronto quando: `cmdConsolidar` devolve `{ gravados, pulados }` (pulados = pedaços em que o LLM devolveu null); `cmdManutencao` grava `consolidar: fim (N pedaço(s) pulado(s))` quando N > 0 (e `consolidar: fim` com zero) e, com N > 0, marca `houveFalha` (a forma é a linha do `de:`), de modo que o `manutencao.log` termina em `manutencao: completa com falhas`; a CLI `consolidar` direta imprime o total pulado no relatório final. Antes de chamar o LLM, cada observação do pedaço é cortada em `Math.floor(16000 / pedaco.length) - 40` caracteres com o marcador `[…]` quando o texto montado passaria do teto, de modo que o pedaço de 30 observações longas chega ao LLM com no máximo 16.000 caracteres; o banco não muda. Em `scripts/observar.cjs`, a linha final `ok: observacao gravada em N fatia(s)` conta só as fatias processadas quando o orçamento corta (`:650-652`). A bateria nova usa `RFM_ROOT` numa caixa `mktemp -d` e o dublê `TESTADOR_CHAMAR_LLM` (o mesmo de `scripts/testa-memoria.sh`) e cobre: manutenção com `TESTADOR_LLM_FALHAR=1` termina em `completa com falhas` e com `pulado` na linha do consolidar; manutenção com LLM ok termina em `completa`; 30 observações de 2.000 caracteres chegam ao dublê com o texto ≤ 16.000 e gravam resumo — provado por `bash scripts/testa-memoria-consolidar-pulo.sh`, com `bash scripts/testa-memoria.sh` e `bash scripts/testa-observar*.sh` que existirem verdes.

### 6. Write com linha de base no gate de publicação [tipo: implementar]
atende: D8, D9
arquivos: `hooks/gate-publicacao-destino.cjs`, `hooks/testa-gate-publicacao-write.sh`
depende de: nenhuma
busca:
- repo | grep -n 'nome === "Write"' hooks/gate-publicacao-destino.cjs | o Write deixa antigo = null (:749-751) e o filtro de introduzidos não roda (:811)
- repo | grep -n "function soIntroduzidos" hooks/gate-publicacao-destino.cjs | o filtro por multiconjunto de linhas que o Edit usa (:338)
desfecho: estender
prova: `bash hooks/testa-gate-publicacao-write.sh`
mutacao:
  arquivo: `hooks/gate-publicacao-destino.cjs`
  de: antigo = lerSeExiste(arquivo, cwdDoEvento);
  para: antigo = null;
  bateria: `bash hooks/testa-gate-publicacao-write.sh`
  fixture: testa-gate-publicacao-write.sh, caso "Write que reescreve arquivo com a linha sensível já existente passa"
pronto quando: no `Write`, `antigo` recebe o conteúdo atual do arquivo no disco (resolvido contra o `cwd` do evento quando relativo) ou fica null quando o arquivo não existe ou não é legível (a forma é a linha do `de:`); com `antigo` não nulo, `soIntroduzidos` filtra como no Edit. A bateria nova monta payloads com `node` numa caixa `mktemp -d` com remoto público simulado como as baterias vizinhas do gate fazem, e cobre: Write que reescreve um arquivo que já tinha uma linha com número de cara de telefone, mudando outra linha, passa; Write que acrescenta uma segunda ocorrência nova barra; Write de arquivo novo com a linha barra; o commit com a linha nova segue barrado — provado por `bash hooks/testa-gate-publicacao-write.sh`, com `bash hooks/testa-gate-publicacao-destino.sh` verde.

### 7. Versão 1.80.0, CHANGELOG, README e o placar do caminho real [tipo: docs]
atende: D1, D10, D11
arquivos: `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `CHANGELOG.md`, `README.md`, `hooks/testa-caminho-real.sh`, `scripts/testa-conferir-categoria.sh`, `hooks/aviso-duplicata.cjs`
depende de: 1, 2, 3, 4, 5, 6
mutacao: n/a
  motivo: metadado de versão, documentação e a contagem de pulados no resumo de uma bateria, sem comportamento de produção a inverter
pronto quando: com o diff real das tarefas 1 a 6, os dois `plugin.json` dizem `1.80.0`, o badge do README diz 1.80.0, o CHANGELOG tem a entrada `1.80.0 — 2026-10-25` com uma linha por decisão entregue (D3 a D8 e D10) citando o `arquivo:linha` do furo na 1.79.0, sem linha de crédito a projeto de terceiros; a entrada 1.79.0 troca `conferir-ancoras.cjs:271` por `:270` e "84 baterias" por 88; o README documenta `[preexistente]` e `--comparacao` onde documenta o revisor, a linha `ENTREGA:` onde documenta o executor, os degraus da âncora, o aviso de acoplamento da cobertura e a chave `contrato-relato-executor`; `hooks/testa-caminho-real.sh` conta os casos `pulado` e os imprime no resumo final (`== resultado: N ok, M falha(s), P pulado(s) ==`), e cria a junction com `cmd /c mklink /J ... </dev/null` (com o `MSYS_NO_PATHCONV=1` da bateria, o `cmd //c` abria o cmd interativo e o caso nunca rodava), de modo que o caso da junction roda e fica vermelho numa cópia sem o segundo nome do `aviso-duplicata` (emenda depois do CI do PR #598: o caso, rodando, achou o segundo nome errado com cwd 8.3 contra o toplevel longo do git; o segundo nome resolve só o cwd, e a bateria ganha o caso da junction com cwd 8.3; a revisão desse conserto achou o cwd dentro da junction, e o CI do PR #599 o cwd 8.3 dentro da junction; o nome da junction passa a sair subindo do arquivo até o ancestral cujo caminho real é o do toplevel, com os casos dos dois) ; `scripts/testa-conferir-categoria.sh` passa a contar 65 peças e 37 sensores, porque o `hooks/relato-executor.cjs` da tarefa 2 é uma peça nova (emenda depois da integração da tarefa 2, que a acusou) — provado por `node -e "for (const f of ['.claude-plugin/plugin.json','.codex-plugin/plugin.json']) console.log(require('./'+f).version)"` devolvendo `1.80.0` duas vezes, por `bash hooks/testa-caminho-real.sh`, por `bash scripts/testa-conferir-categoria.sh` verde verde com o placar de pulados, e pela leitura do revisor casando cada linha do CHANGELOG com o diff.
