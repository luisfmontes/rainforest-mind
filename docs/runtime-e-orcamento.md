# Runtime, dependências e orçamento de token

Por que o caminho de execução é só Node, o que sobrou de Python e por quê, e
como o custo de contexto do plugin é medido a cada PR.

## Runtime
`/saude`, o fluxo e a medição de jornada rodam em Node. O Claude Code não
garante Node nem Python (a lista oficial de dependências adicionais tem
`ripgrep` e mais nada), então a meta é **uma** dependência, não duas.

Sobra Python em **ferramental seu**, fora de qualquer regra: `medir-injecao.py`
(mede o custo real da abertura), `validar-colhidas.py` e a `statusline/` inteira
(`statusline.py` mais três testes) — a barra é opcional, e ela mesma chama o
`jornada.cjs` em vez de inferir jornada por conta própria. Nenhuma regra depende
deles — se Python não existir na máquina, nada aqui degrada.

**E as baterias também são Node.** Até 2026-08-12 elas usavam Python para montar
fixture e conferir JSON: o runtime era único para quem *instala* e duplo para quem
*contribui*, o que é a mesma promessa quebrada uma camada acima. Os 24 usos viraram
`node -e`. Os gêmeos em Python continuam, porque ali o Python **é** o teste.

Essa frase foi **falsa até 2026-08-12**, e vale dizer por quê: as regras 11 e 12
exigiam `conferir-entrega.py` na integração de toda entrega de agente, e
`skills/executar` e `agents/executor.md` o chamavam pelo nome. Um dev sem Python
não tinha a trava da regra 12 — tinha o texto dela. Trava que não trava é o único
defeito que este repo não aceita, então o script virou `conferir-entrega.cjs`.

Dois scripts ficam como **gêmeos** dos ports, e não como legado morto:

| Gêmeo | O que ele prova |
|---|---|
| `conferir-entrega.py` | a mesma bateria roda contra os dois — `CONFERIR="python scripts/conferir-entrega.py" bash scripts/testa-conferir-entrega.sh` — **23 casos / 43 asserções** (o rodapé imprime `43 ok`), e as falhas encenadas (as seis dos relatórios mais o arquivo que some por `.gitignore`) reprovam nos dois |
| `jornada.py` | os dois medem o mesmo dia e devolvem os mesmos números, lacuna por lacuna |

Apagar o gêmeo seria apagar a única prova de que o port está certo. O
terceiro gêmeo — o do `ideias.cjs` — foi aposentado em 2026-08-22: a bateria
gêmea tinha parado de provar equivalência (saía 53 ok / 5 falhas, pulando 5
seções inteiras como "recurso novo só do .cjs") e virou manutenção sem
retorno.

**Nenhuma regra depende de plugin de terceiro.** A regra 8 media a jornada com
um plugin de cliente até 2026-08-11; hoje mede com `node scripts/jornada.cjs`,
que lê o transcript da própria sessão. Quem tiver o plugin pode usá-lo como
conferência — nunca como requisito.

**E dependência opcional não se anuncia nem se sonda sem alguém pedir.** Duas
consequências disso, as duas de 2026-08-12:

- A abertura só reporta o que este install **declara**: a bridge do WhatsApp
  aparece quando existe `WHATSAPP_API_BASE_URL` no ambiente, e o claude-mem
  quando está instalado. Antes, toda sessão de toda máquina abria uma conexão TCP
  para `localhost:3005` e imprimia "bridge WhatsApp FORA" para quem nunca ouviu
  falar dela. Sem nada declarado o bloco inteiro sai da injeção (−169 B).
- **Os vigias nascem desligados** (`vigias`, em `/setup`). As rondas exigem
  PowerShell agendado, `claude.exe` no caminho e um destino de envio; com a chave
  desligada o `run-vigia.ps1` **sai limpo (exit 0)** e não escreve em
  `vigias/ERROS.md`, porque desligado não é erro. Ele pergunta o estado por
  `node scripts/setup.cjs --ligado vigias` em vez de reimplementar a cadeia de
  três níveis em PowerShell — segunda cópia da regra é cópia que diverge calada.


## Ajuste fino

- O **núcleo** das regras vive em [`skills/rainforest-mind/SKILL.md`](../skills/rainforest-mind/SKILL.md) — edite e a mudança vale na próxima sessão. A **elaboração** de cada regra vive em [`skills/rainforest-mind/references/regra-<n>.md`](../skills/rainforest-mind/references) — edite lá quando precisar de critério fino, comando exato ou incidente datado.
- **Incidente datado vai em blockquote.** O hook remove as linhas que começam
  com `>` antes de injetar: a narrativa continua no arquivo, ao lado da regra
  que fundamenta, e sai do custo de toda sessão. Instrução nunca entra na
  citação — se a frase diz o que fazer, fica fora. Rendeu **−11%** da injeção
  quando entrou, sem perder uma linha de conteúdo; hoje o `SKILL.md` já não tem
  nenhuma linha `>` (os incidentes nascem direto nos `references/`, que não são
  injetados), então o filtro ficou como trava contra reincidência.
- Antes de caçar token na skill, olhe onde ele está de verdade. Medido com
  `/context all` em **2026-08-09**: as ferramentas de MCP somavam **40,2k
  tokens** contra ~330 das skills deste plugin. Desligar MCP por projeto rendeu
  **~120×** o que traduzir as regras inteiras renderia. (Hoje as `description`
  das skills somam 3.601 B, ~1,2k tokens — a ordem de grandeza da conclusão não
  mudou.)
- O hook avisa quando a skill passa de **60 dias sem revisão**.

## Memória pelo assunto: o que é injetado e quanto

Além do bloco de abertura (`## Memória (corpus residentes)`, que não mudou), dois
hooks injetam memória durante a sessão, sob o cabeçalho `## Memória do assunto`:

| Canal | Hook (`hooks/hooks.json`) | Evento | Como entrega |
|---|---|---|---|
| Pedido | `memoria-assunto-prompt.cjs` | `UserPromptSubmit` | `additionalContext` |
| Subagente | `memoria-assunto-agente.cjs` | `PreToolUse`, matcher `Agent` | `updatedInput`: o bloco vai ao fim do `prompt` do briefing, sem `permissionDecision` |

- **Teto:** 3 memórias por pedido ou briefing, bloco de no máximo **1.500 bytes**
  (`TETO_BYTES` em `hooks/lib/memoria-assunto.cjs`) — por volta de 480 tokens no
  pior caso, pelo fator 3,11 byte/token indicativo desta página. Só entra
  candidata com bm25 ≤ -10 numa consulta pelos 30 termos mais raros do texto, sem termos presentes em mais de 2% das memórias vivas (`LIMIAR_BM25` e `TETO_DF_FRACAO`; calibração em
  [`docs/rainforest/referencia/2026-10-08-limiar-memoria-assunto.md`](rainforest/referencia/2026-10-08-limiar-memoria-assunto.md));
  sem candidata, custo zero.
- **Sem repetir:** os ids servidos ficam em `<raiz de dados>/memoria-assunto/<sessão>.json`
  (só números). Quem grava é a abertura (`hooks/memoria-session-start.cjs`), com os ids das observações que de fato entraram no bloco, somados aos já existentes na sessão retomada, e o hook do pedido, só com o que `montarBlocoAssuntoComIds` pôs no bloco (a candidata cortada pelo teto não conta como servida). A leitura do transcrito (`lerServidasDoInicio`, `hooks/memoria-assunto-prompt.cjs`) fica só para a sessão aberta antes da atualização, quando o arquivo ainda não existe. Vale só para o canal do pedido: o subagente é contexto novo e não deduplica.
- **Orçamento:** isto não entra no teto de 15.000 B do `orcamento.cjs`, que mede só
  a abertura (fontes do repositório); é custo por pedido, limitado pelo teto acima.
- **Falha calada:** banco ausente ou travado e qualquer erro saem com exit 0 e sem injeção;
  o teto de cada hook no `hooks.json` é de 5 s.
- **Régua D7:** a medição de 2026-10-08 tem base de **27%** de sessões com memória
  útil e **171** de 255 sessões com perda. O canal fica se, 14 dias depois de a
  versão estar viva, houver **≥ 40%** de sessões com memória útil e perdas
  **≤ 1/3**; senão sai. Leitura: `node scripts/memoria.cjs utilidade --relatorio`
  (por canal, buscas ativas e a linha `régua D7`). A pontuação feita antes da
  1.54.0 carrega as regras antigas; para refazer a janela, rode antes do
  relatório `node scripts/memoria.cjs utilidade --repontuar --desde 2026-10-08`
  (backup antes, `pontuada_em` preservado, sessão sem transcrito intocada e contada).
- **O que a nota mede (1.54.0):** a busca ativa é a instrução `node <caminho>memoria.cjs buscar`
  (`scripts/lib/busca-ativa.cjs`); texto citado e corpo de heredoc não contam. Limites declarados
  no código (todos subcontam): caminho entre aspas, prefixos `time`/`timeout`/`env`, flag do node
  antes do script, chamada dentro de `$(...)`/`(...)`/depois de `then`, continuação com `\`, `<<`
  dentro de outro comando e here-string do PowerShell não são reconhecidos. Nos canais pedido e subagente a nota mede só os termos raros que o texto que
  disparou a injeção não tinha; sem termo raro fora dele, a servida fica com nota nula e sai do
  numerador e do denominador (o relatório conta quantas, em `servidas fora da conta`).

## Glossário do repo: o que é injetado e quanto

O `GLOSSARIO.md` da raiz do repositório entra em dois canais, sob o cabeçalho `## Glossário do repo`. Ele não entra na abertura da sessão: entre os hooks de `hooks/*.cjs`, só os dois abaixo leem o arquivo.

| Canal | Hook (`hooks/hooks.json`) | Evento | Como entrega |
|---|---|---|---|
| Pedido | `memoria-assunto-prompt.cjs` | `UserPromptSubmit` | `additionalContext` |
| Subagente | `memoria-assunto-agente.cjs` | `PreToolUse`, matcher `Task\|Agent` (`hooks/hooks.json:122`) | `updatedInput`: o bloco do glossário vai ao fim do `prompt` do briefing, antes do bloco de memória |

- **Teto:** 3 verbetes (`VERBETES_MAX = 3`, `hooks/lib/glossario.cjs:25`) e 1.800 B no bloco inteiro (`TETO_BYTES_GLOSSARIO = 1800`, `:26`). Cada linha de verbete tem no máximo 900 B (`BYTES_MAX_VERBETE = 900`, `:27`); linha maior não entra (`:244`), e se o bloco passar de 1.800 B a última linha sai (`:250-251`).
- **Casamento:** só entra verbete cujo termo casa com o texto do pedido ou do briefing (`casarVerbetes`, `memoria-assunto-prompt.cjs:83` e `memoria-assunto-agente.cjs:24`).
- **Arquivo do repo:** o `GLOSSARIO.md` é procurado subindo a partir do diretório atual até o primeiro que tenha `.git`, e só ali (`hooks/lib/glossario.cjs:170-188`). Arquivo acima de 256 KB (`GLOSSARIO_MAX_BYTES = 262144`, `:28`) não é lido: o glossário fica de fora nos dois canais (`:179`).
- **Sem repetir, só no pedido:** o hook do pedido grava em `<raiz>/memoria-assunto/<sessão>.glossario.json` só as chaves dos verbetes já servidos (`memoria-assunto-prompt.cjs:87-88`, `:96`), nunca o texto do pedido. Arquivo de dedup ilegível vira lista vazia (`lerChavesOuVazio`, `:47`) e falha ao gravar é engolida (`:96`): nos dois casos o bloco entra, só sem dedup. O hook do subagente não lê esse arquivo: cada briefing é contexto novo.
- **Sem banco:** o glossário é lido antes de qualquer acesso ao banco (`memoria-assunto-prompt.cjs:151`, antes da memória em `:154-155`), e o caminho do glossário no subagente não passa pelo banco (`memoria-assunto-agente.cjs:19-27`).
- **Raiz de dados, no pedido:** o glossário não depende dela. Sem raiz, o hook do pedido injeta o glossário sem deduplicação (`memoria-assunto-prompt.cjs:87`, `:148-151`), e só a memória por assunto fica de fora (`:154`). A raiz é `.rainforest/` com `FOCO.md` ou `ideias.jsonl`, `~/.rainforest`, ou o próprio plugin (`hooks/lib/raiz.cjs:40`); sem nenhum deles, `resolverRaiz` devolve `raiz: null` (`hooks/lib/raiz.cjs:99`). O hook do subagente não depende disso.

## Orçamento de token

O rainforest-mind é injetado em toda sessão, então o custo dele é real e precisa de medição contínua. O `scripts/orcamento.cjs` mede as fontes (hook, skills, commands, agentes) em byte e acusa quando passa do teto de **15.000 B** — subiu de 14.000 em 2026-08-25, com a conta escrita no cabeçalho do script. Ele entra no laço de testes do `CONTRIBUTING.md:11` pela convenção de nome, via `scripts/testa-orcamento.sh` — o workflow `.github/workflows/baterias.yml` roda todas as baterias (`scripts/testa-*.sh` e `hooks/testa-*.sh`) automaticamente **a cada PR**, e sob demanda por `workflow_dispatch`; o gatilho de push na `main` saiu em 2026-08-25, quando a conta de Actions bateu 90% da cota:

```bash
node scripts/orcamento.cjs          # sai 0 se dentro do teto, 1 se estourou
node scripts/orcamento.cjs --teto 1000  # sobrescreve o teto para teste
```

O modo `--repartir` do `scripts/medir-injecao.py` lê o transcript e reparte a abertura por fonte, respondendo a pergunta "para onde foi cada token?" em vez de só "quanto custa?":

```bash
python scripts/medir-injecao.py --repartir
```

Medição da abertura de 2026-08-14T00:36 (transcript `570a6723`): das **67.914 tokens**, **18.980 (28%)** são atribuíveis pelo transcript — o resto é system prompt do Claude Code, schema das tools, CLAUDE.md e memórias, que o transcript não guarda.

O rainforest-mind por si ocupa **13.205 B, uns 4.246 tokens estimados, ou ~6,3%** da abertura. Pelo outro caminho, o `orcamento.cjs` contando arquivos do repositório dá **~14,5 kB** (14.559 B medidos em 2026-08-26). Os dois **não medem a mesma coisa** e não deveriam bater exatamente: o lado do repositório conta `commands/` como parcela própria, e o lado do transcript já os traz dentro da listagem de skills; o lado do transcript mede a linha renderizada na listagem, com prefixo e formatação, e o do repositório mede só o texto da `description`. Ficarem a ~10% um do outro é consistência entre duas réguas parecidas — **não é validação cruzada**, e não deve ser lida como tal.

**Três armadilhas que este número já pisou, todas deixadas escritas de propósito:**

1. **Não some byte de uma medição com token da outra.** Uma versão deste parágrafo dizia "13.604 B ... 1.157 tokens ou 1,7%", casando o total do `orcamento.cjs` com o token de um recorte bem mais estreito do `--repartir` — errando o custo em quase 4× para menos. Cada linha da tabela traz byte e token da mesma medição; é assim que se lê.
2. **Um transcript pode ter mais de uma abertura.** Todo `--resume` grava outro `SessionStart` no mesmo arquivo. O `--repartir` atribui pelo **primeiro**, que é o mesmo que fixou o total em token — antes de isso ser consertado, ele somava as fontes de um evento com o total de outro.
3. **Nem tudo que diz "rainforest-mind" é do rainforest-mind.** O `hook_additional_context` da abertura chega como **lista** de itens de plugins diferentes, e o item do claude-mem começa com `# [rainforest-mind] recent context` — o nome do projeto no claude-mem, não o dono do texto. Ele foi contado como nosso por uma rodada inteira, inflando a fatia em 9.018 B. A separação hoje é por marcador do item, não pelo nome que aparece nele.

O byte do hook **oscila entre execuções** — ele embute estado vivo da sessão (janelas ativas, horários), então medições feitas com minutos de diferença dão 7.7xx–7.8xx variando. As três outras fontes são estáveis. Por isso o teto é agregado e com folga, e por isso o `testa-orcamento.sh` afirma faixas e "não pode ser 0 B", nunca igualdade exata contra o repo real.

**Ressalva sobre token estimado:** a coluna de token no `--repartir` é estimada dividindo byte por fator **3.11**, que foi medido com `tiktoken` no encoding `cl100k_base` — **que é da OpenAI (GPT-4)**, não do Claude. Não existe tokenizador do Claude disponível offline nesta máquina. O total da abertura é token **medido** (vem do `usage` da API), tudo mais é **indicativo**.

