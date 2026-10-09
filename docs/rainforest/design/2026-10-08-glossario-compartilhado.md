# Glossário de domínio compartilhado por repo (GLOSSARIO.md)

## Objetivo

Dar a cada repositório um `GLOSSARIO.md` versionado com os termos de domínio, lido sob
demanda pelo agente de quem trabalhar ali (Claude com ou sem o plugin, Codex), para que o
conhecimento de domínio deixe de morar só na memória pessoal de uma máquina. O piloto é o
próprio rainforest-mind; o repo de trabalho da squad (pedido do chefe: contexto
compartilhado entre funcionários) entra só depois da conversa do Luís com ele.

## Decisões fechadas

- **D1 — Leitor principal é o agente de qualquer dev do repo, consultando sob demanda quando um termo aparece; humanos leem o mesmo arquivo no GitHub.** — porquê: injetar o arquivo inteiro na abertura bate no teto de bytes por hook que já mordeu o SessionStart; consulta pelo assunto é o modelo da memória por assunto (1.49.0).
- **D2 — Só o glossário entra nesta entrega; a ideia `repo-de-contexto-para-os-repos-de-trabalho` (23/08) segue plantada.** — porquê: o `ao_colher` dela começa por outro experimento (sentir a entrevista do `/setup` do RatosOS num repo vazio) e os mapas de código já têm a `arqueologia`; juntar dobra o escopo sem dependência real.
- **D3 — Verbete é termo de domínio: o que é, onde mora, cenário real. Pegadinha de ferramenta e vocabulário pessoal do Luís ficam fora.** — porquê: das 101 memórias `reference` da conta de trabalho no repo da squad, a maioria é pegadinha (`compilar_derruba_todo_mundo`, `catch_sem_variavel_aborta_build`); com elas o glossário vira um segundo `MEMORY.md`, e o pedido é entender o domínio.
- **D4 — Verbete migrado da memória pessoal deixa a memória como ponteiro para o verbete, sem cópia.** — porquê: duas fontes do mesmo fato divergem em silêncio, o mesmo defeito das duas `CLAUDE.md` de escopo usuário em 2026-08-10.
- **D5 — Piloto no rainforest-mind; o repo de trabalho da squad só depois da conversa com o chefe.** — porquê: repo dele, commit solo permitido, e com vocabulário de domínio real já repetido ("fluxo, não esteira"); repo compartilhado da squad não recebe commit solo.
- **D6 — O arquivo se chama `GLOSSARIO.md`, na raiz, em maiúsculas como `AGENTS.md` e `CLAUDE.md`.** — porquê: diz o conteúdo a quem nunca ouviu da ideia, segue o português dos repos da squad, e sem acento não vira mojibake em repo gravado em CP-1252. `DOMINIO.md` confunde com domínio de rede e DDD; `TERMOS.md` soa a termos de uso; `GLOSSARY.md` só valeria se o Codex o achasse por convenção, e quem aponta é a `ponte`.
- **D7 — Forma do verbete: termo, definição de uma a duas frases, onde mora (tabela, campo, rotina ou arquivo), um cenário real, e "evite" com os sinônimos errados (ex.: `esteira → fluxo`).** — porquê: o "evite" é o que o `GLOSSARY.md` do mattpocock/skills v1.3 tem e o que três memórias de vocabulário do Luís são ("não diga X, diga Y"); o cenário real cumpre a pergunta obrigatória do brainstorm sobre valores de domínio.
- **D8 — A skill propõe, o Luís aprova, o verbete entra por commit/PR; nada grava sozinho.** — porquê: o arquivo é versionado e, no repo da squad, compartilhado; escrita automática ali vira commit solo em repo coletivo.
- **D9 — Leitura por dois canais existentes: no Claude com o plugin, a injeção por assunto passa a casar os termos do `GLOSSARIO.md` do repo e injeta só os verbetes casados; no Codex ou Claude sem plugin, a `ponte` acrescenta ao `AGENTS.md`/`CLAUDE.md` a linha "termos de domínio: leia `GLOSSARIO.md`".** — porquê: nenhum hook novo; ponteiro é o único mecanismo que o Codex lê.
- **D10 — Skill nova `/glossario` com três ações: `propor` (verbete a partir da conversa), `migrar` (de memória de domínio, que vira ponteiro, D4) e `listar`.** — porquê: encaixar em `/ideia` ou `/feedback` misturaria registro de método com conhecimento de domínio, que têm leitores diferentes.
- **D11 — Gatilho automático único: na regra 13, correção de vocabulário de domínio propõe verbete em vez de gravar memória pessoal; fora isso, a skill é chamada à mão.** — porquê: "explicou pela segunda vez" não tem detector confiável; a correção de vocabulário já é evento capturado, e dela nasceram `dizer-fluxo-nao-esteira` e `vocabulario-enxertar-nao-roubar`.
- **D12 — Semente do piloto: termos do próprio plugin — fluxo e estágios, plantar/colher, acervo, território, enxertar, worktree de agente, portaria; o que vier de memória migra (D4). "Pode aprovar = merge" e "atividade = PSA" ficam na memória pessoal.** — porquê: corte da D3, e é o que um dev novo do plugin precisaria saber.
- **D13 — `conferir-glossario.cjs` na CI recusa verbete sem definição, sem "onde mora" ou sem cenário, e termo duplicado.** — porquê: a injeção da D9 lê o arquivo por máquina; verbete fora do formato deixaria de ser casado em silêncio.

## Avaliado e descartado

- **Injetar o glossário inteiro na abertura** — o payload do SessionStart já estourou o teto de entrega por hook (medido em 2026-08-10: ~2,2 KB entregues de 32 KB); a injeção por assunto existe por causa disso.
- **Nomes `GLOSSARY.md`, `DOMINIO.md`, `TERMOS.md`** — ver D6.
- **Detector de "termo explicado pela segunda vez"** — sem sinal confiável no transcript; substituído pelo evento da regra 13 (D11).

## Fora de escopo

- Repo de contexto próprio do trabalho, `/setup` do RatosOS e ligação com os repos de trabalho (ideia de 23/08, segue plantada).
- Mapas de código dos fontes — é a `arqueologia`.
- Pegadinhas de ferramenta (compilador, arquivo de build) — seguem na memória; outro arquivo compartilhado para elas é conversa futura.
- Piloto em qualquer repo de trabalho da squad — depende da conversa do Luís com o chefe.

## Varredura

docs/rainforest/varredura/2026-10-08-glossario-compartilhado.txt — nenhuma Issue, PR ou branch sobre glossário; o único eco é o design `2026-08-24-camada-obsidian-para-o-harness` (conhecimento vira rota, não migração), que reforça D1 e D9. As ideias casadas foram a própria `glossario-compartilhado-por-repo` e observações de vocabulário (`vocabulario-do-sistema-estreitou-o-pedido`, `obs-2026-09-02-dominio-de-codigo-sem-cenario`), que sustentam D7 e D11.

## Em aberto
- **Achado no executar (2026-10-08), para o `revisar`:** a D4 ("memória vira ponteiro") supõe memória que só define termo. `dizer-fluxo-nao-esteira` e `vocabulario-enxertar-nao-roubar` são também conduta de escrita em qualquer projeto, e o verbete só chega quando o termo aparece no pedido, neste repo — reduzi-las a ponteiro faria a sessão voltar a escrever o termo evitado. Decisão do Luís: as duas ficam inteiras, com uma linha de ponteiro para o verbete, e a tarefa 10 fecha `pulada`.
