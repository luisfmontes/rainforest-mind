# Critério — fluxo 13, parte 1: a Fase 0 e o selo

O diff altera `skills/regua/SKILL.md`. Julgue **só** se as quatro afirmações
abaixo são verdadeiras sobre o texto que o diff deixa no arquivo. Cada uma é
falsificável: se o texto disser o contrário, ou não disser nada, a afirmação é
falsa. Responda `concordo` só se as quatro forem verdadeiras; qualquer uma falsa
→ `discordo`, nomeando o número.

1. **O manifesto é um arquivo só.** `docs/rainforest/reguas/<slug>.md` carrega as
   três coisas: qual é a régua, os mecanismos, e uma seção `## Freios` com o teto
   de rodadas. O texto diz que o teto mora no arquivo, e não na conversa — e dá o
   motivo (o que não está em disco não chega no agente novo de cada rodada).

2. **A leitura e a checagem são o mesmo caminho.** O texto prescreve que o crítico
   recebe o manifesto pela saída de `node scripts/conferir-regua.cjs mostrar
   --slug <slug>`, e afirma explicitamente que esse é o **único** caminho que
   imprime o manifesto, porque não pode existir o caminho "pegou o conteúdo sem
   conferir". Texto que mande o crítico ler o arquivo direto, ou fazer `git show`
   por conta, reprova esta afirmação.

3. **O limite está declarado, não escondido.** O texto diz que o topo continua
   procedural — a sessão que orquestra precisa chamar o comando certo — porque
   quem orquestra é um LLM, e que o ganho é sobrar **um** ponto onde burlar em vez
   de um por rodada e por crítico. Texto que prometa impossibilidade de burla
   reprova.

4. **A atribuição nomeia três fontes.** O rodapé credita `robonuggets/gauntlet-loop`
   e a skill `design-loop` (como já fazia) e acrescenta `karpathy/autoresearch`,
   dizendo o que dele veio e o que dele ficou de fora, e que foi reimplementado a
   partir da descrição, sem copiar arquivo.
