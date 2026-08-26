# Design: a trava de cwd — três observações que prescrevem o mesmo mecanismo

## Objetivo

Fechar, por mecanismo verificável por máquina, as três observações que prescrevem
a mesma checagem e nunca foram implementadas — `cwd` da sessão contra o caminho
que vai ser escrito, e contra as pastas do foco. A terceira delas
(`tres-vezes-o-mesmo-conserto-prescrito-e-nunca-implementado`, 2026-08-23) existe
exatamente para dizer que registrar de novo não fecha o laço: *"Enquanto for
disciplina, será a 4ª vez."* Esta é a 4ª vez, e é a primeira que vira código.

No caminho, dois textos que entraram na `main` hoje em `d5d24b6` prescrevem
efeito que o código não produz, e caem junto.

### O que a apuração mudou no problema

Três fatos derrubaram premissas do próprio registro:

1. **Nenhum código emite a linha de prazo.** Não existe função que compare data
   com hoje. O hook injeta a seção crua `## Compromissos com prazo` do FOCO.md
   (`SECOES_RESIDENTES`, `hooks/lib/contexto-sessao.cjs:188`) e a instrução da
   regra 3; a conta é do modelo, em prosa. Suprimir não é filtrar texto — é o
   hook mandar não emitir.
2. **A maquinaria de supressão já existe e já roda.** `computarVeredito()`
   (`hooks/lib/contexto-sessao.cjs:1378`) recebe `pastasDoFoco()`,
   `ociosidadeDoFoco()` e a lista de sessões, chama `focoAtivoEmOutraJanela()` e
   já emite diretiva do formato exato que falta: `**NÃO cobrar desvio de escopo
   nesta sessão** — …` (`:1428`). É onde a nova diretiva custa menos.
3. **O `combina()` do `semear.cjs` é a ferramenta errada.** O registro manda
   reaproveitá-lo. `scripts/semear.cjs:145` é substring bidirecional com um corte
   no primeiro `-c-` (o que `C:` vira ao normalizar) — não casa raiz de caminho.
   Quem casa caminho corretamente é `focoAtivoEmOutraJanela`, no mesmo arquivo
   que este trabalho toca.

## Decisões fechadas

- **D1 — A linha de prazo é de abertura, e nunca do fechamento.** O incidente de
  2026-08-11 foi um lembrete de prazo emitido por conta própria no fecho de
  sessão, depois de o usuário já ter respondido a pergunta de observações da
  regra 13. No fim do turno não há o que fazer com um prazo. Isso é regra de
  texto, sem código: nenhum hook de `Stop`/`SessionEnd` emite prazo hoje
  (confirmado em `hooks/hooks.json:72-113`), então não há nada para desligar —
  há o que proibir.

- **D2 — Foco ativo em outra janela transforma o prazo em nota, não o silencia.**
  A diretiva nova sai da mesma função e no mesmo formato da que já existe: quando
  `focoAtivoEmOutraJanela()` é verdadeiro, o hook manda apresentar o prazo como
  nota de que o foco está sendo tocado naquela janela, nunca como cobrança
  dirigida a esta sessão. Preserva o raciocínio do `README.md:196` — saber que
  algo vence é informação e não custa nada; ser cobrado é o que incomoda — e
  atende o registro, que já oferecia a nota como alternativa.

- **D3 — `README.md` e `references/regra-03.md` se alinham nessa formulação, e a
  linha de `d5d24b6` é estreitada.** Hoje o README diz que a isenção cala **só**
  o desvio e que o prazo "continua saindo, sempre"; a regra 3 diz que a checagem
  vale para "a frase de desvio **ou a linha de prazo**". Contradição viva, escrita
  hoje. Os dois passam a dizer o mesmo: a isenção não silencia o prazo, muda o
  **tom** dele — e o fecho não emite prazo nunca.

- **D4 — A trava de escrita fora do repo barra só quando o destino está dentro de
  OUTRO repositório git.** Fora de git (o `~/.rainforest/`, o scratchpad, arquivo
  solto) passa sem regra especial. É o recorte exato do incidente de 2026-08-23 —
  consertar o `rainforest-mind` a partir da janela do `whatsapp-mcp` — e é o que
  torna a trava usável: barrar toda escrita fora do repo desta sessão teria
  batido 29 vezes só na sessão de hoje, que gravou no `ideias.jsonl` a cada
  colheita.

- **D5 — A trava segue o molde dos três gates que já existem, sem inventar
  contrato.** Entrada por `JSON.parse(fs.readFileSync(0,"utf8") || "{}")` em
  try/catch com `exit 0` no catch; recorte por `ev.tool_name` em
  `Write`/`Edit`/`MultiEdit`/`NotebookEdit` lendo `tool_input.file_path` (com
  `notebook_path` de reserva); escotilhas `RAINFOREST_GATE_OFF`,
  `.rainforest-gate-off` no toplevel e chave registrada em `CHAVES`;
  **bloqueio = texto em stderr + `process.exit(2)`**, liberação = `exit 0`
  silencioso; declaração em `hooks/hooks.json` no array `PreToolUse`; bateria
  `hooks/testa-<nome>.sh` no padrão `cygpath -m` + helper que compara exit code.

- **D6 — O casamento de caminho reaproveita o que já funciona neste arquivo, não
  o `combina()` do `semear.cjs`.** Comparação por toplevel de git resolvido
  (`git rev-parse --show-toplevel` dos dois lados), normalizado como
  `normalizarCwd()` normaliza — barra invertida vira barra, minúscula, por
  igualdade. Dois toplevels diferentes e ambos não-nulos = escrita em repo
  alheio.

- **D7 — O texto da regra 13 é corrigido para o que é verdade, e o
  reaparecimento por sessão é plantado, não construído.** O parágrafo que entrou
  hoje justifica `projeto: solta` dizendo que arquivar sob um repositório
  "esconde das sessões onde ela precisa reaparecer". É falso: a injeção de
  abertura não lê o `ideias.jsonl` (o único ponteiro é o rodapé,
  `hooks/lib/contexto-sessao.cjs:1098`), e o jardineiro de sexta mostra
  observação independente de `projeto` (`vigias/dados-jardineiro-ideias.js:29`).
  `solta` muda o agrupamento do `listar` e nada mais. O texto passa a dizer isso;
  o reaparecimento de verdade mora no corpus da memória (`rainforest.db`,
  filtrado por *basename* do toplevel em `scripts/memoria.cjs:92`), que é outro
  subsistema.

- **D8 — `gate-publicacao` entra em `CHAVES`.** `hooks/gate-publicacao-destino.cjs:161`
  chama `ligado("gate-publicacao", …)` e a chave não está registrada em
  `hooks/lib/config.cjs`; como `ligado()` devolve `true` para chave desconhecida
  (`if (!(chave in CHAVES)) return true;`), o botão por projeto dessa trava é
  inerte desde que ela nasceu. Entra junto porque é o mesmo arquivo que a trava
  nova precisa editar.

## Avaliado e descartado

- **Suprimir o prazo junto do desvio de escopo** (o que o registro pede ao pé da
  letra). Derruba o parágrafo do `README.md:196`, cujo raciocínio está certo e é
  mais fino que o do registro: informação num sábado não custa nada, cobrança
  custa. A D2 entrega o que doía sem pagar esse preço.
- **Reaproveitar `combina()` do `semear.cjs`** para casar foco com caminho, como
  o registro manda. Ele é substring bidirecional com corte no `-c-`; casaria
  `C:/Projetos/x` com quase tudo. Fato apurado que contradiz o registro.
- **Barrar toda escrita fora do repo da sessão.** 29 colisões legítimas só hoje.
  A trava morreria desligada na primeira semana, que é a pior forma de trava.
- **Construir agora o reaparecimento de observação de método em toda sessão.**
  Vive no pipeline da memória, não no ledger; puxaria outro subsistema para
  dentro deste fluxo. Vira ideia plantada com gancho.
- **Um `PostToolUse` que avisa depois da escrita.** Chega tarde: o arquivo já foi
  editado no repo alheio, que é exatamente o estado que o incidente deixou
  (worktree com 39+/10− não commitados, perdida).

## Fora de escopo

- **Unificar as duas normalizações de caminho do mesmo arquivo** —
  `normalizarCwd()` (`:746`, `path.posix`, por igualdade) e a
  `normalizarCaminho()` local de `focoAtivoEmOutraJanela` (`:1277`,
  `path.normalize`, por prefixo). É defeito real de coerência, mas é refactor no
  arquivo mais crítico do plugin e não é o que as três observações pedem.
- **Os dois consumidores de `Ociosidade máxima` discordarem no caso ausente** —
  `hooks/foco-session-start.cjs:209` assume `'45'`, `computarVeredito:1399`
  anuncia indeterminação. Também real, também não é isto.
- **Os 34 alvos de método da triagem das observações sem etiqueta** — esteira
  própria, já recomendada contra puxar agora.
- **Colher as três precedentes.** Só depois do merge, como todas as outras.

## Em aberto

Nada. A fronteira esvaziou nas quatro perguntas da rodada — prazo (Q1, meio-termo),
recorte da trava (Q2, só repo alheio), texto da regra 13 (Q3, corrigir e plantar) e
o botão inerte (Q4, entra) — todas respondidas.
