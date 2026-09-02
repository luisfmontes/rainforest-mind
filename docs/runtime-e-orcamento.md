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

