# Régua do batedor por trilha: instalar, enxertar, ler

## Objetivo

Fazer o veredito do batedor medir **o modo de uso que está de fato na mesa**, em vez de
medir sempre instalação. Fecha a Issue #93.

O problema, na palavra do usuário: *"precisamos reavaliar as perguntas do batedor, pq
quando digo acoplar é cópia ou reimplementar ou tirar ideias deles e que possa ser útil
pra nós"*. A palavra **acoplar** cobre três coisas e as seis perguntas de hoje só medem
a primeira.

Contagem das 40 linhas com data de `vigias/livro-de-repos.md`, medida em 2026-08-25:

| veredito | quantas |
|---|---|
| `não acopla` seco | 23 |
| `não acopla` + "tem peça" | 6 |
| **adotado** | 5 |
| **nenhum dos dois — string inventada na hora** | **6** |

**29 de 40 (73%) são "não acopla"**, e as reprovações se concentram nas perguntas 2
(colide com o que já roda), 3 (custo em token por sessão) e 5 (dá pra instalar em
pedaço) — as três que **só existem se o modo de uso for instalar**.

O achado que a issue não tinha, e que muda o desenho: **o vocabulário de veredito já
quebrou na prática**. Os outros 6 são `olhar de perto`, `testar, custo zero (npx)`,
`ler, não copiar`, `referência de estrutura`, `índice de descoberta` e
`candidato, não avaliado` — seis rodadas, seis termos inventados, cada uma achando que
o caso era especial. O livro **já diz** em prosa que o default é `não acopla` e que "tem
peça" é veredito legítimo; a prosa não segurou.

O caso puro continua sendo o `ChristopherKahler/base`: reprovou em 2, 3 e 5, e a licença
dele (PolyForm Noncommercial) **proíbe copiar de qualquer jeito**. Instalar nunca esteve
na mesa. As três reprovações mediram um caminho que não existia, e o veredito saiu
"não acopla" quando a resposta honesta era "não instala, mas enxerta".

## Decisões fechadas

- **D1 — A trilha é propriedade do PROBLEMA, e a âncora a escolhe ANTES da busca.** —
  porquê: trilha escolhida no momento de avaliar é escolhida **depois** de ver o
  candidato, e aí vira a trilha em que ele passa. É o defeito que o próprio livro já
  documenta na seção "Fila da primeira rodada": *"o veredito adiantado vira a hipótese
  que a avaliação tenta confirmar"* — e naquela rodada **dois dos três candidatos
  morreram na âncora, não no repo**.

- **D2 — Cascata: Instalar → Enxertar → Ler, cada degrau com veredito próprio.** —
  porquê: sem cascata o `base` continua saindo "não acopla", que é falso — ele tem peça
  forte e a licença nunca permitiu instalar. Com cascata ele sai "não instala,
  **enxerta**".

- **D3 — A cascata só desce enquanto a pergunta 1 continuar passando, e o degrau `Ler`
  é conquistado, não herdado.** — porquê: é o freio contra a cascata virar consolação
  automática. Reprovou na pergunta 1 (*"resolve o problema ancorado?"*), acabou — sai
  `fora da âncora`, sem cascata, porque não resolve problema que o usuário tem. Passou
  na 1 e reprovou nas de instalação (2, 3, 5)? Aí desce, porque colisão de hook e
  granularidade de instalador são irrelevantes para quem vai reimplementar. E há fundo
  de poço: reprovando também na pergunta 2 de `Ler` (*"está legível o bastante para valer
  voltar?"*), o veredito é `não vale voltar`. Descer exige **evidência positiva** em cada
  degrau, nunca só ausência de reprovação no degrau acima.

- **D4 — A âncora com a trilha declarada mora no `vigias/fila-de-repos.jsonl`.** —
  porquê: se a âncora escolhe a trilha antes da busca (D1), ela precisa estar escrita
  onde o vigia leia. A seção "Fila da primeira rodada" do livro é exatamente o que a
  ideia plantada `fila-do-livro-de-repos-e-prosa-que-ninguem-le` chama de *"prosa que o
  apurador não lê"*. As duas se resolvem juntas, e a segunda já estava desenhada.

- **D5 — Âncora sem trilha declarada RECUSA a avaliação daquele candidato.** — porquê:
  vai acontecer com entrada antiga da fila e com ideia plantada sem pensar em trilha. Se
  a falta cair num default — e o default natural seria `Instalar`, que é a régua de hoje
  —, o desenho inteiro volta ao ponto de partida **em silêncio**, justamente para as
  entradas que ninguém revisou. Mesmo raciocínio do `validarSlug` da #100 e dos
  `--antes`/`--depois` obrigatórios da #101: recusa explícita, nunca correção por baixo,
  porque corrigir por baixo esconde o defeito de quem chamou.

- **D6 — Vocabulário de veredito FECHADO, com sete strings e sem meio-termo.** — porquê:
  os 6 termos inventados acima. String livre não é registro, é anotação: não dá para
  contar, não dá para revisitar por veredito, e cada rodada inventa um termo novo.

  ```
  Instalar   ->  instala      |  nao instala
  Enxertar   ->  enxerta      |  nao enxerta
  Ler        ->  vale voltar  |  nao vale voltar
  terminal   ->  fora da ancora        (reprovou na pergunta 1, sem cascata)
  ```

  **O meio-termo sumiu de propósito.** "Tem peça aproveitável" existia porque não havia
  trilha para ela; com a cascata, "tem peça" **é** a trilha Enxertar. Ela deixa de ser
  consolação de quem reprovou e vira o resultado de primeira classe que a issue pediu,
  sem precisar de um veredito próprio — que é o que a issue chamava de *"'tem peça' virou
  consolação de quem reprovou em vez de resultado de primeira classe"*.

- **D7 — O vocabulário se MECANIZA num `conferir-*`, não fica em prosa.** — porquê: o
  vocabulário de hoje já está escrito no livro e mesmo assim seis rodadas o furaram.
  Regra em prosa que o próprio autor da linha interpreta não trava nada — é a mesma
  frase que originou o `conferir-entrega.cjs` e que decidiu a #101 no mesmo dia:
  *"enquanto o veredito de uma checagem for redigido pelo mesmo agente que ela deveria
  travar, ela não trava nada"*. Custa zero byte de injeção e recusa antes do commit.

- **D8 — O checador valida só linha com data POSTERIOR à mudança.** — porquê: as 6
  linhas de veredito inventado não cabem no vocabulário novo. Migrá-las significa
  **rejulgá-las sob a régua nova**, que é o erro que a seção "Por que a pergunta 4 aceita
  código" do próprio livro documenta: *mudar critério de veredito com a peça em cima da
  régua é reescrever a medida para caber no que se mediu*. A issue já dizia não reescrever
  os 29; isto estende a mesma proteção às 6.

- **D9 — Licença é FATO registrado, nunca pergunta que reprova — inclusive na trilha
  Enxertar.** — porquê: a issue propunha, como pergunta 3 de Enxertar, *"a licença
  permite reimplementar a partir da ideia"*. Isso contradiz o princípio
  `licenca-e-fato-nao-veredito`, que o livro **já aplica** nas linhas do `evolution-api`
  e do `OpenViking`. E o conflito não é só formal: a trilha responde a permissão **por
  construção**, porque Enxertar é reimplementar a partir do mecanismo lido, e o que
  licença proíbe é **copiar**. Manter a licença como pergunta que reprova recria, dentro
  da trilha nova, o mesmo erro que a issue conserta — medir contra um caminho que não
  está na mesa. A pergunta vira **"o que exatamente ela proíbe?"**, com a resposta
  escrita na linha, como o `ChristopherKahler/base` já tem hoje.

- **D10 — A linha registra o CAMINHO da cascata, não só a trilha final.** — porquê:
  `Instalar → Enxertar` diz duas coisas que a trilha final não diz: que instalar foi
  avaliado e por onde caiu, e qual pergunta reabre numa revisita. A coluna "Reprovou em"
  passa a ser lida junto da trilha em que a reprovação aconteceu — "reprovou em 2 e 3"
  não significa nada sem saber que era a régua de Instalar.

- **D11 — A pergunta de revisita é por trilha final, e `Ler` não se revisita.** —
  porquê: o gatilho duplo (60+ dias **E** push posterior) continua como está, que o livro
  já justifica. O que muda é a pergunta:

  | trilha final | pergunta da revisita |
  |---|---|
  | Instalar, adotado | *"ainda vale o que custa?"* (a de hoje) |
  | Instalar, não instala | *"a reprovação caiu?"* (a nomeada na coluna) |
  | Enxertar | *"a peça já foi enxertada, ou ainda está plantada?"* — responde-se no `ideias.jsonl`, não no repo de terceiro |
  | Ler | **não se revisita** |

  Repo de peça plantada há 60 dias não pede revisita do repo: pede colheita da ideia. E
  ponteiro de leitura já respondeu o que tinha para responder — reavaliá-lo gasta teto de
  revisita com quem não tem pergunta.

- **D12 — As seis perguntas de Instalar não mudam.** — porquê: elas estão certas para o
  modo de uso que medem, inclusive a 4 com a emenda de 2026-08-12 que passou a aceitar
  prova de código. O defeito nunca foi a régua de instalar; foi aplicá-la a quem não ia
  instalar.

## Avaliado e descartado

- **Trilha escolhida pelo vigia no momento de avaliar** — a medição que o matou está no
  próprio livro: na fila da primeira rodada, **dois dos três candidatos morreram na
  âncora, não no repo**, e as duas teses que os mataram tinham sido escritas a partir de
  README, antes de ler código. Quem escolhe depois de ver o candidato escolhe a régua em
  que ele passa. Ver D1.

- **Cascata livre, descendo até achar onde passa** — sem o freio da pergunta 1, todo
  reprovado vira `vale voltar`, e o livro deixa de distinguir "tem peça de verdade" de
  "não achei onde reprovar". Seria trocar um default único (`não acopla`, 73% das linhas)
  por outro default único no extremo oposto. Ver D3.

- **Manter o vocabulário livre, com a régua só escrita em prosa** — refutado por
  contagem, não por opinião: a regra do default e a legitimidade de "tem peça" **já estão
  escritas** no livro, e ainda assim 6 das 40 linhas inventaram termo próprio. A prosa
  teve 40 oportunidades e falhou em 6. Ver D6 e D7.

- **Um veredito de meio-termo por trilha (`passa com ressalva`)** — descartado porque a
  ressalva vira o novo lugar onde a prosa se acumula, e porque a cascata já **absorve** o
  meio-termo: "tem peça" não é um estado intermediário de Instalar, é a trilha Enxertar.
  Ver D6.

- **Licença como pergunta que reprova na trilha Enxertar** (a proposta literal da issue)
  — descartada por contradizer o princípio `licenca-e-fato-nao-veredito`, que o livro já
  aplica em duas linhas, e por recriar dentro da trilha nova o erro que a issue conserta:
  medir contra copiar, que é o caminho que Enxertar não usa. Ver D9.

- **Migrar as 6 linhas de veredito inventado para o vocabulário novo** — descartada pelo
  precedente escrito na seção "Por que a pergunta 4 aceita código" do próprio livro:
  mudar critério com a peça em cima da régua é reescrever a medida para caber no que se
  mediu. Ver D8.

- **Registrar só a trilha final na linha, sem o caminho** — mais curto, e perde a
  informação de revisita: sem saber em que trilha a reprovação aconteceu, "reprovou em 2
  e 3" não diz nada. Ver D10.

- **Assumir `Instalar` quando a âncora não declara trilha** — é o default que reconstrói
  o defeito original em silêncio, e justamente para as entradas que ninguém revisou. Ver
  D5.

## Fora de escopo

- **Reescrever os 29 vereditos antigos** — pela mesma razão de D8. A régua nova vale
  daqui para a frente; o que existe fica com a data que tem.
- **Mexer no gatilho de revisita** (60+ dias E push posterior) — D11 muda a pergunta, não
  o gatilho.

## Perguntas das trilhas novas

**Enxertar** (reimplementar o mecanismo):

1. resolve o problema ancorado?
2. o mecanismo foi **lido no código**, não no README?
3. o que exatamente a licença proíbe? (fato registrado, D9)
4. o custo de reimplementar cabe, contra o que entrega?

**Ler** (só a ideia):

1. resolve o problema ancorado?
2. está legível o bastante para valer voltar?

A pergunta 1 é comum às três trilhas de propósito — é ela o freio da cascata (D3).

## Em aberto

- Nada. A fronteira esvaziou em quatro rodadas.
