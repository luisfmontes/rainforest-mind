# Design — a ponte ganha o bloco do projeto (entrevista + varredura), e o setup declara integrações opcionais

Origem: pedido de 2026-08-28 — "o setup não entrevista o usuário sobre o
repositório" e "quero CLAUDE.md, AGENTS.md e GEMINI.md saindo de um
entendimento só" — lido contra `skills/setup/SKILL.md`, `commands/setup.md` e
`commands/ponte.md`.

Data: 2026-08-28. Status: aprovado em 2026-08-31 — Q1 fechada com os fatos
apurados no ambiente (abaixo, em "Em aberto"); demais decisões fechadas na
recomendada em 28/08.

## Objetivo

Duas entregas com donos diferentes:

1. **O entendimento do repositório** — o que o projeto é, como builda, como
   testa, o que é "pronto" aqui, o que não se toca — não existe em lugar
   nenhum: a ponte gera os três arquivos (`CLAUDE.md`, `AGENTS.md`,
   `GEMINI.md`) só com o bloco de **regras** derivado do SKILL.md. Falta o
   bloco do **projeto**, nascido de varredura + entrevista, um entendimento
   para os três agentes.
2. **Integrações opcionais** (hoje: o MCP do WhatsApp e o Sabiá, repositórios
   próprios do usuário) não têm onde ser declaradas, mencionadas nem
   conferidas — quem instala o plugin nem fica sabendo que existem, e quem as
   usa não tem o `/saude` olhando para elas.

Pronto quando: `ponte.cjs --entrevistar` produz `docs/rainforest/projeto.md`
com o entendimento aprovado; `--aplicar` passa a derivar dois blocos por
arquivo (regras + projeto), cada um no seu marcador, regeneráveis; o `/setup`
lista integrações declaráveis com uma linha de descrição cada, desligadas por
padrão; e o `/saude` confere **só** as integrações que o setup declarou, uma
linha cada, sem rede.

## O mecanismo, nomeado

- O `/setup` diz explicitamente o que não faz ("não recomenda automação") e a
  ponte diz que **quem escolhe agente é o setup, quem recebe arquivo é alvo
  explícito**. A divisão está certa e este design não a mexe: entendimento de
  repositório é assunto da **ponte** (é ela que possui os três arquivos, os
  marcadores e o invariante "gerado não se edita à mão") — o setup só ganha o
  vocabulário de integrações.
- O invariante da ponte — bloco gerado se **regenera**, nunca se edita — exige
  que o entendimento tenha fonte canônica fora dos três arquivos. Daí o
  `docs/rainforest/projeto.md`: versionado (outro dev herda o entendimento),
  editável (é a fonte, não o derivado), e a ponte deriva dele.

## Decisões fechadas

- **D1 — a entrevista mora na ponte, não no setup.** `ponte.cjs --entrevistar`
  (conduzido pela skill, no estilo do `/brainstorm`): primeiro a **varredura**
  responde o que o ambiente responde — stack, gerenciador de pacotes, comandos
  de build/teste achados em manifesto e CI, layout de pastas — porque fato não
  sobe para o usuário (regra 16); depois a rodada de `Q`s numeradas, cada uma
  com recomendada, cobre só o que é decisão dele: o que é "pronto" aqui, o que
  não se toca, convenções que não estão escritas, política de revisão. O
  resultado aprovado grava em `docs/rainforest/projeto.md`.

- **D2 — os três arquivos ganham um segundo bloco marcado,
  `rainforest-mind:projeto`, derivado do `projeto.md`.** Mesmo contrato do
  bloco de regras: sem marcador entra no fim, com marcador só o bloco é
  substituído, texto alheio sobrevive, nada de caminho de home chumbado. Um
  entendimento, três arquivos — a adaptação por agente continua onde já
  existe (a explicação das travas muda por host; o projeto é idêntico).

- **D3 — o setup ganha a seção `INTEGRACOES`, declarável por chave:**
  `--ligar integracao-<nome>` no mesmo padrão das chaves atuais, todas
  desligadas por padrão, cada uma com uma linha de descrição e o link do
  repositório no estado — é a "menção" que faz quem instala saber que existem,
  sem empurrar nada. As duas primeiras: `integracao-whatsapp-mcp` e
  `integracao-sabia`. A lista é dado (registro em `setup.cjs`), não código
  espalhado: integração nova entra numa linha.

- **D4 — o `/saude` confere só o que foi declarado, no padrão do
  `checarClaudeMem` que já existe:** chave desligada → a seção nem aparece;
  ligada → uma linha por integração, checagem local e barata (binário/config/
  processo presente — Q1 define qual, por integração), sem rede, com a ação de
  conserto nomeada. Integração declarada e quebrada é `aviso`, nunca `alerta`
  — opcional não derruba saúde de quem optou.

## Avaliado e descartado

- **Entrevista dentro do `/setup`.** Era o pedido literal, e o próprio texto do
  setup barra: ele configura a máquina e a pasta de dados, e delega o que é do
  repositório. Colocar a entrevista lá quebraria a divisão que a ponte nomeia
  ("qual agente você usa é configuração; qual repositório recebe arquivo não
  é") — e o repositório é de quem? O alvo explícito da ponte responde isso; o
  setup não tem como.
- **Gerar o bloco do projeto direto da entrevista, sem `projeto.md` no meio.**
  Perde a fonte canônica: o dia em que alguém quiser ajustar uma linha do
  entendimento, ou edita o bloco gerado (proibido, e com razão — foi assim que
  as duas CLAUDE.md divergiram em 2026-08-10) ou re-entrevista tudo. O arquivo
  intermediário é o que torna o bloco regenerável e o entendimento versionável.
- **`/saude` detectar as integrações sozinho, sem declaração no setup.**
  Varredura de máquina atrás de repositório alheio é adivinhação: acusaria
  falta em quem nunca quis, e o silêncio de quem tem mas não declarou seguiria
  igual. Declarar é uma linha, e deixa o `/saude` no que ele sabe fazer:
  conferir o que foi prometido.
- **Empacotar WhatsApp-MCP e Sabiá dentro do plugin.** São repositórios
  próprios, específicos, com ciclo de release próprio — "o pessoal pode querer
  usar ou não" é exatamente o caso de menção + chave, não de dependência.

## Fora de escopo

- **O conteúdo das regras da ponte** — o bloco `rainforest-mind:inicio` não
  muda uma linha.
- **Recomendação de automação no projeto** — segue com o
  `claude-automation-recommender`, como o setup já aponta.
- **Instalação das integrações** — o `/saude` confere e ensina a ação; quem
  instala é o usuário, no repositório delas (regra 15: ninguém altera o
  ambiente do usuário).

## Em aberto

- **Q1 — FECHADA em 2026-08-31, com os fatos apurados no ambiente:**
  - `integracao-whatsapp-mcp`; **detecção:** GET `http://localhost:3005/api`
    com timeout curto — qualquer resposta HTTP (um 404 inclusive) prova a
    bridge de pé; é loopback puro, sem rede externa, e é a mesma checagem que
    o hook de abertura do rainforest já faz. A arquitetura real: bridge Go
    (whatsmeow) residente em 127.0.0.1:3005 + servidor MCP Python, repo
    `C:/Projetos/whatsapp-mcp`. **Conserto:** subir a bridge no repositório
    local (binário Go de `whatsapp-bridge/`, ou o serviço configurado da
    máquina).
  - `integracao-sabia`; **detecção:** rasa = existência de `sabia.py` e da
    `.venv` no caminho registrado em `projetos.json` (hoje
    `C:/Projetos/sabia`) — Sabiá é CLI Python local, sem serviço residente,
    então "presente" é repo instalado, não porta. Profunda (opcional, mais
    cara): exit 0 de `.venv/Scripts/python sabia.py doutor`, o autodiagnóstico
    que o próprio repo mantém. **Conserto:** `python -m venv .venv &&
    .venv/Scripts/pip install -r requirements.txt` e rodar o `doutor`.
