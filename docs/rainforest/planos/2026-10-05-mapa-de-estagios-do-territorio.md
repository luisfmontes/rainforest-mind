# Plano: Contrato do mapa de estágios do território

Design: docs/rainforest/design/2026-10-05-mapa-de-estagios-do-territorio.md

## O que não pode quebrar

- Repositório sem território nenhum: as quatro skills ligadas se comportam exatamente como hoje. O `territorio.cjs estagio <nome>` imprime `sem territorio` e sai 0, e o `marcar` não exige nada a mais.
- Nenhum caminho de máquina, nome de empregador, cliente ou linguagem específica entra neste repositório (D7 do design de 2026-08-28). O território sintético dos testes é inventado.
- As baterias existentes (`scripts/testa-estado.sh`, `scripts/testa-conferir-fluxo.sh`, `node scripts/conferir-invariantes.cjs`) continuam verdes.

## Formato do manifesto (referência para as tarefas 1 a 3)

`territorio.json`, na raiz do plugin de território:

    {
      "versao_contrato": 0,
      "nome": "<nome>",
      "deteccao": { "extensoes": [".abc"], "arquivos": [] },
      "variaveis": ["lint"],
      "estagios": {
        "brainstorm": { "mcp": [{ "tool": "mcp__<srv>__<tool>", "quem": "orquestrador", "obrigatorio": false }],
                        "skills": ["<plugin>:<skill>"] },
        "executar":   { "modo": "substitui", "agentes": [{ "tipo": "<plugin>:<agente>", "mcp": "orquestrador", "obrigatorio": false }] },
        "revisar":    { "modo": "soma",      "agentes": [{ "tipo": "<plugin>:<revisor>", "obrigatorio": false }] },
        "verificar":  { "comandos": [{ "id": "lint", "comando": "{lint} {arquivo}", "obrigatorio": true }] }
      }
    }

Config local por máquina: `~/.rainforest/territorios/<nome>.json` = `{ "lint": "<caminho>" }`.
Apontamento do repositório: `.rainforest/territorio`, uma linha com o `nome`.

## Tarefas

### 1. `territorio.cjs`: descoberta e bloco do estágio [tipo: implementar]
atende: D1, D2, D3, D4, D8, D10
arquivos: `scripts/territorio.cjs`, `scripts/testa-territorio.sh`, `test/fixtures/territorio/sintetico/territorio.json`, `test/fixtures/territorio/sintetico/.claude-plugin/plugin.json`, `test/fixtures/territorio/repo-abc/x.abc`, `test/fixtures/territorio/repo-vazio/LEIAME.txt`
depende de: nenhuma
paralela: sim
prova: `bash scripts/testa-territorio.sh`
mutacao:
  arquivo: `scripts/territorio.cjs`
  de: `if (apontado) return candidatos.find((t) => t.manifesto.nome === apontado) || null;`
  para: `if (false) return candidatos.find((t) => t.manifesto.nome === apontado) || null;`
  bateria: `bash scripts/testa-territorio.sh`
  fixture: `testa-territorio.sh, caso "apontamento do repo vence a deteccao"`
pronto quando: com o `installed_plugins.json` de um config dir de teste apontando um plugin cuja raiz tem o `territorio.json` sintético, rodar `node scripts/territorio.cjs estagio revisar` dentro de `test/fixtures/territorio/repo-abc` imprime o `modo: soma` e o `tipo` do agente declarado. Dentro de `repo-vazio`, imprime `sem territorio` e sai 0. Com `.rainforest/territorio` apontando um nome inexistente, sai 2 nomeando o nome. Manifesto com `versao_contrato` diferente de 0 sai 2. A linha de cada MCP mostra `quem: orquestrador` quando o campo é omitido. Tudo provado por `bash scripts/testa-territorio.sh`, que monta o próprio config dir temporário (zero casos pulados).

### 2. `territorio.cjs`: variáveis do config local e itens indisponíveis [tipo: implementar]
atende: D5, D6, D7
arquivos: `scripts/territorio.cjs`, `scripts/testa-territorio.sh`
depende de: 1
paralela: nao
prova: `bash scripts/testa-territorio.sh`
mutacao:
  arquivo: `scripts/territorio.cjs`
  de: `if (faltando.length) { console.error(\`variavel sem valor em ${arquivoLocal}: ${faltando.join(', ')}\`); process.exit(3); }`
  para: `if (false) { console.error(\`variavel sem valor em ${arquivoLocal}: ${faltando.join(', ')}\`); process.exit(3); }`
  bateria: `bash scripts/testa-territorio.sh`
  fixture: `testa-territorio.sh, caso "variavel sem valor no config local sai 3 nomeando a variavel"`
pronto quando: com `HOME` de teste contendo `.rainforest/territorios/sintetico.json` = `{"lint":"/bin/true"}`, `node scripts/territorio.cjs estagio verificar --arquivo x.abc` imprime o comando resolvido `/bin/true x.abc`. Sem a chave `lint`, sai 3 com stderr contendo `lint` e o caminho do config local. Agente opcional cujo plugin não está no `installed_plugins.json` sai do bloco com uma linha `aviso: <tipo> indisponivel, papel padrao do rainforest` e exit 0. Comando obrigatório com variável faltando nunca sai 0. Tudo provado por `bash scripts/testa-territorio.sh`.

### 3. `estado.cjs`: rastro do território e recusa de obrigatório sem evidência [tipo: implementar]
atende: D9
arquivos: `scripts/estado.cjs`, `scripts/testa-estado-territorio.sh`, `scripts/territorio.cjs`
desvio (2026-10-05, na integracao da tarefa 2): `territorio.cjs` ganha `--json` com os itens do estagio sem resolver variaveis, para o `estado.cjs` ler os obrigatorios por interface estavel em vez de raspar o texto impresso
depende de: 2
paralela: nao
prova: `bash scripts/testa-estado-territorio.sh`
mutacao:
  arquivo: `scripts/estado.cjs`
  de: `if (obrigatoriosSemEvidencia.length) { console.error(\`RECUSADO: item obrigatorio do territorio sem evidencia: ${obrigatoriosSemEvidencia.join(', ')}\`); process.exit(2); }`
  para: `if (false) { console.error(\`RECUSADO: item obrigatorio do territorio sem evidencia: ${obrigatoriosSemEvidencia.join(', ')}\`); process.exit(2); }`
  bateria: `bash scripts/testa-estado-territorio.sh`
  fixture: `testa-estado-territorio.sh, caso "verificar sem evidencia do comando obrigatorio recusa com exit 2"`
pronto quando: num repositório de teste com o território sintético resolvido, `node scripts/estado.cjs marcar --estagio verificar --status ok --json '{...sem campo territorio...}'` sai 2 e nomeia o `id` `lint`. O mesmo `marcar` com `"territorio":{"comandos":[{"id":"lint","comando":"...","saida":"...","exit":0}]}` passa. O campo `territorio` fica gravado no JSON de estado do estágio. Um item opcional sem evidência só gera aviso em stderr e exit 0. Num repositório sem território, o `marcar` se comporta byte a byte como antes (a bateria compara a saída dos dois). Tudo provado por `bash scripts/testa-estado-territorio.sh`.

### 4. Ligar as quatro skills ao mapa [tipo: docs]
atende: D2, D4, D8, D12
arquivos: `skills/brainstorm/SKILL.md`, `skills/executar/SKILL.md`, `skills/revisar/SKILL.md`, `skills/verificar/SKILL.md`, `skills/executar/invariantes.json`, `skills/revisar/invariantes.json`, `skills/verificar/invariantes.json`, `skills/brainstorm/invariantes.json`
depende de: 3
paralela: nao
mutacao: n/a
  motivo: texto de skill não tem comportamento executável a inverter; a falsificação é a coerência com o design, conferida pelo sensor de invariantes e pela leitura abaixo
pronto quando: cada uma das quatro skills manda rodar `node scripts/territorio.cjs estagio <o nome dela>` na abertura e diz o que fazer com cada parte do bloco, coerente com o design. O brainstorm consulta as tools com `quem: orquestrador` (D8). O executar despacha o agente declarado no lugar do executor quando `modo: substitui`, mantendo `isolation: "worktree"` e o briefing com o resultado do MCP (D4, D8). O revisar despacha os revisores declarados em paralelo ao próprio quando `modo: soma` (D4). O verificar roda os comandos do bloco e fecha com o campo `territorio` no `--json` (D9). Cada skill tem a frase correspondente em `invariantes.json`. Provado por `node scripts/conferir-invariantes.cjs` saindo 0 com as frases novas e saindo ≠ 0 quando uma delas é apagada do SKILL.md (o executor cola as duas saídas).

### 5. Documento do contrato e protocolo de aceite [tipo: docs]
atende: D10, D11, D13
arquivos: `docs/rainforest/referencia/contrato-territorio.md`, `CHANGELOG.md`
depende de: 4
paralela: nao
mutacao: n/a
  motivo: documento de referência sem comportamento executável
pronto quando: o documento descreve o formato do manifesto exatamente como o `territorio.cjs` o lê. Todo campo citado no doc aparece no `test/fixtures/territorio/sintetico/territorio.json`, e todo campo do fixture aparece no doc, conferido por `node -e` que lista as chaves dos dois e sai ≠ 0 em qualquer diferença (o executor cola o comando e a saída). Declara `versao_contrato: 0` e a condição de promoção a v1 (D10). Traz o protocolo da 3ª rodada do benchmark com os três critérios do D11, em números: agentes declarados despachados no transcript, qualidade no júri cego não cai, custo ≤ +30%. Diz que o mapa do território real mora no plugin dele (D13). O `CHANGELOG.md` ganha a entrada da versão.
