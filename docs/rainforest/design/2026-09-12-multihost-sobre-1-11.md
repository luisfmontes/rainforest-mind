# Rainforest Mind multihost sobre a versão 1.11

## Objetivo

Reaplicar a integração nativa do Codex sobre o Rainforest Mind `1.11.0` sem
bifurcar o produto, preservando Claude, Codex e o futuro Gemini no mesmo
repositório. A entrega parte da `main` atual, mantém o núcleo compartilhado e
produz evidência nova de instalação — a prova da piloto `1.7.0` é referência
histórica, não aceite desta versão.

## Decisões fechadas

- **D1 — Staging total é regra do núcleo compartilhado** — porquê: comandos semanticamente equivalentes a `git add -A` devem receber a mesma decisão em todos os hosts; o adaptador Codex traduz protocolo, não redefine a política do produto.
- **D2 — O inventário de skills é descoberto dinamicamente** — porquê: a `1.11.0` já contém 19 skills e novas skills não devem exigir trocar uma constante; o contrato valida cada `skills/*/SKILL.md` encontrado.
- **D3 — O manifesto Claude permanece a fonte canônica de metadados nesta rodada** — porquê: `name`, `version`, `description` e `author` já têm uma origem estável; criar um terceiro manifesto neutro agora aumentaria o escopo sem resolver uma falha observada.
- **D4 — Gemini permanece adiado nesta entrega** — porquê: o produto e o repositório já são únicos para Claude, Codex e Gemini, mas esta fatia comprova somente o adaptador Codex; nenhum manifesto, hook ou payload Gemini será inventado.
- **D5 — A versão 1.11 recebe documentos e evidências próprios** — porquê: design, plano, estado e portão da piloto `1.7.0` descrevem outra árvore e outro cache; eles serão referenciados pelo commit `c71ecd01a73ab9208c981ff2d1eea5f6378434d7`, não importados como estado atual.
- **D6 — O delimitador `--` preserva a semântica de pathspec** — porquê: `git add -- "-A"` nomeia um caminho e permanece permitido; `git add "-A"` usa a opção de staging total e é bloqueado, inclusive quando aparece depois de um Git inofensivo dentro de wrapper.
- **D7 — O portão global compara as versões Claude e Codex** — porquê: depois de existir um segundo manifesto nativo, a publicação não pode ficar verde com versões divergentes.
- **D8 — O marketplace local distribui a raiz do repositório** — porquê: `source.path: "./"` materializa o produto único; uma subpasta ou cópia aninhada recriaria duas fontes do mesmo plugin.
- **D9 — Cachebuster é somente instrumento de desenvolvimento** — porquê: iterações locais usam `1.11.0+codex.<token>`, mas o portão final reinstala `1.11.0` e exige igualdade byte a byte entre commit e cache, inclusive do manifesto.
- **D10 — A adaptação será reaplicada como diff mínimo sobre a main 1.11** — porquê: o merge entre as árvores alcança 209 caminhos e cherry-picks em série carregam hashes, contagens e documentos da `1.7.0`; arquivos totalmente novos servem como referência, enquanto arquivos existentes preservam o conteúdo atual.

## Avaliado e descartado

- Fazer merge da branch `codex/piloto-rainforest`: descartado porque o diff entre as árvores alcança 209 caminhos e mistura evolução independente fora da fatia Codex.
- Cherry-pick da série completa da piloto: descartado porque os commits congelam 18 skills, hashes de corpos antigos, versão `1.7.0` e evidência do cache correspondente.
- Copiar integralmente os quatro `SKILL.md` da piloto: descartado porque `fechar`, `modo-dev` e `regua` ganharam conteúdo na `1.11.0`; somente o YAML necessário será normalizado, com o corpo atual ancorado byte a byte antes da edição.
- Congelar o contrato em exatamente 19 skills: descartado porque repetiria o defeito que tornou a contagem 18 obsoleta; a lista real do pacote é a entrada do teste.
- Criar agora uma fonte neutra adicional de metadados: descartado por YAGNI; o contrato de igualdade com o manifesto Claude cobre a divergência observada e o portão global impedirá versões diferentes.
- Promover a instalação `1.7.0` como prova da `1.11.0`: descartado porque evidência instalada não atravessa bump de versão nem mudança de bytes.

## Fora de escopo

- Criar adaptador, manifesto ou hook Gemini nesta entrega.
- Converter comandos ou agentes Claude em novas superfícies Codex além da skill e do gate de staging já escolhidos.
- Carregar `hooks/hooks.json` inteiro no Codex ou modificar o comportamento dos demais hooks Claude.
- Publicar release, enviar branch, abrir PR ou remover a piloto `1.7.0` antes de a nova instalação `1.11.0` passar por execução, revisão e verificação.
- Reorganizar toda a metadata do produto em um novo formato neutro.

## Em aberto

Nenhuma decisão de design permanece aberta. O plano deve transformar estas dez
decisões em tarefas falsificáveis, começando por contratos vermelhos sobre a
árvore `a338dd02ad495f87a66d84af2ab24eab3d2660b8` e preservando como referência o
mapa `docs/rainforest/mapas/2026-09-12-multihost-sobre-1-11.md`.
