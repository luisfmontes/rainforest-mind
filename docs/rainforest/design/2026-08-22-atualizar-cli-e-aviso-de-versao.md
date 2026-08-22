# Atualizar a CLI por script, e a barra avisar quando a sessao esta atrasada

## Objetivo

Duas pontas do mesmo incidente de 2026-08-22: o Luis estava oito releases atras
(2.1.220, de 24/07, contra 2.1.231 estavel) **achando que estava na ultima**, e a
atualizacao so nao falhou porque descobri na hora que da para renomear um exe em
uso no Windows. A receita que funcionou nao pode viver so no meu relato, e a
falta de aviso nao pode depender de eu estar olhando.

## O que o ambiente disse antes de qualquer decisao

Apurado em 2026-08-22, antes de decidir qualquer coisa:

- A instalacao e **portable do WinGet**: um unico `claude.exe` em
  `.../WinGet/Packages/Anthropic.ClaudeCode_Microsoft.Winget.Source_8wekyb3d8bbwe`,
  e **essa pasta esta no PATH de usuario** — nao ha shim em `WinGet\Links`. Nao ha
  instalacao npm nem `~/.local/bin` concorrente. Binario unico para a maquina
  inteira: nao existe "atualizar so uma conta".
- `winget upgrade` com o exe em uso falha em `remove: Access is denied`. Renomear
  o exe **funciona** com sessoes rodando (medido: 4 processos seguiram vivos a
  partir do arquivo renomeado, e o `winget upgrade` seguinte instalou limpo).
- `https://downloads.claude.ai/claude-code-releases/stable` devolve **7 bytes**,
  `2.1.231`, sem quebra de linha. E a mesma versao que o WinGet oferece. O npm
  publica a frente do canal estavel (2.1.239 la, 2.1.231 aqui) — o estavel e o
  numero certo para comparar.
- Toda linha do transcript JSONL carrega `"version"` — a versao **do processo que
  esta rodando aquela sessao**, nao a do disco. Depois da atualizacao de hoje, as
  4 sessoes abertas continuam gravando `2.1.220` enquanto o disco ja tem
  `2.1.231`. A statusline ja recebe `transcript_path` no stdin.
- `claude --version` custa **1,58 s** e responde o que esta no **disco**.
- `statusline-jornada.sh` ja e o molde de refresher: lock por `mkdir` atomico,
  orfao acima de 5 min, cache em `$TEMP`, `exit 0` em toda falha. A statusline le
  o arquivo de cache e nunca a fonte.
- `DISABLE_AUTOUPDATER: "1"` esta nas duas contas, e o binario **nao** tem
  nenhuma deteccao de gerenciador de pacote (o grep so acha internals do SQLite).
  Ligar o autoupdater embutido num binario que o WinGet gerencia pode criar uma
  segunda copia em outro caminho.

## Decisões fechadas

- **D1 — a atualizacao vira `scripts/atualizar-cli.sh`, rodado a mao, nunca
  automatico** — porque: trocar um executavel de 300 MB por baixo de sessoes
  vivas e acao irreversivel o suficiente para pedir intencao explicita. O
  autoupdater embutido continua desligado (`DISABLE_AUTOUPDATER`), porque o
  binario e do WinGet e nao sabe disso. O que o script tira do caminho e o
  trabalho manual e a chance de errar a ordem — nao a decisao de atualizar.

- **D2 — a receita do script e renomear, atualizar, conferir rodando, e voltar
  sozinho se nao subir** — porque: e exatamente a sequencia medida hoje. Renomear
  `claude.exe` para `claude-<versao>.exe.bak` libera o caminho **sem** fechar
  sessao; `winget upgrade` instala; e a conferencia e `claude --version`
  **executado**, nao o que o winget relata. Versao que nao subiu = rollback
  automatico pelo rename de volta, porque um PATH apontando para pasta sem
  executavel e o pior estado possivel.

- **D3 — o script guarda exatamente **um** backup: o da versao imediatamente
  anterior** — porque: 265 MB por release acumulando em silencio e vazamento de
  disco pelo mesmo mecanismo do `mktemp` que a esteira de ontem fechou. Backups
  mais antigos que o penultimo saem no fim da execucao bem-sucedida; o
  penultimo fica ate a proxima atualizacao provar que a atual presta.

- **D4 — o segmento da barra compara a versao **da sessao** (ultima linha do
  transcript) com o estavel do CDN** — porque: a pergunta que interessa nao e "o
  disco esta atualizado", e "**esta sessao aqui** esta velha". Sao respostas
  diferentes justamente no unico momento em que o aviso importa: depois de uma
  atualizacao, com sessoes antigas ainda de pe. E de graca — o numero ja esta no
  arquivo que a barra ja recebe — enquanto `claude --version` custa 1,58 s e
  responde a pergunta errada.

- **D5 — o estavel vem do CDN por refresher em segundo plano, no molde do
  `statusline-jornada.sh`** — porque: e chamada de rede, e rede na barra e travar
  a barra. Mesmo lock por `mkdir`, mesmo cache em `$TEMP`, mesmo `exit 0` em toda
  falha. Cache de versao pode ser velho sem prejuizo: um aviso que aparece uma
  hora depois ainda cumpre a funcao.

- **D6 — sem cache, sem rede, sem transcript ou versoes iguais, o segmento
  simplesmente nao aparece** — porque: e a regra que a barra ja segue. O aviso e
  informacao util, nao alarme; barra que erra para o lado de nao acender aqui e
  aceitavel, porque o custo de nao saber e "atualizo semana que vem", nao um
  compromisso perdido.

- **D7 — a bateria de versao e um arquivo proprio, `testa-statusline-versao.py`,
  invocado pelo `scripts/testa-statusline.sh` que ja existe** — porque:
  `testa-statusline-prazo.py` tem prazo no nome e 16 casos de uma unica funcao;
  empurrar versao para dentro dele faria o nome mentir. O invocador do CI ja
  existe e ja e o ponto de entrada — passa a rodar as duas e a somar os
  resultados. O glob e o piso de 15 do workflow continuam intactos.

- **D8 — a bateria do `atualizar-cli.sh` testa o script contra uma arvore
  sintetica, nunca a instalacao real** — porque: bateria que roda `winget
  upgrade` de verdade no CI (ou na maquina dele, a cada execucao) troca binario
  como efeito colateral de um teste. O script recebe a pasta do pacote por
  variavel — o mesmo padrao do `STATUSLINE_INSTALL_DEST` do instalador de ontem —
  e a bateria monta um exe falso, um `winget` falso no PATH, e confere rename,
  rollback e limpeza de backup.

## Avaliado e descartado

- **Ligar o autoupdater embutido (tirar `DISABLE_AUTOUPDATER`)** — o binario e
  gerenciado pelo WinGet e nao detecta isso; o risco concreto e uma segunda
  instalacao em outro caminho e ambiguidade de PATH. Troca um incomodo conhecido
  por um problema de diagnostico caro.
- **A barra chamar `claude --version`** — 1,58 s por render, num lugar onde o
  orcamento e milissegundos, para responder a pergunta errada (disco, nao
  sessao).
- **Comparar contra o npm (`npm view ... version`)** — o npm publica a frente do
  canal estavel; o aviso ficaria permanentemente aceso mesmo com a maquina em dia.
- **Fechar as sessoes para atualizar** — foi o que eu recomendei antes de medir,
  e o rename provou desnecessario. Fica registrado porque a versao anterior desta
  recomendacao esta no historico da conversa e estava errada.
- **Avisar so depois de N releases de atraso** — o incidente de hoje foi de oito
  releases sem nenhum sinal; qualquer piso reproduz o silencio que causou o
  problema. Diferente e diferente.

## Fora de escopo

- Atualizar qualquer outra ferramenta da maquina (o WinGet gerencia varias). O
  gatilho foi a CLI; varrer o resto e outro trabalho, com outro risco.
- Mexer no `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` ou no autocompact. Fechado hoje mais
  cedo, com a variavel de janela removida das duas contas.
- Levar o `atualizar-cli.sh` para outra maquina. Ele nasce com o caminho do
  WinGet do Luis parametrizado, mas Windows/WinGet/portable e a unica combinacao
  que esta entrega cobre.

## Em aberto

- (nada)
