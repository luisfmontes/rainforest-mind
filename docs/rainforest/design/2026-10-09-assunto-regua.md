# Régua D7 da memória por assunto sem as distorções (#436)

## Objetivo
O número que a régua D7 lê na colheita de 2026-10-23 (`node scripts/memoria.cjs utilidade --relatorio`) é a
fração de sessões que tiveram ao menos uma memória útil. Ele não pode contar busca que só cita o comando,
nota ganha por tautologia com o pedido nem memória reinjetada porque a abertura cortada não entrou no dedupe.
Tudo tem que estar no `main` e repontuado antes da colheita, sem mover a data.

## Decisões fechadas
- **D1 — Busca ativa é instrução, não texto** — `contarBuscasArquivo` (`scripts/lib/utilidade.cjs:510-534`)
  conta um `tool_use` Bash/PowerShell só quando alguma **instrução** do comando começa pela chamada
  `node <...>memoria.cjs buscar`. Antes, a instrução pode ter atribuições de ambiente (`X=1`), e a chamada pode
  vir depois de `cd <dir> &&`. O corpo de heredoc (`<<'EOF'` ... `EOF`) sai antes da análise, e as instruções se
  separam por `&&`, `||`, `;`, `|` e quebra de linha. Porquê: hoje o `includes('memoria.cjs buscar')` conta
  `git commit -F - <<'EOF'` com o texto dentro (3 de 32 casos nos transcritos do repo). Regra técnica, sem
  impacto de produto.
- **D2 — A nota do canal do assunto desconta os termos do pedido** — para servida dos canais `pedido` e
  `subagente`, `calcularNota` (`utilidade.cjs:416-438`) mede só os termos raros da memória que **não** estavam
  no texto que disparou a injeção. Para `pedido`, esse texto é a linha do pedido (`partesTexto[indiceInjecao]`).
  Para `subagente`, é o briefing. A abertura não muda. Porquê: o `Read`/`Edit` seguinte do arquivo que o pedido
  citou carrega os mesmos termos, e a memória ganha nota sem ter sido usada.
- **D3 — Memória sem termo raro fora do pedido sai da conta** — se todos os termos raros da memória estavam no
  pedido, a servida não é medida: não conta como útil nem como inútil, nem no numerador nem no denominador da
  régua e do relatório por canal. Ela fica gravada com uma marca própria (nota nula) para o relatório dizer
  quantas saíram. Porquê: não há como medir uso sem tautologia, e contar como inútil puniria o canal novo por
  culpa do instrumento. Decisão do usuário, 2026-10-09 (Q1 A).
- **D4 — A abertura grava os ids que serviu** — `hooks/memoria-session-start.cjs` grava os ids das
  observações que de fato entraram no bloco (depois da escada de texto e do teto) em
  `<raiz>/memoria-assunto/<sessao>.json`, o mesmo arquivo de dedupe do canal do pedido. Na sessão retomada,
  ele **soma** os ids aos que já estão lá. A gravação é em `try` próprio: se falhar, a abertura não muda. A
  leitura do transcrito (`lerServidasDoInicio`, 2 MiB) continua só para o arquivo que ainda não existe
  (sessão aberta antes da atualização). Porquê: a linha cortada pela escada 200/160/120 não casa no
  `acharAlvo`, e a retomada fica além dos 2 MiB. Fecha o item 3, o comentário da Issue e o menor (c). Decisão
  do usuário, 2026-10-09 (Q2 A).
- **D5 — Só vai para os já servidos o que entrou no bloco** — `hooks/memoria-assunto-prompt.cjs:130` grava
  apenas os ids que `montarBlocoAssunto` de fato pôs no bloco, não todas as `achadas`. Porquê: hoje a memória
  cortada pelo teto de 1.500 B fica marcada como servida sem ter entrado (menor b).
- **D6 — `SQLITE_BUSY` no `ALTER TABLE` não engole a sessão** — os `try/catch` vazios de `criarSchema`
  (`scripts/memoria.cjs:419-438`) passam a engolir só "duplicate column". Banco ocupado propaga, e a passada de
  pontuação trata como ocupado (`ehBancoOcupado`): a sessão fica para a próxima passada, sem ser marcada como
  falha definitiva. Porquê: hoje um BUSY no `ALTER` faz o `INSERT ... canal` falhar com "no such column", e as
  sessões daquela passada saem da fila para sempre (menor d).
- **D7 — O peso do projeto atual fica como está** — o desempate só no bm25 igual
  (`hooks/lib/memoria-assunto.cjs:60-64`) é a decisão D4 do design `2026-10-08-memoria-por-assunto`. A parte
  das duas grafias foi resolvida pelo nome canônico (#435). Decisão do usuário, 2026-10-09 (Q3 A). O menor (a)
  se fecha na Issue com essa nota.
- **D8 — Repontuar a janela com as regras novas** — subcomando `node scripts/memoria.cjs utilidade --repontuar
  --desde <AAAA-MM-DD>`. Apaga de `uso_memoria` e `uso_memoria_sessoes` as sessões pontuadas a partir da data,
  devolve essas sessões à fila e roda a pontuação pelas regras de D1–D3. É idempotente e faz backup antes
  (`fazerBackupDoBanco`). Sessão cujo transcrito não existe mais fica de fora e aparece contada na saída. A
  colheita de 2026-10-23 fica onde está, e o `ao_colher` da ideia `regua-d7-memoria-por-assunto` ganha o passo
  "rodar `--repontuar --desde 2026-10-08` antes do `--relatorio`". Porquê: as sessões já pontuadas carregam as
  distorções, e os transcritos ainda existem. Decisão do usuário, 2026-10-09 (Q4 A).

## Fora de escopo
- Mudar a régua (limiares 40% e 1/3, base 27%) ou o critério de seleção do canal do assunto.
- Usar o arquivo de ids da abertura (D4) na pontuação da utilidade da abertura. Ela continua casando pelo
  `acharAlvo`, e a linha cortada da abertura segue sem id na **pontuação**: a régua conta sessões com alguma
  memória útil, e a abertura serve até 14.

## Critério de pronto
Cada item tem um caso de teste que falha com o comportamento atual (a Issue pede isso). O `--repontuar` roda
numa cópia do banco real com os transcritos reais e imprime quantas sessões refez, quantas faltaram transcrito e
quantas servidas saíram pela D3. O `--relatorio` roda depois disso.
