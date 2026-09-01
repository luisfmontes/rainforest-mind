# Plano: Segunda opinião cross-model no `revisar`

Design: docs/rainforest/design/segunda-opiniao-cross-model.md
Base: `cc1db6a` (ponta da `origin/main`, 0.79.0)

## O que não pode quebrar

- `scripts/testa-conselho.sh` continua verde nas 29 casos — a extração é
  refatoração, não mudança de comportamento do conselho.
- Nenhuma bateria chama Codex ou Gemini reais: fixture sempre (D7).
- Nenhuma dependência npm entra; `child_process` e `path` puros.
- Credencial nunca entra em arquivo versionado — `GEMINI_API_KEY` só por env.
- `scripts/estado.cjs` e o motor de portões não são tocados.
- O agente `rainforest-mind:revisor` continua sendo o revisor primário: o
  externo entra ao lado, nunca no lugar.

## Tarefas

### 1. Transporte de CLI externo em `hooks/lib`, com bateria própria [tipo: implementar]
atende: D1, D3, D7
arquivos: `hooks/lib/cli-externo.cjs`, `scripts/testa-cli-externo.sh`, `scripts/fixtures/cli-externo/*.cjs`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `hooks/lib/cli-externo.cjs`
  de: a passagem do conteúdo por `input:` no `spawnSync` (stdin)
  para: concatenar o conteúdo no fim do `cmd`, como argumento
  bateria: `bash scripts/testa-cli-externo.sh`
  fixture: caso `prompt-com-aspas-e-quebra-de-linha` — fixture que ecoa o stdin recebido; com prompt contendo `"` e quebra de linha, o eco tem de bater byte a byte com a entrada
pronto quando: `hooks/lib/cli-externo.cjs` exporta `rodarCli({ cmd, entrada, timeoutMs, env })` → `{ status, stdout, stderr }` e `extrairJson(stdout)` → objeto ou `null`, no padrão do diretório (`module.exports` na última linha); `bash scripts/testa-cli-externo.sh` sai 0 cobrindo os três eixos, e cada uma das **três mutações declaradas** deixa a bateria vermelha nomeando o caso — (a) stdin virando argumento quebra `prompt-com-aspas-e-quebra-de-linha`; (b) remover o `timeout` do `spawnSync` quebra `cli-que-trava-e-cortado` (fixture que dorme além do teto); (c) tirar o primeiro ramo da regex dupla quebra `json-cercado-por-crase`. Provado com o comando e a saída dos quatro rodares (verde + 3 vermelhos) colados no relato.

### 2. Adaptadores Codex e Gemini viram wrapper fino [tipo: implementar]
atende: D2
arquivos: `scripts/conselho.cjs`, `scripts/testa-conselho.sh`, `scripts/fixtures/conselho/*.cjs`
depende de: 1
paralela: nao
mutacao:
  arquivo: `scripts/conselho.cjs`
  de: o guard `if (!process.env.GEMINI_API_KEY)` no início do `adaptadorGemini`
  para: seguir sem a credencial
  bateria: `bash scripts/testa-conselho.sh`
  fixture: caso `gemini-sem-credencial-falha` — com `GEMINI_API_KEY` vazia, `node scripts/conselho.cjs adaptador-gemini <prompt> <saida>` tem de sair ≠ 0 **sem criar** o arquivo de saída
pronto quando: `adaptadorCodex` e `adaptadorGemini` não contêm mais `spawnSync` nem regex de JSON — só o comando, o guard de credencial do Gemini e a chamada a `rodarCli`/`extrairJson`; `grep -c spawnSync scripts/conselho.cjs` cai de 4 para 2 (as duas do orquestrador, que a tarefa 3 remove); `bash scripts/testa-conselho.sh` continua com as 29 casos verdes. Provado por `git diff --stat`, pelo `grep` e pela saída da bateria colados.

### 3. As duas cópias do spawn no orquestrador consomem o helper [tipo: implementar]
atende: D2
arquivos: `scripts/conselho.cjs`, `scripts/testa-conselho.sh`
depende de: 2
paralela: nao
mutacao:
  arquivo: `scripts/conselho.cjs`
  de: o `timeoutMs` repassado ao `rodarCli` em `executarPareceres`
  para: omitir o campo, deixando a chamada sem teto de tempo
  bateria: `bash scripts/testa-conselho.sh`
  fixture: caso `membro-que-trava-e-cortado` — fixture que dorme além do teto; a fase tem de reprovar por tempo em vez de pendurar
pronto quando: `grep -c 'spawnSync' scripts/conselho.cjs` devolve 0 e `grep -c 'cmd.exe' scripts/conselho.cjs` devolve 0 — o padrão de shell por plataforma existe uma vez só no repo, em `hooks/lib/cli-externo.cjs`; `bash scripts/testa-conselho.sh` verde nas 29 casos. Provado pelos dois `grep` e pela saída da bateria.

### 4. Segunda opinião: caminho próprio, com contrato de entrada e veredito de uma linha [tipo: implementar]
atende: D4, D5, D7
arquivos: `scripts/segunda-opiniao.cjs`, `scripts/testa-segunda-opiniao.sh`, `scripts/fixtures/segunda-opiniao/*.cjs`
depende de: 1
paralela: sim
mutacao:
  arquivo: `scripts/segunda-opiniao.cjs`
  de: a recusa quando a última linha da saída do modelo externo está fora do vocabulário fechado de veredito
  para: aceitar qualquer última linha, tratando ausência de veredito como concordância
  bateria: `bash scripts/testa-segunda-opiniao.sh`
  fixture: caso `veredito-fora-do-vocabulario` — fixture que devolve prosa sem linha de veredito; o comando tem de sair ≠ 0 nomeando a linha recebida
pronto quando: `node scripts/segunda-opiniao.cjs --base <sha> --head <sha> --criterio <arquivo>` monta o prompt com `git diff <base>...<head>` (três pontos), o critério falsificável e o commit-base, chama o CLI externo por `rodarCli` e devolve **uma linha** do vocabulário fechado; entrada sem `--base`/`--head` recusa; diff vazio recusa (o mesmo "sem diff, sem revisão" do `revisar`). Provado por três rodares contra fixture — concorda, discorda, veredito inválido — com comando e saída colados, e por `git diff <base>...<head> | wc -l` batendo com o que o prompt recebeu.

### 5. Falha fechada e registro da divergência com motivo [tipo: implementar]
atende: D6, D5
arquivos: `scripts/segunda-opiniao.cjs`, `scripts/testa-segunda-opiniao.sh`, `scripts/fixtures/segunda-opiniao/*.cjs`
depende de: 4
paralela: nao
mutacao:
  arquivo: `scripts/segunda-opiniao.cjs`
  de: o ramo que sai ≠ 0 quando o modelo externo ligado está indisponível (exit ≠ 0, saída vazia ou timeout)
  para: sair 0 registrando "segunda opinião indisponível"
  bateria: `bash scripts/testa-segunda-opiniao.sh`
  fixture: caso `externo-indisponivel-reprova` — fixture que sai 1 sem escrever nada; o comando tem de sair ≠ 0 citando o modelo
pronto quando: modelo ligado e indisponível **reprova** em vez de seguir — os três modos (exit ≠ 0, stdout vazio, estouro de timeout) saem ≠ 0 com motivo não vazio; e o registro da divergência exige motivo escrito, recusando registro vazio. Provado pelos quatro cenários rodados contra fixture, com comando e saída colados.

### 6. O `revisar` passa a oferecer a segunda opinião, e a documentação acompanha [tipo: documentar]
atende: D4, D6
arquivos: `skills/revisar/SKILL.md`, `README.md`, `agents/revisor.md`
depende de: 5
paralela: nao
mutacao: n/a
  motivo: tarefa de documentação — não há comportamento a inverter; o que a torna falsificável é o texto citar comando que existe, conferido rodando cada comando citado.
pronto quando: `skills/revisar/SKILL.md` descreve o passo opcional da segunda opinião (quando roda, o que entra, que a janela arbitra, e que discordância rejeitada vai ao log com motivo), o `README.md` lista `hooks/lib/cli-externo.cjs` e `scripts/segunda-opiniao.cjs`, e `agents/revisor.md` deixa claro que o externo não substitui o revisor. Provado rodando **cada comando citado nos três arquivos** e colando a saída — comando citado que não existe reprova a tarefa.
