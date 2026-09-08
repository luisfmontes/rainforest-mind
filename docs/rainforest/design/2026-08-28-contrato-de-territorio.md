# Design — o contrato de território, extraído do primeiro território (Python)

Origem: conversa de 2026-08-28. Premissas fixadas nela: **domínio é skill,
papel é agente** (os papéis do harness ficam agnósticos; o território entra
por referência no briefing); e **território não mora no rainforest** — aqui
mora só o contrato. O repo de AdvPL já existente é o segundo implementador
natural, e o teste de que a interface não nasceu enviesada.

Data: 2026-08-28. Status: **em obra desde 2026-09-08** — a espera pelo núcleo
estável foi levantada, e a ordem dos territórios foi invertida. Ver a seção
"Revisão de 2026-09-08" no fim deste arquivo, que é onde mora a decisão em
vigor; o corpo acima e as Qs abaixo ficam como estavam para preservar o
raciocínio original.

## Objetivo

O fluxo é agnóstico de stack, mas a régua não é: "pronto quando" em Python é
`pytest -x` com fixture, em Flutter é `flutter test` com widget test, em
AdvPL é outra coisa. Hoje esse conhecimento entra por improviso a cada plano.

Pronto quando: existe `docs/rainforest/contrato-territorio.md` versionado
dizendo o que um pacote de território **fornece** e o que o rainforest
**consome**; existe um primeiro território (Python), em repositório próprio,
implementando o contrato; e um plano escrito com o território ativo referencia
templates de critério e padrão de mutação dele, provado num fluxo real.

## Decisões (fechadas na conversa)

- **D1 — o contrato nasce por extração, não por especificação.** O primeiro
  território (Python) se constrói direto; o contrato é o que ele precisou.
  Contrato desenhado antes do caso concreto erra a interface — e o segundo
  implementador (AdvPL, que já existe) é quem valida que ela generaliza.

- **D2 — o que o território fornece (mínimo, a confirmar na extração):**
  templates de critério falsificável para o `plano`; padrão de bateria e de
  alvo de mutação do stack; comandos canônicos (build, teste, lint) com exit
  code; e a regra de detecção que deixa `semear`/`setup` reconhecer que um
  repositório é daquele território.

- **D3 — papéis continuam no harness.** Executor, revisor, sabotador não se
  duplicam por stack; o briefing referencia a skill do território. M papéis ×
  N territórios sem explosão.

## Em aberto (responder no computador, com os repos na frente)

- **Q1 — qual repo Python é o piloto?** ➡️ Recomendo o de maior volume de
  fluxo previsto — o contrato extrai melhor de onde vai ser mais usado.
- **Q2 — como o território chega na sessão:** plugin separado no marketplace,
  ou skill instalada por caminho? ➡️ Recomendo plugin separado, espelhando o
  que o rainforest já faz consigo mesmo.
- **Q3 — o segundo território é AdvPL (validar contrato com o que já existe)
  ou Flutter (forçar o contrato a aguentar app além de API)?** ➡️ Recomendo
  AdvPL: valida com custo quase zero; Flutter vem como terceiro, quando o
  contrato já tiver dois pontos de apoio.

---

## Revisão de 2026-09-08 — AdvPL vira o PRIMEIRO território

O que mudou não foi o desenho, foi a evidência. Em 2026-09-05 este design foi
inventariado como acervo parado, com a recomendação de esperar o núcleo estável
(fluxos 8 e 10). Em 2026-09-08 apareceram dois fatos que aquela recomendação não
conhecia, e os dois apontam para AdvPL:

1. **Existe medição, e ela é desfavorável ao fluxo.** O usuário comparou este
   plugin contra um plugin de domínio AdvPL já instalado nesta máquina, gerando
   código no ecossistema. O plugin de domínio **venceu na qualidade do código**;
   a impressão do usuário é que o fluxo daqui é o melhor dos dois. Ou seja: o
   par que interessa — método daqui, conhecimento de lá — é exatamente o que o
   contrato de território existe para montar, e é o único par que nunca foi
   medido.

2. **O fornecedor de conhecimento já está pronto e já roda junto.** Os dois
   plugins estão habilitados na mesma conta hoje, e o conflito é preciso: o
   plugin de domínio traz uma "locomotiva" própria, cuja description captura
   "continuar a demanda", "o que falta", "onde parei" — o mesmo terreno do
   fluxo. Seis das skills dele já nascem com `disable-model-invocation: true`,
   isto é, **já são ferramenta chamável, não motorista**. Não há fusão a fazer:
   há arbitragem, que é o que o contrato define.

### D4 — a ordem se inverte: AdvPL primeiro, Python como validador

A Q3 recomendava AdvPL como **segundo** território, "valida com custo quase
zero". Passa a primeiro. O papel do segundo — provar que a interface generaliza,
que é o D1 — fica com o Python. Mesma função, ordem trocada.

O motivo é o próprio D1 levado a sério: *o contrato nasce por extração, não por
especificação*, e extrai-se melhor de onde há caso concreto, fornecedor pronto e
medição. Python tinha volume previsto; AdvPL tem os três.

### D5 — as três exoticidades do AdvPL entram nomeadas, como "território pode não ter"

O risco de extrair primeiro de AdvPL é o contrato sair com a forma dele. O
antídoto custa uma seção: estas três coisas são do território, **nunca** viram
campo obrigatório do contrato.

- **Não gera artefato — compila para dentro de um repositório de objetos.** O
  D2 fala em "comandos canônicos (build, teste, lint) com exit code"; aqui
  `build` não produz arquivo que se possa inspecionar, e o efeito é remoto.
- **Não tem runner de teste local.** Rodar teste unitário exige ambiente
  dockerizado de pé. Território sem isso é o caso comum, não a exceção.
- **Boa parte do conhecimento não é arquivo, é serviço remoto atrás de
  credencial.** O D2 supõe que o território **fornece** templates e padrões,
  isto é, conteúdo versionado. Aqui parte do conteúdo é consulta viva. O
  contrato precisa aceitar território que forneça *ponteiro para serviço* e não
  só arquivo — e precisa dizer o que acontece quando o serviço está fora.

### D6 — medir antes de construir

Nenhuma linha do território AdvPL antes de existir uma medição do par
"fluxo daqui + conhecimento de lá" contra o baseline que já venceu. O
instrumento é o `claude plugin eval`: casos em `case.yaml`, graders mecânicos
(`file_exists`, `tool_used`) travando e grader `llm` apenas informando.

Três coisas já apuradas sobre o instrumento, para ninguém redescobrir:

- Ele existe nesta CLI (2.1.263) e resolve este plugin instalado; exige
  `CLAUDE_CODE_WALNUT_SPIRE=1`, senão responde que o subcomando está em early
  access.
- **Grader `llm` só enxerga o transcript.** Não confere disco, e por isso já
  aprovou agente que escreveu "feito" sem criar o arquivo pedido. É a regra 12
  reaparecendo dentro do harness de avaliação: julgamento informa, mecânico
  trava.
- **`tool_used: Skill` é gate ruim na maioria dos casos.** Medição de quem já
  rodou: a tool `Skill` disparou explicitamente em 1 de 6 casos — nos outros o
  modelo resolve por raciocínio geral sem invocar a skill. Travar merge nisso
  deixaria o CI vermelho sem regressão.

**Ressalva honesta, não verificada:** a ablação nativa é com-plugin contra
sem-plugin. Se dá para montar braços com *combinações diferentes de plugins*
(fluxo + domínio contra domínio sozinho) não foi confirmado — é a primeira coisa
a testar, porque é dela que depende o D6 ser executável como está escrito.

### D7 — o território não mora aqui, e a fronteira ganhou um segundo motivo

O design já dizia "território não mora no rainforest; aqui mora só o contrato".
A partir de 2026-09-08 isso deixa de ser só arquitetura e vira **restrição de
publicação**: este repositório é público, e o território AdvPL carrega
identificadores de empregador, de cliente e de colega que não podem aparecer
aqui. Nome de produto de mercado (AdvPL, TLPP, Protheus, TOTVS) não identifica
empregador e continua permitido; nome de empresa, de marketplace privado, de
host de serviço interno, de repositório de trabalho e de pessoa, não.

Consequência prática: o `gate-publicacao-destino.cjs` precisa ganhar esses
padrões, e a varredura de 2026-09-08 achou **13 arquivos versionados** que já os
carregam — anteriores a este design, e a tratar em trabalho próprio.

### Q em aberto depois desta revisão

- **Q4 — o território AdvPL é plugin novo, ou o conhecimento é consumido do
  plugin de domínio que já existe?** Recomendo **plugin novo e magro**, que não
  duplica conhecimento: ele declara, por estágio do fluxo, quais skills do
  fornecedor podem ser chamadas. Duplicar conteúdo envelhece; declarar, não.
- **Q5 — onde ele mora?** Recomendo o marketplace privado do próprio squad.
  **Não** no repositório do time que mantém o plugin de domínio: o manifesto
  daquele marketplace diz, em uma linha, que aquele time não edita plugin
  alheio e mantém os seus no próprio repo — e ignorar isso já foi erro
  registrado uma vez.
