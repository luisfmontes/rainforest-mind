# Auditor de segurança: as cinco falhas do vídeo e a OWASP Top 10 2025 além da régua de API

## Objetivo

Corrigir um erro de escopo do trabalho de 2026-08-24 (PR #87, ainda não mergeado):
o agente entregue audita **só API**, contra a OWASP API Security Top 10 2023, e
por isso **três das cinco falhas do vídeo que originou o trabalho ficaram de
fora**. O usuário apontou a falta e pediu que todas entrem — e não só para
API/SaaS, mas para todo desenvolvimento.

## O erro, medido

Busca no `agents/auditor-de-api.md` entregue ontem:

| falha do vídeo | estava lá? |
|---|---|
| 1. RLS desligada por padrão (banco falando direto com o front) | **nada** |
| 2. Front-end decidindo quem é admin | **nada** |
| 3. IDOR — trocar o ID | sim, é a API1 inteira |
| 4. Segredo no front / no histórico do git | sim, seção própria + Gitleaks |
| 5. Input sem tratamento (XSS) | **quase nada** — só "upload sem limite de tamanho ou de tipo", em API4, que é sobre consumo de recurso |

Ferramentas citadas pelo vídeo: **só o Gitleaks** entrou. `OWASP ZAP`, `Bandit` e
`OpenGrep` tiveram **zero** ocorrência no arquivo.

**A causa:** a régua encolheu o escopo. O vídeo era a procedência declarada no
design, e a OWASP API Security Top 10 virou a régua única — mas ela responde
"esta API está exposta?", e as falhas 1, 2 e 5 não são de API: são de
**arquitetura de aplicação** (fronteira de confiança entre armazenamento e
cliente, autorização decidida no navegador, entrada hostil). Caíram fora por
construção, e a entrega virou a interseção em vez do pedido.

## Decisões fechadas

- **D1 — O agente vira `auditor-de-seguranca`, e continua sendo UM só** — porquê:
  o orçamento agregado tem 373 B de folga (medido 2026-08-25) e um segundo agente
  custaria ~230 B, deixando ~143 B, que a Issue #74 já indica ser insustentável.
  O corpo cresce à vontade porque não é injetado; só a `description` paga.

- **D2 — Duas réguas nomeadas, não três** — porquê: as cinco falhas do vídeo
  **se sobrepõem quase inteiras** à OWASP Top 10 (falhas 1, 2 e 3 caem em
  Broken Access Control; a 4 em Security Misconfiguration e Cryptographic
  Failures; a 5 em Injection). Uma terceira lista paralela produziria o **mesmo
  achado três vezes**, com identificadores diferentes — que é ruído, não rigor.
  As réguas são: **OWASP Top 10 2025** e **OWASP API Security Top 10 2023**.

- **D3 — As cinco falhas entram como PADRÕES DE BUSCA concretos, ancorados na
  categoria onde moram, mais um bloco nomeado "As cinco do vídeo" que diz onde
  cada uma é caçada** — porquê: é assim que elas ficam **verificáveis** (a
  bateria confere que as cinco estão presentes e mapeadas) sem duplicar achado.
  E é fiel à tese do próprio vídeo: o que faz a busca render é o padrão
  concreto, não o nome da categoria. Nenhuma das cinco se perde: o bloco é o
  índice, e a bateria trava contra ele.

- **D4 — A OWASP Top 10 vigente é a 2025, verificada em 2026-08-25** — porquê:
  `owasp.org/Top10/2025/` declara os dez itens, e a página do projeto diz *"The
  most current released version is the OWASP Top Ten 2025"*. Não é a 2021, que
  era o que eu teria escrito de memória. Isso importa concretamente: o achado
  principal da auditoria de ontem (`actionResult.ts` devolvendo `e.message` cru)
  tem casa própria na 2025 — **A10:2025 Mishandling of Exceptional Conditions**
  — e ontem saiu classificado como "API8 Security Misconfiguration", que era o
  encaixe torto que sobrava sem a régua certa.

- **D5 — Régua se roda quando há superfície para ela; o que for pulado se declara
  com o motivo** — porquê: é a escolha do usuário (Q1a, 2026-08-25). A OWASP Top
  10 2025 e as cinco falhas rodam **sempre**; a API Security Top 10 2023 roda
  **só quando existe superfície de API**. Régua pulada sem justificativa escrita
  é entrega incompleta — a trava da Issue #61 continua valendo, só que agora
  contra "pulei porque não achei" em vez de contra seção ausente.

- **D6 — O escopo é qualquer coisa que receba entrada de fora** — porquê: é a
  escolha do usuário (Q2a, 2026-08-25). Web, API, CLI, batch, script que lê
  arquivo, PE de ADVPL/TLPP. As falhas 2 e 5 generalizam sem esforço ("regra de
  negócio é no back, o front só renderiza"; "tudo que o usuário digita é mentira
  até prova em contrário" vale em `.tlpp` igual). A falha 1 generaliza como
  **fronteira de confiança**: quem pode falar direto com o armazenamento.

- **D7 — As quatro ferramentas do vídeo entram nomeadas, e nenhuma é instalada** —
  porquê: `OWASP ZAP`, `Gitleaks`, `Bandit` e `OpenGrep` são o que o vídeo
  recomenda, e nomear ferramenta é barato e útil; instalar é alterar o ambiente
  do usuário (regra 15). O agente **recomenda o comando** e diz o que cada uma
  cobre; quem decide rodar é o dono do repositório. O ZAP fica marcado como
  **execução contra alvo vivo**, o que este agente não faz (D8).

- **D8 — Continua valendo: acha e não conserta, e não manda requisição nenhuma** —
  porquê: são as decisões D3 e D7 do design de 2026-08-24 e nada nesta emenda as
  toca. O ZAP entra como recomendação escrita, nunca como comando executado.

- **D9 — Esta emenda vai para o mesmo PR #87** — porquê: o PR não foi mergeado, e
  o defeito é do que está nele. Corrigir antes do merge é mais barato que mergear
  metade e abrir dívida. É a escolha do usuário (Qa, 2026-08-25).

- **D10 — Fluxo novo com slug próprio, não reabertura do de ontem** — porquê: o
  `estado.cjs` não tem reabertura, e forjar um estado "reaberto" à mão seria
  escrever no registro um caminho que a máquina não percorreu. Slug novo, mesma
  branch, mesmo PR — o registro fica honesto e o PR fica um só.

## Avaliado e descartado

- **Um segundo agente só para camada de aplicação** — descartado por medição de
  orçamento: ~230 B de `description` sobre uma folga de 373 B deixaria ~143 B, e
  a Issue #74 já documenta que esse aperto não se sustenta.

- **As cinco falhas como terceira régua paralela** — descartado por sobreposição:
  quatro das cinco têm casa direta na OWASP Top 10 2025, e a lista paralela
  produziria o mesmo achado com dois identificadores. Viraram padrão de busca
  ancorado (D3), que é onde elas rendem.

- **Ancorar na OWASP Top 10 2021** — descartado por verificação: a vigente é a
  2025 (`owasp.org/Top10/2025/`, conferido em 2026-08-25). Escrever 2021 seria
  fixar régua desatualizada, e o item que mais importava para o achado real de
  ontem (A10 Mishandling of Exceptional Conditions) só existe na 2025.

## Fora de escopo

- Consertar o que o agente achar. Continua sendo trabalho separado.
- Executar ZAP, strix ou qualquer scanner contra alvo vivo. Continua sendo fase 2,
  plantada.
- Instalar Gitleaks, Bandit ou OpenGrep. São recomendação escrita.
- Segurança de skill/agente (prompt injection, tool poisoning). Continua sendo a
  outra régua, plantada.

## Em aberto

- Nenhum. As decisões vieram das respostas do usuário em 2026-08-25 (emendar o
  #87; acrescentar a Top 10 clássica; régua roda quando há superfície; escopo é
  qualquer entrada externa), e o que ele não decidiu foi apurado por leitura ou
  verificação de fonte, não suposto.
