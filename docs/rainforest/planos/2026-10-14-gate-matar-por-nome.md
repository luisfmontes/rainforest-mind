# Plano: Gate: barrar matar processo por nome (#517)

Design: docs/rainforest/design/2026-10-14-gate-matar-por-nome.md

## O que não pode quebrar
- Matar por PID continua livre, na janela e no subagente (D3).
- Comando de consulta que só lista processo (`Get-Process node`, `pgrep -a x`, `tasklist /FI ...`) e texto que só cita a forma proibida (`echo "pkill x"`, `grep -rn "taskkill /IM" hooks`, `git commit -m "barra pkill"`) passam.
- Os gates irmãos do grupo `Bash|PowerShell` em `hooks/hooks.json` seguem registrados e na mesma ordem; o novo entra no fim do grupo.
- Payload ilegível, vazio ou de outra ferramenta sai 0, como os irmãos.

## Regra de parada
O gate reimplementa um pedaço da gramática de shell. O conjunto coberto é a lista do D2, e nada além. Falso negativo fora dessa lista (wmic, CIM, script, PID por arquivo) é o "fora" declarado, não defeito. Falso positivo ou negativo novo que não caiba no parser compartilhado (`segmentosParaGate`, `posicaoDeComando`, `desempacotarWrapperDeString`) volta para o `brainstorm` em vez de ganhar um parser próprio.

## Tarefas

### 1. Gate matar-por-nome, bateria, registro e toggle [tipo: implementar]
atende: D1, D2, D3, D4, D5, D6
arquivos: `hooks/gate-matar-por-nome.cjs`, `hooks/testa-gate-matar-por-nome.cjs`, `hooks/hooks.json`, `hooks/lib/config.cjs`, `scripts/baterias-obrigatorias.txt`, `scripts/testa-conferir-categoria.sh`, `hooks/testa-titulo-sessao-registro.sh`
depende de: nenhuma
prova: `node hooks/testa-gate-matar-por-nome.cjs`
mutacao:
  arquivo: `hooks/gate-matar-por-nome.cjs`
  de: if (forma) bloqueia(
  para: if (false) bloqueia(
  bateria: `node hooks/testa-gate-matar-por-nome.cjs`
  fixture: testa-gate-matar-por-nome.cjs, os casos "contorno:" (toda forma por nome do D2 tem de sair 2)
pronto quando: com o payload real de PreToolUse do harness (`hooks/fixtures/busca-raiz/payload-bash-subagente.json`, só `tool_input.command` trocado; janela = mesmo payload sem `agent_id`/`agent_type`), o hook sai 2 com stderr citando o PID como saída honesta para cada contorno, e 0 para cada vizinho legítimo, provado por `node hooks/testa-gate-matar-por-nome.cjs` com zero FALHA e por `node -e "const p=require('./hooks/fixtures/busca-raiz/payload-bash-subagente.json');p.tool_input={command:'taskkill /IM python.exe /F'};process.stdout.write(JSON.stringify(p))" | node hooks/gate-matar-por-nome.cjs; echo exit=$?`, que imprime `exit=2`.

Forma do código (o alvo de mutação é código a nascer): a decisão mora numa função `formaPorNome(comando)` que devolve o nome da forma casada ou `null`, e desce em `bash -c`, `eval`, `pwsh -Command` (inclusive com flags antes do `-Command`), `sudo`/`env`/`FOO=1` reaproveitando `segmentosParaGate` (de `gate-subagente-sem-gh.cjs`) e `hooks/lib/tokens-comando.cjs`, sem parser novo. O `main` tem exatamente uma linha `if (forma) bloqueia(...)` depois de `const forma = formaPorNome(comando);`. Pipeline (`a | b`) é olhado como um todo, porque `Get-Process x | Stop-Process` e `pgrep x | xargs kill` só são "por nome" juntos. Nenhum caso de teste pode ler o texto do fonte.

Contornos (cada um sai 2, no subagente E na janela; os de PowerShell também com `tool_name: "PowerShell"`):
- `taskkill /IM python.exe /F`, `taskkill /F /IM node.exe`, `TASKKILL.EXE /im node.exe`, `taskkill -im node.exe`, `taskkill /FI "IMAGENAME eq python.exe" /F`
- `pkill node`, `pkill -f python`, `pkill -9 -f "node server"`, `killall node`, `sudo pkill x`, `FOO=1 killall x`, `bash -c "pkill node"`, `sh -c 'killall node'`
- `Stop-Process -Name python`, `Stop-Process -Name python -Force`, `Stop-Process -ProcessName node`, `spps -Name node`, `kill -Name node`, `Stop-Process node` (nome posicional não numérico)
- `Get-Process python | Stop-Process`, `Get-Process -Name node | Stop-Process -Force`, `gps node | spps`, `ps node | kill`, `Get-Process | Where-Object { $_.Name -eq 'node' } | Stop-Process`
- `kill $(pgrep python)`, `kill -9 $(pidof node)`, `` kill `pgrep node` ``, `pgrep python | xargs kill`, `pidof node | xargs kill -9`
- `pwsh -NoProfile -Command "Stop-Process -Name node"`, `powershell -Command "Get-Process node | Stop-Process"`

Vizinhos legítimos (cada um sai 0, no subagente e na janela):
- `taskkill /PID 1234 /F`, `taskkill /F /T /PID 1234`, `kill 1234`, `kill -9 1234`, `kill -TERM 1234 5678`, `Stop-Process -Id 1234`, `Stop-Process -Id 1234 -Force`, `Stop-Process 1234`, `Get-Process -Id 1234 | Stop-Process`
- `Get-Process node`, `pgrep -a python`, `pidof node`, `tasklist /FI "IMAGENAME eq python.exe"`, `ps aux | grep python`
- `echo "pkill node"`, `grep -rn "taskkill /IM" hooks`, `git commit -m "barra pkill e killall"`, `cat notas.txt | grep Stop-Process`

Saídas (D4):
- config do projeto com `matar-por-nome: false`: o contorno `pkill node` sai 0, no subagente e na janela.
- janela com `RAINFOREST_GATE_OFF=1` no ambiente: `pkill node` sai 0.
- subagente com `RAINFOREST_GATE_OFF=1`: `pkill node` sai 2.
- payload vazio, JSON inválido, `tool_name: "Read"`: saem 0.

Mensagem (D5): stderr do bloqueio contém o comando visto, uma forma de listar (`tasklist`/`Get-Process`/`pgrep -a`) e a instrução de matar pelo PID; só a da janela cita `RAINFOREST_GATE_OFF`.

Emenda 2026-10-14, volta 2 do revisar: o hook novo leva `// @categoria: guia`, e `scripts/testa-conferir-categoria.sh` fixa a contagem de peças (58; guia/sensor/dado = 24/31/3). A contagem passa a 59 e 25/31/3, com a linha de histórico no cabeçalho dela; por isso o arquivo entrou em `arquivos:`.

Emenda 2026-10-14, volta 4 (rodada extra liberada pelo Luís): `hooks/testa-titulo-sessao-registro.sh` fixa a contagem de hooks por evento do `hooks/hooks.json` (`"PreToolUse":17`), e o gate novo leva para 18. A contagem passa a 18, com a linha de histórico no cabeçalho dela; por isso o arquivo entrou em `arquivos:`. A varredura completa (`bash scripts/varrer-baterias.sh`) no HEAD 04caf2b7 deu 252 verdes e só essa vermelha.

Registro: entrada nova no grupo `"matcher": "Bash|PowerShell"` de `hooks/hooks.json`; chave `matar-por-nome` (boolean, padrão `true`) em `hooks/lib/config.cjs`; `hooks/testa-gate-matar-por-nome.cjs` na seção de gates de `scripts/baterias-obrigatorias.txt`.

### 2. README, CHANGELOG e versão 1.67.0 [tipo: docs]
atende: D1, D4
arquivos: `README.md`, `CHANGELOG.md`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`
depende de: 1
mutacao: n/a
  motivo: tarefa de documentação e número de versão; não há comportamento a inverter
pronto quando: com o gate da tarefa 1 já no repo, a linha nova da tabela de gates do README e a entrada `## 1.67.0 — 2026-10-14` do CHANGELOG descrevem o mesmo contrato do design (vale na janela e no subagente; PID passa; toggle `matar-por-nome`; `RAINFOREST_GATE_OFF` só na janela; porta fora), a chave citada é a mesma que `hooks/lib/config.cjs` exporta, e as duas `plugin.json` e o selo do README dizem 1.67.0, provado por `node -e "const c=require('./hooks/lib/config.cjs');const fs=require('fs');const r=fs.readFileSync('README.md','utf8');const v=[require('./.claude-plugin/plugin.json').version,require('./.codex-plugin/plugin.json').version];const linha=r.split('\n').find(l=>l.includes('gate-matar-por-nome.cjs'))||'';const ok=JSON.stringify(c).includes('matar-por-nome')||fs.readFileSync('hooks/lib/config.cjs','utf8').includes(\"'matar-por-nome'\");console.log(v.join(','),r.includes('vers%C3%A3o-1.67.0'),linha.includes('matar-por-nome'),linha.includes('PID'),ok)"` imprimindo `1.67.0,1.67.0 true true true true`, e por leitura do revisor confrontando a linha e a entrada do CHANGELOG com D1–D5.
