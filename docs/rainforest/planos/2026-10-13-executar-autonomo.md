# Plano: o fluxo roda sozinho do plano aprovado até o PR mergeado

Design: docs/rainforest/design/2026-10-13-executar-autonomo.md

## Achados lidos no fonte (base fa2bbbab)
- Não existe script de integração. A sequência conferência → commit com trailer → `marcar` está só em prosa, em `skills/executar/references/camadas-e-retomada.md:22-36`.
- `conferir-fluxo.cjs mutacoes` roda a catraca de todas as tarefas do plano e não aceita escolher uma só (`cmdMutacoes`).
- Os trechos que mandam parar e esperar o usuário são `skills/revisar/references/laco.md:23,39-43,74-77,86-91`, `skills/revisar/SKILL.md:269-276`, `skills/fechar/SKILL.md:38-40,135,207-211,249-253` e `skills/rainforest-mind/references/regra-16.md:23-37,97-99`.
- `PushNotification` aparece só em prosa (`camadas-e-retomada.md:81-82`).
- Tamanhos: `executar/SKILL.md` tem 16350 B, `revisar/SKILL.md` 16164 B e `fechar/SKILL.md` 15405 B, contra um teto de 16384 B. O texto novo vai para `references/`. `fechar` é corpo ancorado em `scripts/contrato-plugin-codex.cjs`: se ele mudar, a âncora tem de ser medida de novo.
- A chave `fechar-mergear` (`hooks/lib/config.cjs:262-270`) é o modelo da chave nova. O `.rainforest/config.json` deste repo já a liga.

## O que não pode quebrar
- Com `executar-autonomo` desligada, que é o padrão, nada muda: as skills continuam parando onde param hoje.
- `bash scripts/testa-estado.sh`, `bash scripts/testa-conferir-fluxo.sh` e `bash scripts/testa-conferir-entrega.sh` continuam verdes.
- O `integrar-tarefa` nunca commita uma entrega que o `conferir-entrega` recusou, nem uma cuja mutação sobreviveu. Se recusar, a árvore da branch do fluxo volta ao que era antes.
- Nenhuma decisão que mexa numa `D<n>` do design vira "decidido sem você" (D4).

## Decisões assumidas pelo plano (técnicas; o design não fixa)
- `integrar-tarefa.cjs` roda com o cwd no worktree do fluxo, na ordem fixa: `conferir-entrega` com o `arquivos:` da tarefa como `--escopo` → `git cherry-pick --no-commit` do HEAD do worktree do agente → `conferir-fluxo.cjs mutacoes --tarefa N` → `git commit` com `--trailer "Rainforest-Tarefa: <slug>#<n>"` → `estado.cjs marcar` de `executar` `parcial` com `integradas: [N]` e `em_voo` sem a tarefa → `git worktree remove` + `git branch -D` do agente.
  - Exits: 0 aceito; 2 recusado, com o passo e a saída dele no stderr; 69 ambiente.
  - Na recusa depois do cherry-pick, desfaz com `git restore --staged --worktree` dos arquivos trazidos.
  - Imprime uma linha JSON: `{"tarefa":N,"resultado":"aceito|recusado","passo":"...","commit":"<hash>"}`.
- `rodar-longo.cjs iniciar --saida <arq> -- <comando>` sobe o comando destacado (`detached`, `unref`), com stdout e stderr no arquivo, e acrescenta `exit <N>` ao terminar. Imprime o PID e sai na hora. `rodar-longo.cjs estado --saida <arq>` imprime `rodando` (exit 3) ou `exit <N>` (exit 0).
- O registro da D4 mora no estado: `estado.cjs decidir --slug <s> --pergunta <p> --escolha <e> --porque <m>` acrescenta a `decididos` (com estágio e data). `estado.cjs decididos --slug <s>` imprime a seção markdown `## Decidido sem você`, ou nada se a lista estiver vazia.
- A chave chama `executar-autonomo` (boolean, padrão `false`) e é lida como `fechar-mergear`: erro na leitura conta como desligada.

## Em aberto
- Nada.

## Tarefas

### 1. Integração de uma tarefa num comando só [tipo: implementar]
atende: D6, D7
arquivos: `scripts/integrar-tarefa.cjs`, `scripts/testa-integrar-tarefa.sh`, `scripts/conferir-fluxo.cjs`
depende de: nenhuma
prova: `bash scripts/testa-integrar-tarefa.sh`
mutacao:
  arquivo: `scripts/integrar-tarefa.cjs`
  de: if (entrega.status !== 0) return recusar('conferir-entrega', entrega);
  para: if (false) return recusar('conferir-entrega', entrega);
  bateria: `bash scripts/testa-integrar-tarefa.sh`
  fixture: `testa-integrar-tarefa.sh, secao "entrega fora do escopo recusa e nao commita"`
pronto quando: num repo-caixa com `origin` bare, fluxo aberto em `executar`, plano de 2 tarefas com `mutacao:` real e um worktree de agente com um commit de verdade, `node scripts/integrar-tarefa.cjs --slug <s> --tarefa 1 --worktree <w> --base <h> --head-antes <h0> --sujo-antes <f> --titulo "<t>"`:
- **Entrega boa:** sai 0 e imprime `"resultado":"aceito"`. A branch ganha exatamente 1 commit com o trailer `Rainforest-Tarefa: <s>#1`, o estado passa a ter `integradas` contendo 1 e `em_voo` sem a tarefa 1, e o worktree e a branch do agente somem.
- **Entrega que toca arquivo fora do `arquivos:`:** sai 2 com `"passo":"conferir-entrega"`. O HEAD não se move, `git status --porcelain` fica igual ao de antes e `integradas` não muda.
- **Entrega cuja mutação sobrevive** (bateria que não testa o trecho): sai 2 com `"passo":"mutacao"`. Os arquivos trazidos pelo cherry-pick saem da árvore e o HEAD não se move.
- **Worktree inexistente:** sai 69.

O código tem a linha `if (entrega.status !== 0) return recusar('conferir-entrega', entrega);` exatamente uma vez. `conferir-fluxo.cjs mutacoes --tarefa 2` roda só a tarefa 2. Provado por `bash scripts/testa-integrar-tarefa.sh` e `bash scripts/testa-conferir-fluxo.sh`.

### 2. Processo longo fora do teto do Bash [tipo: implementar]
atende: D7
arquivos: `scripts/rodar-longo.cjs`, `scripts/testa-rodar-longo.sh`
depende de: nenhuma
prova: `bash scripts/testa-rodar-longo.sh`
mutacao:
  arquivo: `scripts/rodar-longo.cjs`
  de: fs.writeFileSync(exitPath(saida), String(codigo));
  para: fs.writeFileSync(exitPath(saida), "0");
  bateria: `bash scripts/testa-rodar-longo.sh`
  fixture: `testa-rodar-longo.sh, secao "comando que sai 3 registra exit 3"`
pronto quando: `node scripts/rodar-longo.cjs iniciar --saida <arq> -- bash -c 'sleep 3; echo oi; exit 3'`:
- sai 0 em menos de 2 s e imprime um PID;
- logo depois, `node scripts/rodar-longo.cjs estado --saida <arq>` imprime `rodando` e sai 3;
- depois de o comando terminar, o arquivo contém `oi` e a última linha é `exit 3`, e o `estado` imprime `exit 3` e sai 0;
- comando inexistente registra exit ≠ 0, sem travar.

O código tem a linha `fs.writeFileSync(exitPath(saida), String(codigo));` exatamente uma vez. Provado por `bash scripts/testa-rodar-longo.sh`.

### 3. Chave executar-autonomo e registro do decidido sem você [tipo: implementar]
atende: D4, D5
arquivos: `hooks/lib/config.cjs`, `.rainforest/config.json`, `scripts/estado.cjs`, `scripts/testa-estado-decididos.sh`
depende de: nenhuma
prova: `bash scripts/testa-estado-decididos.sh`
mutacao:
  arquivo: `scripts/estado.cjs`
  de: if (!porque || !porque.trim()) {
  para: if (false) {
  bateria: `bash scripts/testa-estado-decididos.sh`
  fixture: `testa-estado-decididos.sh, secao "decidir sem porque recusa e nao grava"`
pronto quando: num repo-caixa com o fluxo aberto:
- `estado.cjs decidir --slug <s> --pergunta "Q2 veredito no cartao" --escolha "no resumo" --porque "revisar julga a branch"` sai 0 e grava em `decididos` um item com `pergunta`, `escolha`, `porque`, `estagio` e `em`;
- uma segunda chamada acumula, sem sobrescrever;
- `estado.cjs decididos --slug <s>` imprime `## Decidido sem você` seguido de uma linha por item, com pergunta, escolha e porquê; com a lista vazia, não imprime nada e sai 0;
- `decidir` sem `--porque`, ou com `--porque ""`, sai 2 e não grava.

`node -e` com `resolverConfig` mostra `executar-autonomo` com padrão `false` numa caixa sem config, e `true` com o `.rainforest/config.json` deste repo. A linha `if (!porque || !porque.trim()) {` aparece exatamente uma vez em `estado.cjs`. Provado por `bash scripts/testa-estado-decididos.sh` e `bash scripts/testa-estado.sh`.

### 4. Skills do modo autônomo, README, CHANGELOG e versão 1.66.0 [tipo: docs]
atende: D1, D2, D3, D4, D5, D6, D7
arquivos: `skills/executar/references/modo-autonomo.md`, `skills/executar/SKILL.md`, `skills/revisar/references/laco.md`, `skills/fechar/SKILL.md`, `skills/rainforest-mind/references/regra-16.md`, `README.md`, `CHANGELOG.md`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `scripts/baterias-obrigatorias.txt`, `scripts/contrato-plugin-codex.cjs`
depende de: 1, 2, 3
mutacao: n/a
  motivo: texto de skill e de documentação, sem comportamento a inverter; a falsificação é a coerência com o design e com os comandos das tarefas 1 a 3.
pronto quando: com os scripts das tarefas 1 a 3 na branch, a sessão que lê as skills com `executar-autonomo` ligada recebe as instruções abaixo, e com a chave desligada continua recebendo as de hoje.
- **`modo-autonomo.md`** cobre:
  - o alcance de `plano ok` até o merge (D1);
  - as seis paradas do D2, cada uma com o comando ou sinal que a detecta (`[design]` no relato do revisor, `exigir` recusando por teto de tentativas, estado `flaky`, `gate-teto-despachos`, exit 69, `publicar-branch` com exit 3 listando arquivo fora de `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `CHANGELOG.md` e da linha do selo no `README.md`);
  - `PushNotification` de uma linha em cada parada e no fim, nunca em progresso (D3);
  - `estado.cjs decidir` em vez de pergunta, com a exceção da `D<n>` (D4), e a seção de `estado.cjs decididos` colada no corpo do PR;
  - agente em segundo plano (D6);
  - `integrar-tarefa.cjs` e `rodar-longo.cjs` (D7).
- **Ponteiros.** `executar/SKILL.md`, `revisar/references/laco.md` e `fechar/SKILL.md` apontam para `modo-autonomo.md` nos pontos em que hoje mandam esperar o usuário. `regra-16.md` registra a exceção da D4, limitada à chave ligada e ao trecho de `plano ok` até o merge. Nenhum `SKILL.md` passa de 16384 B.
- **README, CHANGELOG e versão.** O README cita a chave e os três comandos novos. O CHANGELOG tem a 1.66.0, e a versão é 1.66.0 nos dois `plugin.json` e no selo. As três baterias novas estão em `baterias-obrigatorias.txt`. A âncora do `fechar` em `contrato-plugin-codex.cjs` é medida de novo.

Cada comando e flag citado existe nos scripts. Provado por `bash scripts/testa-teto-skills.sh`, `bash scripts/testa-versao.sh`, `bash scripts/testa-plugin-codex.sh`, `bash scripts/testa-varrer-baterias.sh` e `node scripts/orcamento.cjs` saindo 0.

Emenda (executar, tarefa 1, 2026-10-13): na integração, o `integrar-tarefa.cjs` passava o worktree do fluxo como `--repo-principal` do `conferir-entrega`. Só que o `--sujo-antes` vem do checkout principal, e com isso qualquer arquivo sujo no worktree do fluxo reprovava toda entrega. O padrão passou a ser o checkout principal (o pai do `git-common-dir`), e entrou a flag opcional `--repo-principal`. A bateria da tarefa roda num repo-caixa em que os dois coincidem, então o caso do worktree vinculado fica para o revisor.

Emenda (revisar, volta 1, 2026-10-13): o revisor reprovou com 8 achados. Mudou o que as tarefas 1 e 2 entregam, sem mudar os arquivos:
- Tarefa 1: o passo 2 deixou de ser `cherry-pick --no-commit` do HEAD do agente e virou `git apply --index` do diff `base..HEAD`. Assim entram todos os commits do agente, e uma entrega que não encaixa é recusada sem deixar conflito. Antes do apply, o índice com stage prévio é recusado (`indice-sujo`). Se a branch já tem o commit com o trailer da tarefa, o script retoma do `marcar`. Falha ao remover o worktree do agente não é mais exit 69: vira `"worktree_removido":false` com exit 0. A bateria ganhou os quatro cenários.
- Tarefa 2: o exit vai também para `<arq>.exit`, e o `estado` lê dali, então uma linha `exit N` impressa pelo comando não é confundida com o fim. Com o vigia do `.pid` morto e sem `.exit`, o `estado` diz `morto` (exit 4). O alvo de mutação passou para a linha que grava o `.exit`.

Emenda (revisar, volta 2, 2026-10-13): na tarefa 1, a retomada só reconhece um commit com o trailer feito depois da `--base` (`base..HEAD`). Assim, um redespacho da mesma tarefa no laço integra a correção em vez de ser tomado por retomada. A retomada também não exige mais o worktree do agente. O `desfazer` lê os caminhos com `-z`, então caminho com acento ou espaço sai na recusa. A bateria ganhou os três cenários.

Emenda (rodada extra, 2026-10-14, liberada pelo Luís; impasse em `docs/rainforest/portoes/2026-10-13-executar-autonomo-impasse.md`): na tarefa 1, a retomada com o worktree do agente presente confere com `git apply --check -R --cached` que a entrega do agente já está no HEAD. Se não estiver (base velha, fluxo rebaseado), recusa no passo `retomada` e o worktree fica. A recusa remove as pastas que ficaram vazias. Sem o worktree, a branch do agente não tem como ser achada pelo nome, e o script avisa no stderr para apagá-la à mão.

Emenda (fechar, CI do PR #520, 2026-10-14): o CI pegou três baterias vizinhas que a mudança afetou e que o teste local não rodou.
- O `laco.md` passou de 100 linhas e ganhou o bloco de índice (`testa-indice-referencias`).
- A exceção da D4 aumentou a regra 16 em 405 B. Os números fixados em `hooks/testa-abertura-mod-config.sh` foram para 33246 (elaborações) e 39168 (regras), ainda abaixo do teto de 40960.
- O `testa-rodar-longo.sh` ganhou o `trap ... EXIT` do `mktemp -d` (`testa-sandbox-com-trap`).

A tarefa 4 passa a incluir `hooks/testa-abertura-mod-config.sh`.
