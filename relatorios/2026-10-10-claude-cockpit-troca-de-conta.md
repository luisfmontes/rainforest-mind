# claude-cockpit — troca de conta entre assinaturas — 2026-10-10

Indicado pelo Luís. Problema ancorado: a **troca automática de conta pelo uso**, que o
design `docs/rainforest/design/2026-10-09-mods-pr-e-plugins.md` deixou como fluxo próprio,
depois da #456, "trocando a credencial que o Claude Code oficial lê". Trilha declarada:
**Instalar**, com **Enxertar** como degrau de baixo.

| Repo | Commit lido | Licença | Push (API) | Criado |
|---|---|---|---|---|
| `christianjohnston-ai/claude-cockpit` | clone raso de 2026-10-10 | MIT | 2026-10-10 | 2026-10-10 (4 estrelas, 1 autor) |

Lidos inteiros: `README.md`, `docs/how_it_works.md`. Lidos por índice: `docs/gotchas.md`
(56 entradas), `docs/safety.md` (9 invariantes). Conferido no código: os dois endpoints
(`tools/claude-swap.py:87` e `:293`).

## O que é

Ferramentas de linha de comando para quem usa Claude Code com mais de uma assinatura: um
painel com o uso de cada conta (janela de 5 h, semanal e semanal por modelo), uma previsão
de quando a cota acaba, e a troca de **todas** as sessões em curso para outra conta. Um vigia
em `launchd` avisa perto do limite e, se armado, troca **uma** vez sozinho.

## Instalar: nao instala

Reprova na **pergunta 4**, por código: o repositório inteiro depende do chaveiro do macOS
(`security`), de `launchd` e de `open`, e o README declara "macOS only". No Windows o
Claude Code não usa chaveiro: a credencial mora em `<config dir>/.credentials.json`.

## Enxertar: enxerta

O valor está no conhecimento medido, não no código. Cinco peças valem para o nosso fluxo:

1. **Um login mora em exatamente um lugar e nunca é copiado.** O refresh token é de uso
   único, e a trava de renovação é por pasta de configuração. Login copiado para duas pastas
   é renovado pelas duas sem trava comum: a primeira gasta o token e a outra cai. Incidente
   deles em 2026-08-04: sete sessões perderam o login em três minutos (gotcha #1, design v1).
   **É o risco direto do nosso desenho**: copiar o `.credentials.json` da conta pessoal para
   `~/.claude` derruba as duas.
2. **Dois logins separados da mesma conta coexistem.** Entrar duas vezes gera pares
   independentes (o "seal test", 2026-08-17). Daí o desenho padrão deles: cada conta mantém o
   próprio login fixo (âncora), e a troca é um login novo na pasta que as sessões leem.
3. **A identidade se pergunta ao servidor**, nunca ao `.claude.json` em cache: `GET
   /api/oauth/profile` com o token. O cache divergiu do token e fez a versão 2 deles gravar o
   login de uma conta por cima de outra (2026-08-05).
4. **Uso ao vivo vem de `GET /api/oauth/usage`, com limite de taxa por conta.** Responde 429
   quando várias fontes consultam juntas. Eles passam tudo por um cache único, com reuso de
   4 min (1 min acima de 85%) e espera de 3 min após um 429. O cache do `.claude.json` é
   gravado no máximo a cada 5 min e não serve para decidir.
5. **Troca automática é de disparo único e se desarma antes de trocar**, para que uma falha
   no meio nunca vire uma cadeia de trocas. Antes de mover, os dois logins precisam de pelo
   menos 30 min de vida, para nenhum processo renovar no meio do movimento.

Fato do Claude Code que eles mediram e que bate com o nosso (2.1.287): sessão rodando passa
para o login novo em cerca de um minuto; sessão parada por limite passa na próxima mensagem.

## O que não se aplica

- O desenho deles assume **uma pasta compartilhada** ("fleet") que todas as sessões leem. Aqui
  as duas pastas existem de propósito: `~/.claude` (trabalho, plugins da org) e
  `~/.claude-personal` (pessoal). A troca, então, não é "mudar a frota de conta": é pôr a
  assinatura de uma pasta para atender as sessões da outra.
- Medido nesta máquina: `~/.claude` é assinatura `team` (organização) e `~/.claude-personal` é
  `max`, as duas no tier `default_claude_max_5x`. Trocar entre elas mistura conta de
  organização com conta pessoal, e isso é decisão do Luís, não do desenho.

## Pergunta 6

Criado hoje, um autor, quatro estrelas. A documentação é madura (56 gotchas datados, design
history com quatro desenhos abandonados), o que indica uso real anterior à publicação.
