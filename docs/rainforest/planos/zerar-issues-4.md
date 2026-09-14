# Plano — zerar as Issues abertas, rodada 4

**Slug:** `zerar-issues-4` · **Design:** `docs/rainforest/design/zerar-issues-4.md`
**Base:** `origin/main` @ `14c471ed` · **Branch:** `fluxo/zerar-issues-4`

Oito tarefas, nove decisões. **Onda 1** (arquivos disjuntos entre si, paralelas):
T1, T3, T5, T6. **Onda 2** (cada uma encosta no arquivo de uma da onda 1): T2
(depois de T1), T4 (depois de T3), T7 (depois de T6). **Onda 3**: T8 (versão, por
último).

## O que não pode quebrar

O repositório é **público**: nenhum caminho desta máquina em código, teste ou
fixture; `git config` de bateria usa `test@test`. Toda asserção de bateria tem os
dois ramos (`if/else`) — a forma que só conta `ok` e nunca `FALHA` é a que não
sabe falhar. Bateria com mais de um `mktemp -d` usa o idioma `SANDBOXES` (guarda
`testa-sandbox-com-trap.sh`); nenhuma bateria chama `python`/`jq`/`rg` pelo nome
(guarda `testa-dependencias-de-bateria.sh`). Executor entrega em worktree isolado
sobre `14c471ed` e o commit de entrega tem esse hash como ancestral.

**Os três gates tocados aqui rodam do cache do plugin (1.14.0), não desta
árvore.** Consertá-los não alivia nada nesta sessão: a prova é a bateria rodando
contra o fonte do worktree, nunca "parou de bloquear".

**Formato dos campos de mutação** (lição da #254): `de:` e `para:` são **trecho
literal do fonte**, copiado, que ocorre **exatamente uma vez** no `arquivo:`;
`bateria:` é **linha de comando executável**, sem anotação entre parênteses.

---

### 1. `corpoDeHeredoc` vira lib, e o gate de staging passa a usá-la [tipo: implementar]
atende: D1, D2
arquivos: `hooks/lib/heredoc.cjs`, `hooks/gate-fechar-issue.cjs`, `hooks/gate-staging-total.cjs`, `hooks/testa-gate-staging-total.sh`, `hooks/testa-gate-fechar-issue.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `hooks/gate-staging-total.cjs`
  de: `const heredoc = corpoDeHeredoc(seg, i);`
  para: `const heredoc = null;`
  bateria: `bash hooks/testa-gate-staging-total.sh`
  fixture: o caso de prosa `Medido (folga de 2 B). Ele sobe.` dentro de `cat > x.md <<'EOF'` volta a sair 2 em vez de 0
pronto quando: existe `hooks/lib/heredoc.cjs` exportando `corpoDeHeredoc`, com o corpo movido de `hooks/gate-fechar-issue.cjs` **sem alteração de comportamento** (mesma assinatura `corpoDeHeredoc(cmd, i)`, mesmo retorno `{ fim, corpo, comando }` ou `null`, mesma lista de interpretadores); `hooks/gate-fechar-issue.cjs` não define mais a função e a importa da lib, e `bash hooks/testa-gate-fechar-issue.sh` sai 0 com o mesmo placar de antes da mudança (número de casos idêntico, citado no commit); em `hooks/gate-staging-total.cjs` a varredura de segmentos pula o corpo de heredoc cujo comando receptor não é interpretador, pela linha literal `const heredoc = corpoDeHeredoc(seg, i);` (uma ocorrência), e o entrega à análise quando o comando é interpretador; `hooks/testa-gate-staging-total.sh` ganha, cada caso mandando o payload ao hook por stdin com `tool_name: "Bash"`: (a) `cat > x.md <<'EOF'` cujo corpo é `Medido (folga de 2 B). Ele sobe.` sai **0**; (b) o mesmo seguido de `\ngh issue create --body-file x.md` sai **0**; (c) corpo citando o comando de staging em massa sai **0**; (d) corpo com crase, `$(`, `$VAR` e `|` sai **0**; (e) `bash <<'EOF'` cujo corpo tem o comando de staging em massa sai **2**; (f) o comando de staging em massa nu continua saindo **2**; (g) heredoc sem linha de fechamento não trava o gate e o texto restante é verificado como hoje — provado por `bash hooks/testa-gate-staging-total.sh` exit 0, `bash hooks/testa-gate-fechar-issue.sh` exit 0, e `node scripts/conferir-mutacao.cjs` com o bloco acima saindo 0 (`vermelho`).

### 2. O `-C` sobrevive ao bloqueio por ilegibilidade [tipo: implementar]
atende: D3
arquivos: `hooks/gate-staging-total.cjs`, `hooks/testa-gate-staging-total.sh`
depende de: 1
paralela: nao
mutacao:
  arquivo: `hooks/gate-staging-total.cjs`
  de: `      dirC = g.dirC;\n      indiceSegmento = idx;\n      break;`
  para: `      dirC = null;\n      indiceSegmento = idx;\n      break;`
  bateria: `bash hooks/testa-gate-staging-total.sh`
  fixture: bloqueio por ilegibilidade em `git -C <sandbox> ...` volta a citar o repositório do projeto em vez do sandbox
pronto quando: no ramo `if (g.incerto)` de `hooks/gate-staging-total.cjs` a linha `dirC = null;` não existe mais e o ramo atribui `dirC = g.dirC;` (o bloco literal do campo `de:` acima ocorre uma vez no arquivo); `analisaSegmentoGit` devolve o `dirC` do segmento junto de `{ incerto: true }` quando o `-C` foi lido, e `null` quando não havia `-C` ou o valor não é resolvível (começa por `$`, `~`, crase ou `(`); a mensagem de bloqueio, quando `dirC` foi lido e resolve para um repositório git, cita esse repositório na linha `Repo:` e lista os não-rastreados **dele**; quando o `-C` existia mas não resolve, a mensagem diz textualmente que não deu para resolver o destino do `-C` e **não** imprime a lista de não-rastreados de nenhum repositório; `hooks/testa-gate-staging-total.sh` ganha: (h) sandbox git criado pela bateria, comando ilegível com `git -C <sandbox>` — a saída contém o caminho do sandbox e não contém o do repositório sob teste; (i) o mesmo com `-C "$VAR/x"` — a saída contém a frase de destino não resolvível e nenhuma linha de `git status`; (j) sem `-C`, a mensagem continua citando o repositório do evento como hoje — provado por `bash hooks/testa-gate-staging-total.sh` exit 0 e por `node scripts/conferir-mutacao.cjs` com o bloco acima saindo 0 (`vermelho`).

### 3. Autorização de subagente tolera digitação, ancorada no verbo [tipo: implementar]
atende: D4
arquivos: `hooks/lib/autorizacao-usuario.cjs`, `hooks/testa-portaria-autorizacao.cjs`, `.rainforest/cobertura/autorizacao-usuario.json`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `hooks/lib/autorizacao-usuario.cjs`
  de: `const TOLERANCIA_SUBAGENTE = 2;`
  para: `const TOLERANCIA_SUBAGENTE = 0;`
  bateria: `node hooks/testa-portaria-autorizacao.cjs`
  fixture: `autorizo subagens` volta a não autorizar
pronto quando: `hooks/lib/autorizacao-usuario.cjs` reconhece a forma também por distância de edição — dentro da mesma janela de proximidade já usada depois de `autorizo`/`autorizar`/`autorizando`, um token que comece por `sub` e cuja distância de Levenshtein até `subagente` **ou** `subagentes` seja `<= TOLERANCIA_SUBAGENTE` conta como a forma, com `const TOLERANCIA_SUBAGENTE = 2;` ocorrendo uma vez; as formas exatas de hoje continuam casando pelo caminho de hoje (o regex `FORMAS_DE_SUBAGENTE` não é removido); `hooks/testa-portaria-autorizacao.cjs` afirma, pela porta pública `autorizado`, que **autorizam**: `autorizo subagentes`, `autorizo subagente`, `autorizo sub agentes`, `autorizo subagens`, `autorizo os subagens`, `autoriza subagens`, `autorizo subgentes`; e que **não autorizam**: `nao autorizo subagentes`, `autorizo submarinos`, `autorizo subir a versao`, `autorizo o deploy`, `se eu autorizar subagentes um dia, avise`, e a mesma frase vinda de `tool_result`/relato de subagente em vez da voz do usuário; `.rainforest/cobertura/autorizacao-usuario.json` ganha as sete formas com digitação errada e as seis negativas como fixtures, e `node scripts/conferir-cobertura-fixtures.cjs` sai 0 — provado por `node hooks/testa-portaria-autorizacao.cjs` exit 0, `node scripts/conferir-cobertura-fixtures.cjs` exit 0, e `node scripts/conferir-mutacao.cjs` com o bloco acima saindo 0 (`vermelho`).

### 4. A recusa da portaria culpa a digitação, não o estágio [tipo: implementar]
atende: D5
arquivos: `hooks/portaria.cjs`, `hooks/testa-portaria-diagnostico.cjs`
depende de: 3
paralela: nao
mutacao:
  arquivo: `hooks/portaria.cjs`
  de: `const quaseAutorizou = quaseFormaDeSubagente(linhaDoUsuario);`
  para: `const quaseAutorizou = null;`
  bateria: `node hooks/testa-portaria-diagnostico.cjs`
  fixture: recusa após `autorizo subagens` volta a dizer `sem estágio ativo — abra um fluxo`
pronto quando: `hooks/lib/autorizacao-usuario.cjs` exporta `quaseFormaDeSubagente(texto)`, que devolve o token lido quando a linha tem `autoriz*` seguido, na janela de proximidade, de um token começado por `sub` que **não** passou na tolerância da T3, e `null` caso contrário; `hooks/portaria.cjs` chama `const quaseAutorizou = quaseFormaDeSubagente(linhaDoUsuario);` (uma ocorrência) antes de montar a recusa da linha 800, e quando o retorno não é `null` o motivo impresso cita que a autorização foi **quase** reconhecida e mostra o token lido entre aspas, em vez de `sem estágio ativo — abra um fluxo`; a linha de `alternativas:` desse caso não repete `responda "autorizo subagentes"` como única saída sem dizer que a forma lida ficou fora da tolerância; os demais caminhos de recusa (transcript ausente, caminho inválido, autorização revogada) mantêm texto e exit de hoje; `hooks/testa-portaria-diagnostico.cjs` afirma os dois ramos: com `autorizo subagens` na voz do usuário a recusa contém `subagens` e não contém `sem estágio ativo`, e sem nenhuma menção a subagente a recusa é a de hoje, palavra por palavra — provado por `node hooks/testa-portaria-diagnostico.cjs` exit 0, `node hooks/testa-portaria-autorizacao.cjs` exit 0, e `node scripts/conferir-mutacao.cjs` com o bloco acima saindo 0 (`vermelho`).

### 5. Gate de publicação consulta a visibilidade do remoto [tipo: implementar]
atende: D6
arquivos: `hooks/gate-publicacao-destino.cjs`, `hooks/testa-gate-publicacao-destino.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `hooks/gate-publicacao-destino.cjs`
  de: `if (repositorioEhPrivado(gitTop)) process.exit(0);`
  para: `if (false) process.exit(0);`
  bateria: `bash hooks/testa-gate-publicacao-destino.sh`
  fixture: gravação em repo privado com termo proibido volta a ser bloqueada
pronto quando: `hooks/gate-publicacao-destino.cjs` tem `repositorioEhPrivado(dir)`, chamada pela linha literal `if (repositorioEhPrivado(gitTop)) process.exit(0);` (uma ocorrência) antes de qualquer bloqueio por termo; a função resolve `owner/repo` do remoto de destino, consulta `gh repo view <owner/repo> --json isPrivate`, e devolve `true` **apenas** quando a resposta é o JSON com `isPrivate: true`; devolve `false` quando a resposta diz público, quando o `gh` não existe, quando ele sai diferente de 0, quando a saída não é JSON legível, quando não há remoto, e quando `RAINFOREST_GATE_SEM_REDE=1` está no ambiente — falha fechada, nunca aberta; o resultado é gravado em cache sob a pasta de dados do rainforest (fora do repositório, regra 15), indexado por `owner/repo`, com validade declarada em constante nomeada no arquivo, e uma segunda gravação no mesmo repositório **não** dispara nova chamada ao `gh`; a mensagem de bloqueio deixa de afirmar "repo público" incondicionalmente e diz a visibilidade que foi de fato apurada; `hooks/testa-gate-publicacao-destino.sh` ganha, com um `gh` dublê no `PATH` do sandbox: (a) dublê que responde `{"isPrivate":true}` → gravação com termo proibido sai **0**; (b) dublê que responde `{"isPrivate":false}` → sai **2**; (c) sem `gh` no `PATH` → sai **2**; (d) dublê que sai 1 → sai **2**; (e) dublê que imprime lixo não-JSON → sai **2**; (f) o caso (a) repetido conta **uma** invocação do dublê (contador em arquivo dentro do sandbox), provando o cache; (g) `RAINFOREST_GATE_SEM_REDE=1` → sai **2** sem invocar o dublê; nenhum caminho desta máquina entra em fixture — provado por `bash hooks/testa-gate-publicacao-destino.sh` exit 0 e por `node scripts/conferir-mutacao.cjs` com o bloco acima saindo 0 (`vermelho`).

### 6. O laço das baterias vira `scripts/varrer-baterias.sh` [tipo: implementar]
atende: D7
arquivos: `scripts/varrer-baterias.sh`, `.github/workflows/baterias.yml`, `scripts/testa-varrer-baterias.sh`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `scripts/varrer-baterias.sh`
  de: `if [ "$total" -lt 15 ]; then`
  para: `if [ "$total" -lt 0 ]; then`
  bateria: `bash scripts/testa-varrer-baterias.sh`
  fixture: glob sabotado (zero bateria) passa a sair 0 em vez de 1
pronto quando: `scripts/varrer-baterias.sh` existe, é executável por `bash`, e contém o laço, a guarda de piso e o placar movidos de `.github/workflows/baterias.yml` (linhas ~160-196) **sem mudança de lógica**: mesmo glob `scripts/testa-*.sh hooks/testa-*.sh`, mesmo piso de 15 pela linha literal `if [ "$total" -lt 15 ]; then`, mesmo texto de placar, exit 0 com todas verdes e exit 1 listando as vermelhas; o script aceita `--so <caminho>` para rodar uma bateria só, e nesse modo a guarda de piso não se aplica; `grep -c 'testa-\*\.sh' .github/workflows/baterias.yml` devolve **0** e o passo `Rodar as baterias` do YAML é uma chamada a `bash scripts/varrer-baterias.sh`; `scripts/testa-varrer-baterias.sh` afirma, em sandbox com árvore sintética: (a) três baterias verdes → exit 0 e o placar cita 3 — mas só se o piso for exercitado pelo modo `--so`, senão a bateria monta as 15 mínimas; (b) uma vermelha entre elas → exit 1 e o nome dela aparece na lista de vermelhas; (c) glob que não casa com ninguém → exit 1 citando a guarda de piso, **não** exit 0; (d) `--so <uma bateria verde>` → exit 0 sem a guarda de piso; (e) `--so <uma vermelha>` → exit 1; a saída de cada bateria é preservada por bateria (o log de uma não sobrescreve o da outra) — provado por `bash scripts/testa-varrer-baterias.sh` exit 0, `bash scripts/varrer-baterias.sh` exit 0 na árvore do worktree, e `node scripts/conferir-mutacao.cjs` com o bloco acima saindo 0 (`vermelho`).

### 7. `conferir-versao.cjs` roda no job de PR [tipo: implementar]
atende: D8
arquivos: `.github/workflows/baterias.yml`, `scripts/testa-conferir-versao.sh`
depende de: 6
paralela: nao
mutacao:
  arquivo: `scripts/conferir-versao.cjs`
  de: `  const cmp = compararSemver(versaoLocal, versaoRemota);`
  para: `  const cmp = 1;`
  bateria: `bash scripts/testa-conferir-versao.sh`
  fixture: branch cuja versão empata com a de origin/main deixa de sair 2
pronto quando: `.github/workflows/baterias.yml` tem um passo nomeado que roda `node scripts/conferir-versao.cjs` dentro do job `baterias` que já existe — **nenhum job novo**, `permissions: contents: read` inalterado, `runs-on` inalterado; o passo roda depois do checkout com histórico e antes (ou junto) da varredura, e sua falha derruba o job; `scripts/testa-conferir-versao.sh` ganha, em sandbox: (a) repositório cuja versão local é MAIOR que a de `origin/main` → exit 0; (b) versão IGUAL → exit 2 citando os dois números; (c) versão MENOR → exit 2; (d) sem `origin/main` resolvível → exit 0 e a saída diz que a comparação foi pulada; nenhum caminho desta máquina entra em fixture — provado por `bash scripts/testa-conferir-versao.sh` exit 0, pelo próprio run de CI deste PR ficando **vermelho** enquanto `plugin.json` estiver em `1.14.0` e verde depois da T8 (as duas saídas citadas no PR), e por `node scripts/conferir-mutacao.cjs` com o bloco acima saindo 0 (`vermelho`).

### 8. Versão 1.14.1 e documentação das travas [tipo: docs]
atende: D9
arquivos: `.claude-plugin/plugin.json`, `README.md`, `docs/travas-mecanicas.md`
depende de: 1, 2, 3, 4, 5, 6, 7
paralela: nao
mutacao: n/a
  motivo: texto e um número; a coerência com o código é o critério abaixo, e `scripts/testa-versao.sh` confere o número e `scripts/testa-mapa-regras.sh` confere que todo arquivo citado existe
pronto quando: `.claude-plugin/plugin.json` declara `1.14.1` e o badge do README traz o mesmo número; `docs/travas-mecanicas.md` registra, na linha do `gate-staging-total.cjs`, que corpo de heredoc é dado e só conta quando alimenta interpretador, e que o `-C` decide o repositório citado na mensagem; na linha do `gate-publicacao-destino.cjs`, que repositório privado passa e que visibilidade desconhecida bloqueia; e ganha `scripts/varrer-baterias.sh` como o comando único das baterias; o README cita `bash scripts/varrer-baterias.sh` onde hoje manda reproduzir o laço; a soma de casos das baterias tocadas é re-medida se o placar mudou; `bash scripts/testa-versao.sh` exit 0, `bash scripts/testa-mapa-regras.sh` exit 0, `node scripts/conferir-versao.cjs` exit 0 — provado por esses três comandos e por `bash scripts/varrer-baterias.sh` exit 0 na árvore inteira.
