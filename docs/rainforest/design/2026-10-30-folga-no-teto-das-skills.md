# Folga no teto de 16 KB das skills regua, executar, fechar e plano

## Objetivo
`scripts/testa-teto-skills.sh` reprova `SKILL.md` acima de 16.384 bytes. Medido em 2026-10-30 na `main` (`6169212f`), quatro skills estão encostadas nele: `regua` com 2 bytes de folga, `executar` com 3, `fechar` com 8 e `plano` com 14. Qualquer correção nelas reprova no teto, e nos dois fluxos de 2026-10-29 o texto novo do `plano` teve de ser espremido para caber; o revisor do fluxo colheita-coordenacao-e-gates registrou o risco. Este trabalho abre pelo menos 1.000 bytes de folga em cada uma, movendo para `references/` da própria skill um bloco autocontido, sem reescrever o texto movido.

Conduzido pela sessão em 2026-10-30, sob a autorização permanente de seguir o fluxo com a recomendada. As decisões ficam marcadas no PR para veto.

## Decisões fechadas
- **D1 — `regua`: a seção "O que falsificaria esta skill" vai para `skills/regua/references/o-que-falsificaria.md`** — 2.850 bytes. — porquê: é o maior bloco autocontido, é leitura de quem audita a skill e não de quem a executa, e não contém frase de `invariantes.json` (a `regua` não tem o arquivo).
- **D2 — `executar`: a tabela de saídas da catraca e o que vem depois dela até "## Fechamento" vão para `skills/executar/references/catraca-de-mutacao.md`** — 1.839 bytes. — porquê: é a consulta de quem já rodou o `conferir-mutacao.cjs` e quer ler o exit; o parágrafo que manda rodar a catraca, com o comando, fica na skill. Nenhuma das quatro frases de `skills/executar/invariantes.json` está no bloco, e o caso 8 de `hooks/testa-portaria-manifesto.cjs` lê o bloco `Sensor:`, que fica.
- **D3 — `fechar`: a seção "Conferir de fora se o fluxo fechou: `concluido`" vai para `skills/fechar/references/concluido.md`** — 1.640 bytes. — porquê: é uso fora do fluxo (quem confere depois), não passo do `fechar`. O bloco não tem frase de `skills/fechar/invariantes.json`, nem o "O GitHub reconhece" e o "`acao` é o que" que `scripts/testa-fechar-destino.sh` lê.
- **D4 — `plano`: o relato do incidente de 2026-08-19 da seção "`pronto quando:` nomeia a ENTRADA REAL" vai para `skills/plano/references/incidente-pronto-quando.md`** — 1.102 bytes. — porquê: é o porquê histórico, não instrução; a regra e a forma do critério ficam na skill. A frase de `skills/plano/invariantes.json` ("`bash <bateria>` sai 0\" não é critério de pronto") fica onde está.
- **D5 — Mover sem reescrever, com uma linha de ponteiro** — o bloco sai byte a byte para o arquivo novo, que ganha só um título e uma linha dizendo de qual skill e seção veio. No lugar, uma linha diz o que o arquivo tem e quando lê-lo. — porquê: mover é a mudança que não altera instrução; reescrever no mesmo passo misturaria duas revisões.
- **D6 — Âncoras binárias do pacote Codex re-medidas** — `fechar` e `regua` têm âncora de corpo em `scripts/contrato-plugin-codex.cjs`; as duas são re-medidas com o comentário de por quê, como nos re-medições anteriores. — porquê: a âncora existe para pegar mudança acidental; esta é deliberada.
- **D7 — Contra quem protege, e o que fica fora** — protege contra a próxima correção numa das quatro skills reprovar no teto por poucos bytes, e contra texto novo espremido para caber. Não muda o teto, nem as skills com folga maior (`revisar` tem 514 bytes e fica para quando encostar). Não conserta o hábito de crescer: a bateria continua sendo o freio.
- **D8 — Versão 2.2.2** — PATCH, com CHANGELOG e bump nos dois `plugin.json` e no badge do README. — porquê: só move texto entre arquivos da mesma skill; nenhum contrato muda (tabela do `CONTRIBUTING.md`).

## Avaliado e descartado
- **Subir o teto** — o teto mede o contexto que a skill ocupa quando carrega; subir troca o sintoma por custo em toda sessão que a carrega.
- **Encurtar o texto das quatro skills** — é revisão de conteúdo, uma por skill, com risco de perder instrução; mover o bloco autocontido dá a folga sem tocar no que a skill manda.
- **Uma bateria de folga mínima (falhar abaixo de N bytes)** — só desloca o penhasco para N; o que falta é folga agora, não um segundo limite.

## Fora de escopo
- `revisar` (514 bytes de folga) e as demais skills.
- Conteúdo dos blocos movidos: qualquer correção neles fica para outro trabalho.

## Varredura
docs/rainforest/varredura/2026-10-30-folga-no-teto-das-skills.txt — nenhuma Issue aberta nos termos.

## Em aberto
nada
