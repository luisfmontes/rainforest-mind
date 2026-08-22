---
description: Saúde do rainforest — o que os checadores oficiais do Claude Code não sabem, e ponteiro para eles
---

Rode `node scripts/saude.cjs` e apresente o resultado.

O que ele checa, e por quê cada um está aqui: **de quem é a raiz de dados** (quem
instala e não configura recebe o foco e as ideias de quem publicou o plugin), a
**margem do orçamento de injeção** (sem margem, prazo e marco caem fora da
abertura em silêncio), a **integridade do `ideias.jsonl`**, **trabalho do fluxo
parado no meio**, **worktree de agente pendurado**, e se o **plugin instalado
está atrás do repo** — em 2026-08-11 esteve 18 commits atrás, e sete skills
escritas naquele dia não valiam em sessão nova.

Uma checagem responde a uma pergunta diferente das outras e por isso se comporta
diferente: **contas do harness em versões diferentes do mesmo plugin**. Todas as
outras falam da sessão em que você está, e obedecem o `CLAUDE_CONFIG_DIR` — que
é uma declaração, "a config é esta". Essa é de **inventário** ("as contas desta
máquina batem?"), declaração de sessão não a responde, e por isso ela varre a
home inteira. Fica **calada quando batem** — dizer "estão iguais" é inventário
364 dias por ano, e o evento é a divergência — e é `aviso`, nunca alerta, porque
divergir às vezes é escolha. Nasceu em 2026-08-20: depois de quatro PRs e de um
`claude plugin update`, o perfil pessoal estava em 0.71.0 e o de trabalho em
0.70.0, e o painel dizia `ok`.

Nada aqui roda bateria de teste. Comando que demora vira comando que ninguém
chama. Quando algo cheirar mal, ele diz qual bateria rodar.

**O que este comando NÃO faz, de propósito:** saúde de instalação e custo de
token já têm dono oficial, e duplicá-los é custo sem retorno.

| Para quê | Comando |
|---|---|
| Instalação: PATH, duplicata, atualização, settings inválidas | `claude doctor` (ou `/doctor` numa sessão, que também conserta) |
| Inventário de componentes e custo de token do plugin | `claude plugin details rainforest-mind` |
| O que criar de automação **neste projeto** | skill `claude-automation-recommender` (plugin oficial `claude-code-setup`) |

Havendo **ALERTA**, trate como trabalho, não como recado: diga o que fazer e
ofereça fazer. Só avisos, relate em uma linha e siga o que estava fazendo.
