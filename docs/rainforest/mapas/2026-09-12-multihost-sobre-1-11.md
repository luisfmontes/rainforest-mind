# Arqueologia: fatia multihost sobre a versão 1.11

**Data:** 2026-09-12
**Árvore atual:** `a338dd02ad495f87a66d84af2ab24eab3d2660b8` (`codex/multihost-1.11`)
**Referência piloto:** `c71ecd01a73ab9208c981ff2d1eea5f6378434d7` (`codex/piloto-rainforest`)
**Escopo:** os 14 caminhos finais da adaptação multihost e a dependência direta
`hooks/gate-staging-total.cjs`; não é um mapa do repositório inteiro.

## Escala e método

- **CONFIRMADO** — leitura do arquivo citado ou comando Git/runtime reproduzível
  registrado neste mapa.
- **INFERIDO** — consequência técnica provável, ainda não convertida em decisão.
- **LACUNA** — requer decisão de produto ou nova prova no host.

Triagem da fatia: o core atual tem 350 linhas, 9 funções, repetição de 15,8% e
classe `logica`; o contrato piloto tem 982 linhas, 49 funções, repetição de 27%
e classe `logica`. A leitura do contrato foi limitada às âncoras de manifesto,
skills, hook, marketplace, Gemini e dispatcher
(`codex/piloto-rainforest:scripts/testa-plugin-codex.cjs:9-31`,
`:67-270`, `:895-970`). Os quatro `SKILL.md` são documentos pequenos; a triagem
os classificou `indefinido` por terem zero funções, então a passada útil nesta
fatia foi a superfície YAML e o diff do corpo, não uma falsa análise funcional.

## Veredito curto

**CONFIRMADO:** a fonte canônica atual declara `rainforest-mind` versão `1.11.0`
em `.claude-plugin/plugin.json:2-9`. A piloto Codex declara o mesmo nome, mas
versão `1.7.0`, e deriva skills/hook por caminhos da mesma raiz
(`codex/piloto-rainforest:.codex-plugin/plugin.json:2-9`).

**CONFIRMADO (Git):** 10 dos 14 caminhos não existem na árvore 1.11; os quatro
existentes são `skills/fechar`, `modo-dev`, `montar-corpus` e `regua`. O diff
direto completo entre as árvores toca 209 arquivos (4.344 inserções, 15.384
remoções); limitado aos 14 caminhos, toca apenas esses 14 (3.055 inserções, 104
remoções). Portanto as árvores não são equivalentes fora da fatia.

**INFERIDO:** a estratégia tecnicamente mais segura é **reaplicar o diff mínimo
sobre 1.11**, usando a piloto como especificação e evidência histórica. Merge
mistura 209 caminhos; cherry-pick em série traz contratos, hashes e documentos
amarrados à árvore 1.7. Cherry-picks isolados podem servir como fonte mecânica
para arquivos totalmente novos, mas não como estratégia de integração.

## Superfície atual da 1.11

**CONFIRMADO:** o manifesto Claude é a única entrada nativa de plugin nesta
árvore e contém nome, versão, descrição, autor, licença e homepage
(`.claude-plugin/plugin.json:1-10`). Não há `.codex-plugin/plugin.json` nem
`.agents/plugins/marketplace.json` rastreados (consulta `git cat-file -e` no
SHA atual).

**CONFIRMADO:** há 19 diretórios com `skills/*/SKILL.md`. `enxugar` é a skill
adicional em relação à piloto e tem frontmatter próprio
(`skills/enxugar/SKILL.md:1-4`). Quatro das 19 falham no contrato YAML que a
piloto codificou: `fechar`, `modo-dev` e `regua` têm `:` seguido de espaço em
`description` sem aspas (`skills/fechar/SKILL.md:1-4`,
`skills/modo-dev/SKILL.md:1-4`, `skills/regua/SKILL.md:1-4`), e
`montar-corpus` não tem frontmatter (`skills/montar-corpus/SKILL.md:1-5`).

**CONFIRMADO:** a 1.11 já contém pontes para Codex e Gemini — elas geram
`AGENTS.md`/`GEMINI.md`, não instalam o plugin. A própria skill nomeia os três
alvos e o comando Codex (`skills/ponte/SKILL.md:13-43`); as definições dos hosts
ficam em `hooks/lib/ponte-corpo.cjs:122-152`. Também há scripts e hooks com
“codex” no nome, mas nenhum deles é o manifesto/hook nativo dos 14 caminhos.

**CONFIRMADO:** `hooks/hooks.json` é a superfície Claude e hoje possui seis
eventos, iniciados em `hooks/hooks.json:3`, `:38`, `:81`, `:93`, `:128` e
`:152`; são 22 handlers, não os “18 handlers em 5 eventos” registrados pela
piloto (`codex/piloto-rainforest:docs/rainforest/design/2026-09-08-adaptacao-multihost.md:92-100`).

## Conferência dos 14 caminhos

| Caminho | 1.11 | Piloto e aplicação atual |
|---|---|---|
| `.codex-plugin/plugin.json` | ausente | **COLIDE:** estrutura, `skills` e hook dedicado ainda se aplicam, mas `version: 1.7.0` ficou obsoleto; deve derivar `1.11.0` da canônica (`.claude-plugin/plugin.json:2-9`; piloto `:2-24`). |
| `hooks/codex-gate-staging-total.json` | ausente | **APLICA:** registro mínimo de um `PreToolUse`, matcher `^Bash$` e adaptador por `${PLUGIN_ROOT}` (`codex/piloto-rainforest:hooks/codex-gate-staging-total.json:1-15`). **LACUNA:** reconfirmar o matcher no Codex vigente antes da publicação. |
| `hooks/codex-gate-staging-total.cjs` | ausente | **APLICA COM COLISÃO:** é fino e só traduz protocolo (`codex/piloto-rainforest:hooks/codex-gate-staging-total.cjs:10-18`, `:20-64`), mas depende do core divergente descrito abaixo. |
| `skills/fechar/SKILL.md` | presente | **REAPLICAR SÓ YAML:** aspas da linha 3 continuam necessárias; copiar o arquivo piloto apagaria conteúdo novo da 1.11. Diff atual→piloto remove, entre outros, `skills/fechar/SKILL.md:91-97`. |
| `skills/modo-dev/SKILL.md` | presente | **REAPLICAR SÓ YAML:** aspas continuam necessárias; o corpo 1.11 ganhou decisões e mecanismos, portanto substituir pelo piloto regrediria a skill (`skills/modo-dev/SKILL.md:1-16`; piloto `:1-16`). |
| `skills/montar-corpus/SKILL.md` | presente | **APLICA:** o diff é somente adicionar frontmatter antes do corpo atual (`skills/montar-corpus/SKILL.md:1-5`; piloto `:1-10`). |
| `skills/regua/SKILL.md` | presente | **REAPLICAR SÓ YAML:** escapar as aspas e envolver a descrição; copiar o piloto removeria a fronteira de honestidade hoje presente em `skills/regua/SKILL.md:221-252`. |
| `.agents/plugins/marketplace.json` | ausente | **APLICA:** uma entrada local aponta `source.path` para `./`, isto é, o mesmo repo (`codex/piloto-rainforest:.agents/plugins/marketplace.json:1-20`). |
| `scripts/testa-plugin-codex.cjs` | ausente | **COLIDE:** o esqueleto contratual serve, mas exige exatamente 18 skills (`codex/piloto-rainforest:scripts/testa-plugin-codex.cjs:225-236`) e fixa hashes dos corpos 1.7 (`:20-25`). Precisa medir as 19 skills e ancorar os corpos 1.11 antes da edição. |
| `scripts/testa-plugin-codex.sh` | ausente | **APLICA:** wrapper chama o CJS real, propaga exit e cobra os marcadores do adaptador (`codex/piloto-rainforest:scripts/testa-plugin-codex.sh:7-32`); os marcadores devem acompanhar o contrato atualizado. |
| `docs/rainforest/design/2026-09-08-adaptacao-multihost.md` | ausente | **DECISÕES AINDA ÚTEIS, ARTEFATO LITERAL OBSOLETO:** um produto e núcleo neutro continuam explícitos (`:5-27`), mas 18 skills, 18 handlers e a exceção “antes do próximo bump” expiraram (`:18-21`, `:31-32`, `:96-97`, `:233-234`). |
| `docs/rainforest/planos/2026-09-08-adaptacao-multihost.md` | ausente | **OBSOLETO COMO PLANO EXECUTÁVEL:** critérios cobram 18 skills (`:40-77`) e instalação daquela fatia. Deve nascer plano novo depois do brainstorm, não ser marcado como entrega 1.11. |
| `docs/rainforest/estado/2026-09-08-adaptacao-multihost.json` | ausente | **OBSOLETO COMO ESTADO ATUAL:** registra cache e instalação `1.7.0` (`:347-363`, `:619-639`) e 18 skills (`:732-754`). Pode ser preservado apenas como evidência histórica da piloto. |
| `docs/rainforest/portoes/2026-09-08-adaptacao-multihost.md` | ausente | **OBSOLETO COMO PORTÃO 1.11:** prova cache/bytes/execução de `1.7.0` (`:345-383`, `:495-502`). A publicação 1.11 exige nova instalação, novo cache e novos hashes. |

## Mecanismo do gate compartilhado

**CONFIRMADO:** o core 1.11 lê o payload, aceita Bash/PowerShell, segmenta o
comando, resolve o repo e encerra com `2` ao bloquear
(`hooks/gate-staging-total.cjs:273-346`). Suas nove funções estão ancoradas em
`hooks/gate-staging-total.cjs:78`, `:98`, `:120`, `:162`, `:180`, `:185`,
`:209`, `:227` e `:273`.

**CONFIRMADO:** o adaptador piloto chama exatamente esse caminho compartilhado
e traduz exit `2`+stderr em deny JSON (`codex/piloto-rainforest:hooks/codex-gate-staging-total.cjs:36-61`). Portanto a identidade comportamental do core é pré-condição da prova Codex.

**CONFIRMADO:** o core 1.11 descarta argumentos citados em `analisaGit`
(`hooks/gate-staging-total.cjs:120-134`), devolve o primeiro Git encontrado
dentro de wrapper (`:162-176`) e analisa flags sem separar `--`/valor de
mensagem (`:180-198`). A piloto preserva argumentos, continua após Git interno
inofensivo e separa mensagem/opções/pathspecs
(`codex/piloto-rainforest:hooks/gate-staging-total.cjs:119-134`, `:161-175`,
`:183-216`).

Prova runtime sobre dois repositórios temporários equivalentes (os comandos
foram apenas payload, não executados):

| Payload | core 1.11 | core piloto |
|---|---:|---:|
| `git add "-A"` | exit 0 | exit 2 |
| `git add -- "-A"` | exit 0 | exit 0 |
| `bash -c "git status; git add -A"` | exit 0 | exit 2 |
| `git add -A` (controle) | exit 2 | exit 2 |

**INFERIDO:** reaplicar apenas os 14 caminhos produziria um plugin instalável
cujo adaptador funciona, mas com proteção mais fraca que a instalação realmente
verificada na piloto. O brainstorm precisa decidir se as três correções do core
e seus casos em `hooks/testa-gate-staging-total.sh` entram nesta reconciliação;
tecnicamente elas são dependência do mesmo contrato, não uma melhoria lateral.

## Regras implícitas

**Um release tem uma versão canônica, mas hoje só Claude é medido.**
`scripts/testa-versao.sh` lê a versão de `.claude-plugin/plugin.json` e confere
README e um marketplace Claude opcional (`scripts/testa-versao.sh:36-48`,
`:84-98`). **INFERIDO:** ao adicionar o manifesto Codex, ele também deve entrar
nesse portão; confiar apenas no teste Codex permite que o portão global fique
verde com versões divergentes.

**Evidência instalada não atravessa bump.** O portão piloto afirma explicitamente
cache e blobs de `1.7.0` (`codex/piloto-rainforest:docs/rainforest/portoes/2026-09-08-adaptacao-multihost.md:345-383`). **INFERIDO:** código reaplicado pode herdar a hipótese, nunca o veredito de instalação.

## Questões que o brainstorm precisa decidir

1. **Fonte canônica de metadados:** continuar derivando o manifesto Codex do
   manifesto Claude ou criar uma fonte neutra agora que a exceção temporária
   expirou (`codex/piloto-rainforest:docs/rainforest/design/2026-09-08-adaptacao-multihost.md:18-21`, `:233-234`)?
2. **Core do gate:** incorporar nesta fatia as três correções comportamentais da
   piloto, preservando as mudanças 1.11, ou reduzir formalmente o contrato Codex?
3. **Inventário:** o contrato deve cobrar a lista/número atual de 19 skills ou
   descobrir dinamicamente e validar cada `SKILL.md` sem quantidade fixa?
4. **Histórico:** manter design/plano/estado/portão de 1.7 como arquivos históricos
   com rótulo explícito, ou criar documentos 2026-09-12 e deixar os antigos apenas
   na branch piloto?
5. **Fatia do host:** confirmar que somente o gate de staging entra agora e que
   as pontes existentes continuam complementares, não substitutas do plugin.
6. **Gemini:** permanece fronteira futura sem manifesto/hook inventado, conforme
   a decisão piloto (`codex/piloto-rainforest:docs/rainforest/design/2026-09-08-adaptacao-multihost.md:50-52`)?

## Estratégia técnica indicada, sem decisão de produto

1. Usar os arquivos novos da piloto como **referência**, não integrar a branch.
2. Recriar manifesto Codex com os metadados/versionamento decididos para 1.11.
3. Reaplicar frontmatter somente nas quatro linhas de cabeçalho, preservando os
   corpos atuais; ancorar bytes antes.
4. Reconciliar primeiro o core e seus testes, pois o adaptador depende dele.
5. Portar o contrato CJS retirando constantes 1.7/18 e refazendo as âncoras.
6. Produzir novo design/plano/estado/portão e repetir a prova instalada; não
   promover evidência 1.7 a evidência 1.11.

**LACUNA:** este mapa não decide a fonte neutra de metadados, o escopo do core,
o contrato Gemini nem autoriza publicação. Também não valida documentação
oficial vigente do Codex/Gemini; isso pertence ao brainstorm antes do novo
plano.
