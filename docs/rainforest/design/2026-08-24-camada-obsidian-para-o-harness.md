# Camada Obsidian para o harness

## Objetivo

Fazer o conhecimento já escrito chegar no momento da decisão, tirando o Obsidian do
caminho. O corpus existe (24 páginas de wiki, 270 arquivos de livro destilado) e não é
lido: 18 das 24 páginas não têm rota, e o acervo foi construído como interface humana para
um leitor que é máquina. O trabalho é de **roteamento e formato de entrega**, não de
migração de conteúdo — e nem de geração: o corpus de conhecimento **já é gerado**, pela
skill `book-to-skill`, e a forma uniforme das 15 pastas de livro (`livro.md`, `capitulos/`,
`cheatsheet.md`, `glossario.md`, `patterns.md`) é a evidência disso. O que nunca foi
construído é a camada de consumo.

O artefato passa a se chamar **acervo** — coleção mantida para consulta. O termo
"segundo cérebro" nomeava ao mesmo tempo a instância pessoal e o conceito geral, e essa
sobreposição gerou confusão real durante este próprio brainstorm.

## Decisões fechadas

- **D1 — O Obsidian sai inteiro, inclusive como leitor; markdown com `[[link]]` fica como
  formato.** — porquê: o dono não abre o aplicativo nem para ler, então toda decisão de
  desenho que mirava o visualizador (nota de comunidade, layout de vault) perdeu a
  justificativa; o formato sobrevive porque markdown serve tanto a humano quanto a agente,
  e renderiza no GitHub.

- **D2 — O acervo `segundo-cerebro` continua repositório separado e privado.** — porquê: o
  `rainforest-mind` é plugin distribuído a terceiros e o acervo tem material pessoal;
  fundir trocaria um problema de roteamento por um problema de vazamento. O
  `para-aplicado.md` já tinha decidido que nenhum arquivo muda de lugar, e a decisão se
  confirma por um motivo mais forte do que quando foi escrita.

- **D3 — O problema é roteamento, não armazenamento.** — porquê: das 24 páginas de wiki,
  6 têm rota (a tabela sintoma→página da skill `message-standards`, que funciona e foi
  observada disparando) e 18 dependem do gatilho temático da skill `segundo-cerebro`, que
  exige a sessão reconhecer o assunto — o gatilho mais fraco disponível.

- **D4 — A rota se constrói em duas etapas: tabela sintoma→página primeiro, citação da
  página na elaboração de cada regra depois, dentro da issue #73.** — porquê: a tabela é
  barata e já tem precedente funcionando nesta casa; a citação por regra é melhor porque
  põe o ponteiro onde a regra dispara em vez de depender de reconhecimento, mas exige o
  `references/` que a #73 constrói.

- **D5 — Um motor só para os corpora, e o que se padroniza é o schema JSON de nós e
  arestas, não o pacote `graphifyy`.** — porquê: o `graphifyy` é pré-1.0 com release quase
  diário e versão pinada como parte do contrato — amarrar o sistema a ele é amarrar a
  dependência instável de terceiro; já o schema custa o mesmo e não amarra a ninguém. O
  enum `file_type` do próprio schema (`code`, `document`, `paper`, `image`, `rationale`,
  `concept`) mostra que ele foi desenhado para corpus misto, não só para código.

- **D6 — O corpus de conhecimento ganha extrator, mas de transcrição, não de extração.** —
  porquê: o extrator de AdvPL tem 726 linhas porque fonte `.prw` é texto não estruturado e
  a aresta precisa ser inferida; as páginas de wiki já têm `relacionados` no frontmatter e
  `[[link]]` no corpo, ou seja, a aresta está escrita. São dezenas de linhas.

- **D7 — JSON é formato de troca entre estágios; markdown é o artefato consumido.** —
  porquê: um `graph.json` de mais de mil nós obriga a ler o arquivo inteiro para responder
  uma pergunta; nota curta por entidade é progressive disclosure que já funciona com
  `Read` e `grep`. Os dois formatos convivem em pontos diferentes da cadeia
  (`extrator → JSON → build → markdown`), e confundi-los foi erro de comunicação
  desfeito nesta sessão.

- **D8 — A entrega é uma skill que gera o acervo de um corpus — nunca o acervo pessoal de
  ninguém —, hospedada no `rainforest-mind`, com o `graphifyy` como dependência externa
  opcional que a skill confere e recusa sem instalar.** — porquê: skill já é a unidade de distribuição do plugin, não é preciso
  inventar formato de entrega nem manter repositório novo; declarar a dependência mantém o
  plugin leve para quem não a tem e respeita a regra 15 (ferramenta ausente para e
  reporta, instalar pergunta).

- **D9 — O escopo da geração é sempre explícito: `--repo` para o repositório atual, ou
  `--corpus <nome>` para um conjunto declarado no `projetos.json`; sem alvo, recusa.** —
  porquê: "geral da máquina" como varredura implícita misturaria repositório de trabalho,
  código de cliente e acervo pessoal privado no mesmo grafo — exatamente o vazamento que a
  D2 evita. "Geral" existe como vários corpora nomeados, nunca como um "tudo".

- **D10 — Padrão de distribuição de ferramenta própria: a ferramenta mora em repositório
  próprio, o `rainforest-mind` entrega uma skill fina, e a skill confere a dependência e
  recusa em vez de instalar.** — porquê: o padrão apareceu três vezes na mesma sessão
  (toolkit de grafo, Sabiá, MCP do WhatsApp) e o Sabiá já tinha sido construído assim,
  com o `sabia.py doutor` conferindo cada peça externa e dizendo o comando da que falta.
  Nomear evita reinventá-lo a cada ferramenta.

- **D11 — A metade "fonte e documentação padrão TOTVS" não se constrói: consome-se o MCP
  hospedado da `tbc-servicos`.** — porquê: a fronteira entre os dois é limpa por origem do
  dado — o MCP deles indexa produto padrão, documentação e material anonimizado, e nunca
  toca fonte de cliente; o extrator próprio cobre o customizado. Além disso não há acesso
  de escrita naquela organização e a squad já consome aquilo. Risco aceito e nomeado: é
  serviço de outra equipe, em VPS único, sem failover nem compromisso de disponibilidade
  encontrado.

- **D12 — A skill `arqueologia` passa a consumir o grafo em vez de reler o fonte, e a
  escala de confiança ganha um quarto degrau.** — porquê: hoje ela relê tudo a cada
  invocação e gasta julgamento em derivação; com o grafo existindo, o julgamento vai para
  onde é julgamento. O `confidence` do schema (`EXTRACTED`, `INFERRED`, `AMBIGUOUS`) quase
  encaixa na escala da arqueologia (`CONFIRMADO`, `INFERIDO`, `LACUNA`), mas `AMBIGUOUS`
  ("achei e não tenho certeza") não é `LACUNA` ("não achei") — a diferença é informação.

- **D13 — O que o `rainforest-mind` distribui é o FORMATO de acervo, não conteúdo e não um
  gerador único.** — porquê: é a D5 um nível acima. Lá o padrão é o schema JSON e o motor é
  trocável; aqui o padrão é a forma do acervo (estrutura de pastas, frontmatter, convenção
  de `[[link]]`, índice e tabela de rota) e o preenchedor é trocável — `book-to-skill` para
  livros, o extrator de grafo para código, o que vier depois. Um formato, N preenchedores,
  N consumidores. A skill cria o acervo vazio e a fiação da rota; quem enche é o dono, com
  o gerador que quiser.

- **D14 — O acervo mora na raiz de dados do rainforest, uma pasta por corpus, e a skill
  nunca toca em git.** — porquê: a raiz de dados já resolve "onde moram os dados deste
  usuário" por uma cadeia de quatro a cinco níveis, e é onde já vivem `FOCO.md`,
  `ideias.jsonl` e `sessoes.json`; inventar um segundo lugar faria a próxima sessão
  adivinhar qual dos dois vale. O nome do corpus reusa o vocabulário do `projetos.json`,
  que a D9 já usa. `git init`, remote e commit ficam fora: criar repositório é alterar o
  ambiente do usuário, e a regra 15 fecha essa porta — versionar é escolha do dono, por
  corpus. O critério de quando vale já está escrito no plano de 09/08 ("artefato gerado
  fica fora do versionamento até a geração ser determinística"), e hoje ele é satisfeito
  para o corpus de código, depois do `PYTHONHASHSEED=0`. Regra prática: acervo regenerável
  não se versiona por padrão, porque é saída e polui o diff; acervo escrito por gente se
  versiona.

## Avaliado e descartado

- **Adotar o kit da `tbc-servicos` como referência de método.** Medição do dono: em sessões
  reais no repositório `inovacao`, o trabalho rendeu melhor com o `rainforest-mind` do que
  com o plugin deles. O kit continua sendo o incumbente que a squad usa — conviver com ele
  é restrição, copiá-lo não é caminho.
- **Construir um MCP próprio agora.** MCP é consumidor, e a regra que o próprio dono
  escreveu é que o motor é o ativo e o consumidor é descartável. Para o corpus de código o
  ativo existe; para o de conhecimento ainda não. Construir consumidor antes do segundo
  ativo inverte a ordem. Reavaliar quando houver ativo com mais de um consumidor, e aí o
  eixo é hospedado contra local — não MCP contra CLI.
- **Extrator estilo AdvPL para o acervo de conhecimento.** As 726 linhas de lá existem porque a aresta
  precisa ser inferida de texto cru; aqui ela já está escrita no frontmatter e no
  `[[link]]`. Seria motor grande para problema que uma transcrição resolve.
- **`to_json` como entregável final.** Ver D7.
- **Fundir o extrator numa skill de arqueologia ou num agente.** Extração é determinística
  e mecânica — o dono mediu a não-determinação (815 de 1378 nós trocando de comunidade
  entre duas execuções na mesma máquina) e a corrigiu com `PYTHONHASHSEED=0` embutido no
  gerador. Pôr um modelo no meio reintroduz a variação que custou trabalho matar, e paga
  token para fazer o que regex faz de graça.
- **Repositório próprio para o toolkit.** A skill da D8 resolve sem criar um décimo sexto
  repositório para manter. Reavaliar só se o toolkit crescer além de skill.

## Fora de escopo

- **O grafo AdvPL e o CI que faltou.** É a frente 2, separada a pedido do dono e já
  plantada como ideia com gancho de retorno. Com um fato novo apurado nesta sessão, que
  aquela frente vai precisar encarar: **nenhum desenvolvedor da squad lê o acervo gerado** —
  o dono o construiu para a sessão de IA, não para humano. O entregável do plano de 09/08
  era "vault Obsidian que qualquer dev lê sem instalar nada", e esse leitor não existe.
  O formato de saída daquela frente precisa ser reescolhido a partir de quem de fato lê. Tem plano próprio de 298 linhas, medido, em
  `tbcagro/claude-plugins`, e parou no passo 4 (workflow de CI) porque o repositório não
  tem `.github/workflows/`. Não se reescreve aqui.
- **Construir a metade padrão TOTVS.** Ver D11.
- **Migrar conteúdo do acervo.** Ver D2 — nenhum arquivo muda de lugar.
- **Desvincular a relação de fork do `whatsapp-mcp` no GitHub.** O remoto `upstream` já
  está configurado localmente, então buscar atualização quando quiser já funciona; o que
  resta é a relação de fork na plataforma, que faz PR abrir por padrão contra o
  repositório de origem. É trabalho próprio, não decisão de arquitetura desta camada.

## Em aberto

- **Licença do `sabia`.** Decidida e adiada: o dono vai declarar uma licença, mas não
  agora. Só bloqueia a aplicação da D10 a essa ferramenta no dia em que ela for
  distribuída.
- **O nome e a semântica do quarto degrau da escala de confiança** (D12).

## Decisões que esta entrega deliberadamente não constrói

Documentadas no relatório de fechamento `relatorios/2026-09-05-camada-obsidian-fechamento.md`, com os motivos e fechamento de cada uma:

- **D1 — O Obsidian sai inteiro.** Decisão pura, sem artefato pendente. O aplicativo é externo, o formato é markdown, pronto.
- **D2 — O acervo `segundo-cerebro` continua repositório separado.** Decisão pura, sem artefato pendente. Nenhum arquivo muda de lugar.
- **D3 — O problema é roteamento.** Atendido pela tabela de rota que já existe na skill pessoal `segundo-cerebro`, fora deste repositório.
- **D4 — A rota por regra, dentro de `references/regra-NN.md`.** Deliberadamente fora deste repositório, porque esses arquivos são distribuídos a terceiros. A rota inversa (skill pessoal → regra) já existe na skill pessoal e não é distribuída.
- **D11 — A metade "padrão TOTVS".** Fora de escopo pelo design — o MCP da `tbc-servicos` a cobre, e o acoplamento não é este design.
- **D12 — A arqueologia consome grafo.** Bloqueado até a frente 2 (grafo AdvPL) existir. O grafo de wiki não vale como entrada de confiança.
