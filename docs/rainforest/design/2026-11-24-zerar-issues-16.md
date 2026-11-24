# Rodada 16: gate-pergunta-memoria, integrar-tarefa e mensagem do gate de publicação

## Objetivo

Tirar três erros que apareceram no uso, sem abrir o que cada peça protege:

1. **#731** — `scripts/integrar-tarefa.cjs` recusa no passo `diff` quando a entrega traz arquivo de ~1 MB ou mais. `git()` chama `spawnSync` sem `maxBuffer` (padrão do Node: 1 MiB), o diff passa disso, `status` vem `null` com `ENOBUFS`, e a recusa não mostra o motivo.
2. **#730** — `hooks/gate-pergunta-memoria.cjs` barra o fim de turno ("Stop hook error") por uma pergunta cujo único vocabulário comum com a memória é o nome da branch citado nela.
3. **#723** — `hooks/gate-publicacao-destino.cjs`, num fork com `origin` privado e `upstream` público só para fetch, barra dizendo "visibilidade pública" sem nomear qual remoto é público, e conta o `upstream` mesmo com o push dele desligado (`git remote set-url --push upstream no_push`).

Pedido do Luís em 2026-11-24 ("preciso que resolva os erros que estão acontecendo, da uma olhada e pode seguir pelo fluxo automatico"). A rodada roda em modo autônomo: as decisões abaixo são a recomendada, e as marcadas *(suposição)* ele revisa no PR.

## Decisões fechadas

- **D1 — `integrar-tarefa`: `maxBuffer` de 1 GiB em `git()`, e a recusa mostra o erro do processo.** A função `git()` passa `maxBuffer: 1024 * 1024 * 1024` ao `spawnSync`. Isso cobre os dois pontos que leem diff (o passo 2 e a conferência da retomada). O `recusar` escreve `res.error.code` e `res.error.message` no stderr quando existem.
  - **Porquê:** reprodução da Issue com o mesmo commit, `status null erro ENOBUFS` sem `maxBuffer` e `status 0` com ele. A retomada lê `d.stdout.trim()` para saber se há diff, então gravar direto em arquivo (`--output`) obrigaria dois caminhos de leitura.
  - **Modelo de ameaça:** não muda o que a integração confere; só deixa de recusar por limite de buffer. Um diff acima de 1 GiB volta a recusar, agora com `ENOBUFS` na mensagem.

- **D2 — `gate-pergunta-memoria`: o que nomeia um objeto sai da pergunta antes de contar termos.** Antes de `termosDe(p.texto)`, tiram-se da pergunta (só da pergunta, não da memória): os trechos em código inline (`` `...` ``) e as palavras com forma de caminho ou branch, isto é, com `/` entre caracteres ou com dois hífens ou mais (`a-b-c`). O limiar (`LIMIAR_TERMOS = 3`) não muda.
  - **Emenda de 2026-11-24 (executar, decidida sem o Luís):** sai só a palavra com forma de caminho ou branch (barra entre letras ou dígitos, com ou sem crase). Código inline e nome kebab sem barra ficam: com eles fora, o P1 da bateria (o caso de origem, `.rainforest-gate-off` em prosa) passou a sair 0, porque ali o nome do arquivo é o próprio assunto da memória. O caso da #730 tem barra na branch e continua coberto.
  - **Porquê:** no caso da Issue, os termos que casaram vieram de `refactor/<cliente>-<demanda>`, que também está no nome e no texto da memória do projeto, e a memória não respondia a pergunta (apagar o worktree antigo). O nome do objeto diz *sobre o que* se decide, não *o que* se decide.
  - **Modelo de ameaça:** o gate é um empurrão para ler a memória antes de perguntar, não uma trava de segurança. Fica fora: pergunta cujo assunto só aparece em código inline ou em nome kebab deixa de barrar *(suposição: falso negativo raro e barato; o caso de origem, D6 de `2026-10-28-colheita-observacoes`, é prosa e continua barrando)*.

- **D3 — `gate-publicacao-destino`: o remoto conta pela URL de push, e a mensagem nomeia o remoto público.**
  1. `repositoriosDoGitHub` lê `git remote get-url --push --all <nome>` em vez de `git remote get-url <nome>`. Cada URL de push do GitHub conta; remoto sem URL de push do GitHub (`no_push`, caminho local) não conta como destino publicável.
  2. A função devolve também o nome do remoto de cada `dono/repo`. Quando a visibilidade sai `publica`, a mensagem diz `Repositório: o remoto '<nome>' (<dono/repo>) é público, apurado por 'gh repo view'.`, com todos os remotos públicos achados.
  - **Porquê:** a pergunta da função é "existe destino público ao alcance de um push?" (docblock de `repositoriosDoGitHub`). Remoto com push desligado não está ao alcance. E a mensagem sem o nome fez quem leu concluir que o gate errou a visibilidade do próprio repositório.
  - **Modelo de ameaça:** protege contra texto sensível versionado num repositório que um push publica. Fica fora: quem desliga o push de um remoto público e depois o religa antes do push. A configuração de remotos já estava fora do alcance do gate (remover o remoto tem o mesmo efeito), e o gate de push segue conferindo o destino no momento do `git push`. Sem nenhuma URL de push do GitHub, a visibilidade fica `desconhecida` e barra como hoje.

- **D4 — #722 e #724 ficam fora desta rodada.** As duas são furos de cobertura achados em revisão (staging em massa por script não-shell; máscara de heredoc com continuação de linha), não erro que aparece no uso. A #722 pede mecanismo novo (seguir o arquivo por `cp`/`mv`/`<`, ler spawn em array) e a #724 pede bateria de cada gate que usa `hooks/lib/heredoc.cjs` e revisão de segurança própria.

- **D5 — Versão 2.17.2 (PATCH).** Três consertos sem contrato novo (`CONTRIBUTING.md`). A 2.17.1 é do fluxo `2026-11-18-portaria-publicacao`, que fecha antes deste.

## Avaliado e descartado

- **`git diff --output=<remendo>` no passo 2 (#731):** dispensa o buffer só naquele ponto; a retomada continuaria com o limite. O `maxBuffer` em `git()` cobre os dois.
- **Subir o `LIMIAR_TERMOS` (#730):** não separa nome de objeto de assunto, e perderia o caso de origem, que casa por poucos termos de prosa.
- **Deixar de contar remoto público de fetch sem olhar o push (#723):** reabre o caso de 2026-09-15 do docblock, em que um fork público cadastrado publicava pelo `git push fork main`.

## Fora de escopo

- #722 e #724 (D4).
- A memória que casa por nome de cliente em prosa (sem código nem forma de caminho): segue barrando quando passa do limiar.

## Varredura

docs/rainforest/varredura/2026-11-24-zerar-issues-16.txt. Só as três Issues estão abertas no tema. Do `gate-pergunta-memoria` seguem valendo a D6/D8 de `2026-10-28-colheita-observacoes` e a D2 de `2026-10-29-colheita-pos-2-1-0` (âncoras intactas); a D3 desta última foi a saída do canal do banco (#626). Do `gate-publicacao-destino`, as decisões intactas de `gate-publicacao-gh`, `zerar-issues-4`, `zerar-issues-9` e `zerar-issues` não tocam `repositoriosDoGitHub`. Nenhuma âncora aponta para `scripts/integrar-tarefa.cjs`.

## Em aberto

(nada)

## Pronto quando

- `bash scripts/testa-integrar-tarefa.sh`: caso novo em que o agente commita um arquivo de mais de 1 MiB no escopo da tarefa 1 integra com exit 0; o resto da bateria com 0 falhas.
- `node hooks/testa-gate-pergunta-memoria.cjs`: caso novo com a pergunta da #730 e uma memória que só compartilha os termos da branch sai 0; o P1 (prosa) continua 2.
- `bash hooks/testa-gate-publicacao-destino.sh`: com `origin` privado e `upstream` público, a mensagem nomeia `'upstream'` e o `dono/repo` dele; com o push do `upstream` em `no_push`, sai 0; com o push do `upstream` apontando para o repositório público, sai 2.
