# Rainforest Mind multihost sobre a versão 1.13.2

## Objetivo

Reaplicar a integração nativa do Codex sobre o Rainforest Mind `1.13.2` sem
bifurcar o produto, preservando Claude, Codex e o futuro Gemini no mesmo
repositório. A entrega parte da `main` atual, mantém o núcleo compartilhado e
produz evidência nova de instalação — a prova da piloto `1.7.0` é referência
histórica, não aceite desta versão.

## Decisões fechadas

- **D1 — Staging total é regra do núcleo compartilhado** — porquê: comandos semanticamente equivalentes a `git add -A` devem receber a mesma decisão em todos os hosts; o adaptador Codex traduz protocolo, não redefine a política do produto.
- **D2 — O inventário de skills é descoberto dinamicamente** — porquê: a `1.13.2` contém 19 skills e novas skills não devem exigir trocar uma constante; o contrato valida cada `skills/*/SKILL.md` encontrado.
- **D3 — O manifesto Claude permanece a fonte canônica de metadados nesta rodada** — porquê: `name`, `version`, `description` e `author` já têm uma origem estável; criar um terceiro manifesto neutro agora aumentaria o escopo sem resolver uma falha observada.
- **D4 — Gemini permanece adiado nesta entrega** — porquê: o produto e o repositório já são únicos para Claude, Codex e Gemini, mas esta fatia comprova somente o adaptador Codex; nenhum manifesto, hook ou payload Gemini será inventado.
- **D5 — A versão corrente recebe documentos e evidências próprios** — porquê: design, plano, estado e portão da piloto `1.7.0` descrevem outra árvore e outro cache; eles serão referenciados pelo commit `c71ecd01a73ab9208c981ff2d1eea5f6378434d7`, não importados como estado atual. O slug preserva `1-11` porque o fluxo começou nessa base, passou pela `1.12.0` e foi reancorado sobre `1.13.2` quando a `main` avançou durante a execução.
- **D6 — O delimitador `--` preserva a semântica de pathspec** — porquê: `git add -- "-A"` nomeia um caminho e permanece permitido; `git add "-A"` usa a opção de staging total e é bloqueado, inclusive quando aparece depois de um Git inofensivo dentro de wrapper.
- **D7 — O portão global compara as versões Claude e Codex** — porquê: depois de existir um segundo manifesto nativo, a publicação não pode ficar verde com versões divergentes.
- **D8 — O marketplace local distribui a raiz do repositório** — porquê: `source.path: "./"` materializa o produto único; uma subpasta ou cópia aninhada recriaria duas fontes do mesmo plugin.
- **D9 — Cachebuster é somente instrumento de desenvolvimento** — porquê: iterações locais usam `1.13.2+codex.<token>`, mas o portão final reinstala `1.13.2` e exige igualdade byte a byte do payload de produto. A projeção exclui somente os sete documentos de governança desta entrega (`docs/HANDOVER-CODEX.md`, design, plano, estado, portão, mapa da fatia e `docs/rainforest/mapas/COBERTURA.md`): eles registram a prova depois que o cache existe e não são lidos pelo runtime. Exigir seus bytes criaria regressão infinita, porque cada commit da evidência tornaria a própria instalação recém-provada obsoleta.
- **D10 — A adaptação será reaplicada como diff mínimo sobre a main corrente** — porquê: o merge entre as árvores da piloto alcança 209 caminhos e cherry-picks em série carregam hashes, contagens e documentos da `1.7.0`; a entrega foi reancorada sobre `068468fb956b8d606e9af1800aaa91dd399fdeb8`, e o rebase descartou o commit de staging já incorporado upstream com conteúdo idêntico.
- **D11 — Artefatos derivados pelo host não viram uma segunda fonte no repo** — porquê: ao instalar a raiz única, o Codex materializa `.codex-plugin/migrated-command-skills/source-command-saude/SKILL.md` a partir de `commands/saude.md`. O portão compara estritamente todo arquivo rastreado fora da lista fechada de governança da D9 e aceita como extra somente essa saída derivada, com caminho, origem e hash registrados; versioná-la duplicaria o corpo do comando e violaria o núcleo único.

## Avaliado e descartado

- Fazer merge da branch `codex/piloto-rainforest`: descartado porque o diff entre as árvores alcança 209 caminhos e mistura evolução independente fora da fatia Codex.
- Cherry-pick da série completa da piloto: descartado porque os commits congelam 18 skills, hashes de corpos antigos, versão `1.7.0` e evidência do cache correspondente.
- Copiar integralmente os quatro `SKILL.md` da piloto: descartado porque `fechar`, `modo-dev` e `regua` ganharam conteúdo depois da piloto; somente o YAML necessário foi normalizado, com o corpo atual ancorado byte a byte antes da edição.
- Congelar o contrato em exatamente 19 skills: descartado porque repetiria o defeito que tornou a contagem 18 obsoleta; a lista real do pacote é a entrada do teste.
- Criar agora uma fonte neutra adicional de metadados: descartado por YAGNI; o contrato de igualdade com o manifesto Claude cobre a divergência observada e o portão global impedirá versões diferentes.
- Promover instalações `1.7.0` ou `1.12.0` como prova da `1.13.2`: descartado porque evidência instalada não atravessa bump de versão nem mudança de bytes.
- Versionar a skill migrada gerada pelo Codex: descartado porque duplicaria `commands/saude.md` e tornaria um detalhe interno do host uma segunda fonte do produto.

## Fora de escopo

- Criar adaptador, manifesto ou hook Gemini nesta entrega.
- Converter comandos ou agentes Claude em novas superfícies Codex além da skill e do gate de staging já escolhidos.
- Carregar `hooks/hooks.json` inteiro no Codex ou modificar o comportamento dos demais hooks Claude.
- Publicar release, enviar branch, abrir PR ou remover a piloto `1.7.0` antes de a nova instalação `1.13.2` passar por execução, revisão e verificação.
- Reorganizar toda a metadata do produto em um novo formato neutro.

## Em aberto

Nenhuma decisão de design permanece aberta. O plano deve transformar estas onze
decisões em tarefas falsificáveis. Os três primeiros contratos nasceram sobre
`a338dd02ad495f87a66d84af2ab24eab3d2660b8`; antes da tarefa 4, os 12 commits
locais foram reaplicados sem conflito sobre `cf1ad7689f84428eb0b10943c0f1cf1a662b8faf` e depois reancorados sobre `068468fb956b8d606e9af1800aaa91dd399fdeb8`, preservando como referência o
mapa `docs/rainforest/mapas/2026-09-12-multihost-sobre-1-11.md`.
