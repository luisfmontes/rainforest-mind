# Sinal de utilidade no ranking da memória

## Objetivo
Medir, por duas semanas e sem mudar a seleção, se a memória injetada na abertura
foi usada na sessão — e se a recência deixa de fora observação que teria sido
útil. O resultado decide, por régua fixada aqui, se o ranking passa a usar o sinal.

## Decisões fechadas
- **D1 — Sinal = casamento com o que a sessão fez; servida é o denominador** — porquê: "servida" sozinha (o que o `rohitg00/agentmemory` faz em `access-tracker.ts:53-83`) só reforça a recência que já decide as 14 vagas; o `buscar` explícito, que seria o sinal de puxada, aparece 2 vezes em todos os transcripts das duas contas; marcação pelo modelo custa injeção fixa e depende de ele lembrar.
- **D2 — Primeira entrega só mede, duas semanas, sem mexer no ranking** — porquê: o design `2026-09-16-memoria-reconciliacao-e-consolidacao` marcou retomar duas semanas depois da reconciliação rodar (roda desde ~18/09); a janela vira período de medição em vez de trava, e descobre antes de mexer se a recência já acerta.
- **D3 — Escopo: só a seleção do SessionStart** — porquê: `buscar` quase não roda; eviction é outro design e a consolidação já cuida dela.
- **D4 — Texto comparado = entradas de ferramenta + prompts do usuário, excluindo o bloco injetado** — porquê: a prosa do assistente ecoa a injeção e marcaria como usada toda observação só parafraseada.
- **D5 — Grava nota crua, não binário** — porquê: a nota é a fração dos termos raros (IDF alto no `observacoes_fts`) da observação presentes no texto da sessão; o corte de "usou" não tem como ser calibrado antes dos dados.
- **D6 — Pontua também o contrafactual** — porquê: além das servidas, as 14 que o FTS acha a partir do texto da sessão; sem isso o relatório não responde se a recência perdeu algo útil.
- **D7 — Pontuação roda na manutenção da abertura seguinte** — porquê: SessionEnd tem orçamento curto e pode ser morto; a marca d'água do `memoria-marca.cjs` (sessão, transcrito, offset) já dá o transcrito e a recuperação de sessão caída.
- **D8 — "Servida" = só o que chegou à sessão, depois do corte de orçamento** — porquê: o `memoria-session-start.cjs` corta parte das 14 no teto de bytes; gravar as candidatas mediria o que o modelo nunca viu.
- **D9 — Régua de decisão, fixada antes dos dados: liga o ranking se em ≥ 1/3 das sessões alguma não-servida pontua acima da melhor servida** — porquê: régua escrita depois dos dados vira ajuste ao que apareceu; abaixo disso a ideia fecha com o achado "recência basta".
- **D10 — Grava só id da observação, id da sessão, servida/não, nota e data — nenhum texto** — porquê: a nota se recalcula do transcrito; guardar trecho duplica dado pessoal sem ganho.
- **D11 — Relatório por comando sob demanda (`memoria.cjs utilidade --relatorio`) + ideia com gancho em 2026-10-07** — porquê: vigia novo é custo permanente para uma medição de uma vez.

## Avaliado e descartado
- Sinal "servida" como numerador (agentmemory): mede recência, não utilidade — a seleção atual já é recência.
- Sinal "puxada pelo `buscar`": 2 chamadas reais em todos os transcripts das duas contas em 2026-09-23 (as demais menções são o texto de dica injetado pela abertura).
- Comparar com a prosa do assistente: ecoa a injeção (D4).

## Fora de escopo
- Mudar a seleção das 14 vagas — só depois do relatório e da régua D9.
- Fórmula de pontuação para o ranking vivo (decaimento + reforço do agentmemory `retention.ts:88-94`, espaçamento do MemPalace `dynamics.py`) — entra no design seguinte, se D9 passar.
- `buscar` e eviction (D3).
- Encurtar observação antes de cortar (ideia `memoria-encurta-antes-de-cortar-e-superada-sai-primeiro`).

## Em aberto
