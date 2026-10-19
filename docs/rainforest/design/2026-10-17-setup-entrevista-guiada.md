# /setup vira entrevista guiada

## Objetivo
Na primeira vez que o rainforest roda numa máquina, o `/setup` deixa de despejar 43 chaves
e passa a entrevistar: uma pergunta por vez, só o que é decisão de quem instala, com opções
tiradas da máquina real, e grava tudo de uma vez no fim, depois do diff. Quem já configurou
continua com o estado e muda uma parte.

Colhe a ideia `setup-vira-entrevista-guiada-como-a-do-ratosos`. Procedência: o `/setup` do
kit RatosOS (`ratos-os-framework-3b80c81`, `.claude/skills/setup/SKILL.md`, lido no código)
dá a forma da entrevista; o contrato de passo da skill `build` do
`austinmarchese/buildpartner-plugin` (`relatorios/2026-10-17-buildpartner-plugin.md`) dá o
como andar cada passo.

## Decisões fechadas
- **D1 — A entrevista é o caminho da primeira vez** (pasta de dados inexistente, ou `nivel: plugin`). Setup já feito abre com "refazer ou mudar uma parte?" — porquê: quem já configurou não deve atravessar a entrevista para trocar uma chave.
- **D2 — O `setup.cjs` segue sendo o motor; só a skill é reescrita** — porquê: baterias, `/saude` e mensagens de gate apontam para o `setup.cjs` e seus flags; trocar o motor quebra os três sem ganho.
- **D3 — A entrevista pergunta só o que algum hook ou script lê**: primeiro foco (`FOCO.md`), estratégia (`ESTRATEGIA.md`, lida por `foco-session-start.cjs` e `contexto-sessao.cjs`), idioma, projetos (`projetos.json`) e chaves. Identidade visual, pastas por perfil e importação de outro assistente ficam fora — porquê: arquivo gerado que ninguém lê é configuração morta, e a regra das três portas (escreve, mostra, checa) cobra isso.
- **D4 — Vira pergunta só a chave que depende de ferramenta externa ou de preferência pessoal** (vigias, pontes Codex/Gemini, conselho, WhatsApp, Sabiá, idioma, `fechar-mergear`, `executar-autonomo`). A ferramenta é detectada antes, em silêncio, e só se pergunta o que existe. Gates de segurança ficam ligados sem pergunta e aparecem no resumo final — porquê: 43 perguntas ninguém responde, e gate desligável por entrevista é convite a desligar.
- **D5 — Como andar o passo**: uma pergunta por turno (`AskUserQuestion`), opções geradas da máquina; antes de cada uma, o que já está configurado vira "manter / ajustar / refazer"; nada é gravado durante a entrevista — tudo de uma vez no fim, depois do diff; a conferência roda o `setup.cjs` de novo e lê a saída — porquê: entrevista abandonada no meio não deixa configuração pela metade, e "nada gravado sem ele ter visto" é a condição de parada que o setup já tem. A conferência pela saída real é a peça do buildpartner.
- **D6 — `vigias` vira cinco chaves** (`vigia-batedor-repos`, `vigia-jardineiro-ideias`, `vigia-revisao-bimestral`, `vigia-sentinela-foco`, `vigia-tickets`), e `vigias` fica como interruptor geral: ronda roda só com a geral **e** a dela ligadas — porquê: hoje calar uma ronda exige desligar as cinco; manter a geral não quebra quem já tem `vigias` gravado.
- **D7 — A tabela de chaves da `skills/setup/SKILL.md` é checada contra o `CHAVES` de `hooks/lib/config.cjs` por um conferidor** — porquê: passou de 3 de 8 para 5 de 43 em dois meses; à mão não segura.
- **D8 — Ordem da entrevista**: pasta de dados → idioma → projetos → ferramentas detectadas (pontes, conselho, integrações, vigias) → jeito de fechar (`fechar-mergear`, `executar-autonomo`) → estratégia → primeiro foco → resumo com diff → gravar → conferir — porquê: do que é da máquina ao que é pessoal; o foco por último entrega direto ao `/foco`, que segue dono da escrita do `FOCO.md`.
- **D9 — Primeira vez grava no escopo `usuario`**; `projeto` só aparece no modo "mudar uma parte", com o aviso de que pode ir para o commit — porquê: o padrão já é `usuario`, e quem instala ainda não está configurando um repo.
- **D10 — Pré-preenchimento só de fato da máquina**: projetos sugeridos das pastas de `~/.claude/projects` que existem em disco e são repo git; idioma sugerido da língua das últimas conversas. Nunca se copia texto de CLAUDE.md nem de memória — porquê: opção real poupa digitação; copiar CLAUDE.md muda regra de lugar sem dono.
- **D11 — `setup.cjs` ganha `--plano-entrevista` e `--aplicar <json>`**: o primeiro devolve JSON com estado atual de cada chave, o que detectou e o que perguntar; o segundo grava, e com `--ensaio` só mostra o diff. A skill só conversa — porquê: detecção e gravação determinísticas são testáveis por bateria; na prosa da skill, não.
- **D12 — Cada chave do `CHAVES` ganha o campo `entrevista`**: `{ grupo, detectar }` ou `null` explícito. O conferidor de D7 recusa chave sem o campo — porquê: é o critério que a ideia pedia ("a lista cresce, com qual critério?"); sem trava, a próxima chave nasce fora, como `vigias`.
- **D13 — Estratégia é pergunta opcional** ("quer declarar suas frentes agora?"); com resposta, gera `ESTRATEGIA.md` de modelo curto — porquê: é lida na abertura, mas quem começa raramente tem frentes, e pergunta obrigatória vira resposta inventada.

## Avaliado e descartado
- **Conteúdo de contexto de negócio do RatosOS** (nome, negócio, tom, identidade visual, equipe, perfil de pastas, prompt de exportação do ChatGPT): lido no `SKILL.md` do kit; nenhum hook do rainforest consome esses campos — gerariam arquivos sem leitor (D3).
- **Gravar a cada passo, como o `build` do buildpartner**: no buildpartner cada passo é uma mudança autocontida no projeto; aqui as respostas compõem uma configuração só, e gravar em pedaços deixa estado parcial em entrevista abandonada (D5).
- **Reescrever o motor**: o `setup.cjs` é chamado por nome em mensagens de gate e no `/saude` (D2).

## Fora de escopo
- O "perfil 2e" do cabeçalho de abertura (`hooks/lib/contexto-sessao.cjs:1138`) é texto fixo, não configuração; torná-lo configurável é outro trabalho.
- Recomendar MCP, hook ou skill para o projeto: segue com a `claude-automation-recommender`, como o `SKILL.md` atual já diz.
- Entrevista no Codex/Gemini: o `/setup` é do Claude Code; a ponte não leva `AskUserQuestion`.
- A frente irmã `repo-de-contexto-para-os-repos-de-trabalho` (rodar o RatosOS num repo próprio).

## Varredura
docs/rainforest/varredura/2026-10-17-setup-entrevista-guiada.txt — nenhuma Issue, PR ou branch concorrente. Achou as duas ideias irmãs (`repo-de-contexto-para-os-repos-de-trabalho`, que ficou fora de escopo, e `configuracao-nova-nasceu-fora-do-lugar-de-configuracao`, colhida, cuja regra das três portas virou o critério de D3 e D12) e a entrevista da `/ponte`, que já grava `projeto.md` e é a prévia mais próxima no repo.

## Em aberto
