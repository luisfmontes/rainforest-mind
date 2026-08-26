# Catálogo de ferramentas: a janela sabe antes de tentar (#76)

## Objetivo

Fazer a janela saber que uma ferramenta falta **antes** de tentar usá-la, sem que o
mecanismo de saber envelheça em silêncio e passe a mentir — e sem nunca recusar
trabalho que funcionaria.

## O que estava travando

A #76 nasceu de um caso medido em 2026-08-23: transcrever um áudio custou cinco
comandos de reconhecimento antes da primeira ação útil. Mas a issue não respondia
quem escreve o catálogo, quando ele reenvelhece, nem o que acontece quando ele mente
— e a assimetria de custo do erro é o coração do problema:

- catálogo que diz **"existe"** e não existe apenas devolve o tropeço de hoje;
- catálogo que diz **"não existe"** e existe faz a janela **recusar** trabalho que
  daria certo. Recusa é silenciosa e não deixa rastro. É estritamente pior.

Uma rodada de `divergir` (registrada em `divergencias.jsonl` como
`76-catalogo-de-ferramentas`) refutou o caminho sedutor com cenário concreto e
produziu a escolha não-óbvia que virou a D2 abaixo. O crítico **não** convergiu para
a primeira ideia da rodada.

## Decisões fechadas

- **D1 — Nada na abertura; o catálogo é lido sob demanda.** — porquê: `ORCAMENTO_BYTES`
  é 8.000 B e a saída do hook mede 8.085 B hoje. Não há "O(1) pequeno" a acrescentar:
  todo byte novo na abertura sai de um bloco de regra. E o critério revisado aceita
  **um** comando, que é exatamente a leitura da entrada.

- **D2 — Gramática sem campo de negativa.** Cada entrada é só um fato positivo datado.
  Não existe campo `ausente` nem lista de "ferramentas que faltam". Ausência de entrada
  lê-se **sempre** como *desconhecido*, nunca como *confirmado ausente*. — porquê: é um
  movimento de esquema, não de política. Remove o desastre do espaço de estados
  possíveis do arquivo, em vez de mitigá-lo com relógio ou job de fundo — e
  *desconhecido* cai no fluxo de tropeço ruidoso que já existe.

- **D3 — Ledger por descoberta em uso; sem varredura de setup.** — porquê: varredura
  cobre tudo de uma vez e envelhece de uma vez, e nada avisa que envelheceu. Com a D2,
  entrada faltando degrada para o comportamento de hoje — o pior caso do ledger é o
  estado atual.

- **D4 — A checagem da bridge do WhatsApp fica onde está.** — porquê: ela é a única
  dependência declarada hoje, já funciona, e mesclá-la agora misturaria refactor de
  hook com feature nova antes de o mecanismo novo se provar. Dívida nomeada em
  "Fora de escopo".

- **D5 — Entrada = nome + receita de invocação + como foi descoberto + data.** —
  porquê: o caso da transcrição prova que "existe" é o fato inútil. O que teria
  poupado os cinco comandos era saber que o `whisper-cli` mora fora do PATH, ao lado
  de um `.bin` de modelo. Receita que envelhece falha ruidoso — o comando quebra.

- **D6 — Dois escritores, com papéis separados.** Um `PostToolUse` grava **só fato
  positivo** depois de sucesso observado; um comando explícito grava o que a máquina
  não infere. — porquê: positivo-só é seguro por construção — o pior caso de uma
  escrita automática errada é uma entrada velha que faz tropeçar, que é o
  comportamento de hoje.

- **D7 — Quem faz a janela consultar é um hook, não texto de regra.** — porquê: texto
  é o que já existe e já falha; a regra 14 é texto, e a descoberta continua
  acontecendo por tropeço. O `conferir-publicacao.cjs` já enuncia isso: *"regra escrita
  não alcança o modo de falha em que quem a leu erra mesmo assim. O que alcança é
  código com exit code."*

- **D8 — Entrada positiva que envelheceu: confia e deixa tropeçar.** — porquê: a D2 já
  classificou esse caso como o tolerável, e re-sondar a cada consulta devolveria o
  custo que a feature existe para tirar.

- **D9 — Superfície da versão 1: só o executável do comando `Bash`.** — porquê: é onde
  o tropeço foi medido, e a única superfície em que o hook nomeia o alvo sem adivinhar.
  Chave de env e MCP têm volatilidade e forma de sonda diferentes.

- **D10 — O `PreToolUse` anuncia e deixa passar; nunca barra.** — porquê: barrar
  reintroduz a recusa silenciosa que é o pior caso da issue. Deixando passar, o pior
  caso vira o comando falhando sozinho, ruidoso, como hoje — e o critério continua
  cumprido, porque o aviso vem antes da tentativa.

- **D11 — A receita de invocação só entra pelo comando explícito.** O `PostToolUse`
  grava apenas *nome, funcionou, data*. — porquê: inferir receita a partir de um
  comando bem-sucedido é adivinhação, e receita inventada custa mais que receita
  ausente.

- **D12 — A sonda deixa de ser peça separada e vira a própria consulta.** Sem entrada
  no ledger, o hook roda **uma** checagem barata do executável e anuncia o resultado. —
  porquê: é o "um comando, não cinco" do critério revisado. A peça 3 da composição
  original existia para proteger a recusa, e a D10 eliminou a recusa.

- **D13 — Uma linha por ferramenta, reescrita; não append por descoberta.** — porquê:
  decorre da D2 e da D8. O `ideias.jsonl` é append-only porque cada ideia é um evento
  distinto; aqui o fato é "esta ferramenta existe, e assim se invoca". Append por
  execução transformaria um inventário de dezenas de linhas num log de milhares, sem
  que nenhuma linha antiga sirva para alguma coisa.

- **D14 — O `PostToolUse` só escreve quando o executável ainda não está no ledger.** —
  porquê: decorre da D13. Escrever a cada comando bem-sucedido seria I/O no disco do
  usuário a cada tool call para reafirmar o que já se sabe.

## Avaliado e descartado

- **Catálogo estático nos moldes do RatosOS, escrito no `setup`.** Refutado com cenário
  concreto na rodada de `divergir`: dia 1 roda o `setup` e grava `whisper-cli: ausente`;
  entre o dia 1 e o 5 o usuário instala a ferramenta e ajusta o PATH sem rerodar o setup,
  porque nada no desenho avisa que é preciso; dia 5 a janela lê o catálogo, cumpre as
  regras 14 e 15 **à risca** e recusa uma task que funcionaria, sem log e sem rastro.
  Ele **passa** no critério de pronto na primeira semana e fica mais perigoso a cada
  instalação.

- **TTL — flat e por categoria — fingerprint de ambiente, e sonda ao vivo antes de
  recusar.** Seis das ideias da rodada atacavam *frescor*: quando foi a última checagem,
  quanto falta expirar, quem revalida. Todas mitigam o desastre; a D2 o remove. Ficam
  disponíveis se a D2 se mostrar insuficiente na prática.

- **Ponteiro com assinatura de frescor injetado no `SessionStart`.** Era a peça 2 da
  composição que entrou no brainstorm. Morreu na medição da D1: o payload já está
  85 B acima do orçamento.

## Fora de escopo

- Chave de API em env e servidor MCP como superfícies do catálogo (D9).
- Unificar a checagem da bridge do WhatsApp neste mecanismo (D4) — dívida registrada.
- `vigias/run-vigia.ps1` gravando o `ERROS.md` em duas raízes: issue #112, independente.

## Em aberto

- **Custo do `PreToolUse` em toda chamada `Bash`.** Não medido. O hook precisa ser
  barato no caminho comum (ler um `.jsonl` de dezenas de linhas, sem subprocesso) e só
  gastar um comando quando o executável é desconhecido. Se a latência aparecer, a saída
  é restringir o gatilho — não afrouxar a D10.

- **Custo da sonda única no Windows.** `where`/`command -v` custam um processo. Para a
  primeira sessão de uma máquina nova, com o ledger vazio, isso acontece uma vez por
  executável desconhecido. Convergir é esperado; a curva não foi medida.

- **Se a D2 basta sozinha.** A gramática sem negativa remove o caso caro por
  construção, mas não diz nada sobre o positivo velho, que a D8 aceita de propósito. Se
  na prática o positivo velho incomodar mais do que o previsto, o TTL por categoria —
  descartado nesta rodada — volta como acréscimo, não como substituto.

- **Onde o comando explícito da D11 mora e como se chama.** Segue a forma de porta
  única do `ideias.cjs` (contagem, validação linha a linha, backup), mas o nome e a
  superfície não foram decididos — é matéria do `plano`.

## Critério de pronto (o da issue, revisado)

Uma task que precise de ferramenta ausente anuncia o bloqueio **antes** de tentar
usá-la. Uma task cuja ferramenta existe gasta **um** comando de reconhecimento, não
cinco. E uma afirmação de ausência **nunca** autoriza recusa sozinha. Conferir nos três
casos com a transcrição real da sessão.
