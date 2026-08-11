---
description: Saúde do rainforest — o que os checadores oficiais do Claude Code não sabem, e ponteiro para eles
---

Rode `node scripts/saude.cjs` e apresente o resultado.

O que ele checa, e por quê cada um está aqui: **de quem é a raiz de dados** (quem
instala e não configura recebe o foco e as ideias de quem publicou o plugin), a
**margem do orçamento de injeção** (sem margem, prazo e marco caem fora da
abertura em silêncio), a **integridade do `ideias.jsonl`**, **trabalho da esteira
parado no meio**, **worktree de agente pendurado**, e se o **plugin instalado
está atrás do repo** — em 2026-08-11 esteve 18 commits atrás, e sete skills
escritas naquele dia não valiam em sessão nova.

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
