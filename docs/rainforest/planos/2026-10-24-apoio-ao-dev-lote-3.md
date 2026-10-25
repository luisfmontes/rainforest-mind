# Plano: Apoio ao dev, lote 3

Design: docs/rainforest/design/2026-10-24-apoio-ao-dev-lote-3.md

## O que não pode quebrar
- `conferir-entrega.cjs` continua avisando (sem reprovar) as vizinhas de arquivo fora do escopo, com o mesmo texto `vizinhas de <arquivo>: ...` (D25, #400).
- `conferir-ancoras.cjs` continua aceitando mapa sem `## Regras implícitas`, e mapa com regra no formato antigo não passa a sair 1; os casos de `scripts/testa-conferir-ancoras.sh` seguem verdes.
- Nenhum hook PostToolUse existente muda de comportamento; o hook novo nunca devolve `decision` e nunca sai ≠ 0.
- `skills/executar/SKILL.md` (16.373 B) e `skills/plano/SKILL.md` (15.829 B) ficam abaixo do teto de 16.384 B (`scripts/testa-teto-skills.sh`).
- Nenhuma bateria existente fica vermelha (`scripts/testa-conferir-entrega.sh`, `scripts/testa-conferir-ancoras.sh`, `scripts/testa-conferir-categoria.sh`, `scripts/testa-conferir-setup.sh`, `scripts/testa-teto-skills.sh`).

## Tarefas

### 1. Baterias pelo diff [tipo: implementar]
atende: D1, D2, D3
arquivos: `scripts/lib/baterias-vizinhas.cjs`, `scripts/baterias-do-diff.cjs`, `scripts/conferir-entrega.cjs`, `skills/executar/SKILL.md`, `skills/verificar/SKILL.md`, `scripts/testa-baterias-do-diff.sh`, `scripts/testa-integrar-tarefa.sh`
depende de: nenhuma
busca:
- repo | grep -n "testa-" scripts/conferir-entrega.cjs | D25 em conferir-entrega.cjs:576-596 já acha bateria que cita o nome-base, só como aviso e só para arquivo fora do escopo
- livro | codebase-memory test_impact_engine.h | seleção de teste por impacto, com volta para tudo quando a evidência é incerta
desfecho: estender
prova: `bash scripts/testa-baterias-do-diff.sh`
mutacao:
  arquivo: `scripts/baterias-do-diff.cjs`
  de: if (citam.length === 0) duvidas.push({ arquivo, motivo: 'nenhuma bateria cita' });
  para: if (false) duvidas.push({ arquivo, motivo: 'nenhuma bateria cita' });
  bateria: `bash scripts/testa-baterias-do-diff.sh`
  fixture: testa-baterias-do-diff.sh, caso "arquivo que nenhuma bateria cita sai rodar tudo com exit 3"
pronto quando: num repo git temporário montado pela bateria, com `scripts/a.cjs`, `scripts/testa-a.sh` (cita `a.cjs`), `scripts/b.cjs` (nenhuma bateria cita) e `hooks/lib/c.cjs` citado por `hooks/testa-c.sh`: alterar só `a.cjs` entre base e head faz `node scripts/baterias-do-diff.cjs --base <base> --raiz <repo>` sair 0 com `scripts/testa-a.sh` numa linha; alterar `b.cjs` sai 3 com `rodar tudo: scripts/b.cjs — nenhuma bateria cita`; alterar `hooks/lib/c.cjs` sai 3 com motivo de biblioteca compartilhada mesmo com `testa-c.sh` citando; alterar a própria `testa-a.sh` lista ela; `.md` ou arquivo sob `docs/` alterado não gera dúvida, mas lista a bateria que cita o nome-base dele (ex.: `skills/x/SKILL.md` citado por `scripts/testa-teto.sh`); bateria apagada entre base e head não é listada; arquivo com acento no caminho sai legível (`git -c core.quotePath=false`, `-z`); `conferir-entrega.cjs` passa a usar a mesma função de `scripts/lib/baterias-vizinhas.cjs` e `scripts/testa-conferir-entrega.sh` segue verde — provado por `bash scripts/testa-baterias-do-diff.sh`. A forma da regra de dúvida é a linha do `de:`. `skills/verificar/SKILL.md` documenta o script para a escolha local; em `skills/executar/SKILL.md` a frase "Você roda cada bateria que a tarefa toca" vira um ponteiro de tamanho igual ou menor para o script (o arquivo tem 11 B de folga; `bash scripts/testa-teto-skills.sh` segue verde).

### 2. Duplicata de definição avisada na edição [tipo: implementar]
atende: D2, D4, D7
arquivos: `hooks/aviso-duplicata.cjs`, `hooks/hooks.json`, `hooks/lib/config.cjs`, `skills/setup/SKILL.md`, `scripts/testa-conferir-categoria.sh`, `docs/travas-mecanicas.md`, `hooks/testa-config.sh`, `hooks/testa-memoria-marca.sh`, `hooks/testa-aviso-duplicata.sh`
depende de: nenhuma
busca:
- repo | grep -n "PostToolUse" hooks/hooks.json | só aviso-fluxo-shell.cjs em Bash|PowerShell; nenhum hook olha definição duplicada
- repo | grep -n "funcoes" scripts/conferir-duplicacao.cjs | conferir-duplicacao.cjs:236-272 compara nomes só no plugin e só sob demanda
- livro | ponytail band/metrics.ts | duplicateOf avisa nome já definido no índice
desfecho: construir
prova: `bash hooks/testa-aviso-duplicata.sh`
mutacao:
  arquivo: `hooks/aviso-duplicata.cjs`
  de: if (achados.length === 0) process.exit(0);
  para: process.exit(0);
  bateria: `bash hooks/testa-aviso-duplicata.sh`
  fixture: testa-aviso-duplicata.sh, caso "Write com function que já existe em outro arquivo rastreado avisa caminho:linha"
pronto quando: num repo git temporário com `lib/util.js` rastreado contendo `function somar(a, b)` na linha 3, o payload real de PostToolUse de `Write` (`hook_event_name`, `tool_name`, `tool_input.file_path` = `src/novo.js`, `tool_input.content` com `function somar(x, y)`, `cwd` no repo) faz `node hooks/aviso-duplicata.cjs` sair 0 com `hookSpecificOutput.additionalContext` citando `somar` e `lib/util.js:3`; `Edit` com `new_string` contendo `User Function MT100OK()` acha `user function mt100ok()` num `.prw` rastreado (caixa ignorada); nome que só existe no próprio arquivo editado não avisa; quatro nomes duplicados avisam só 3; nome extraído que não é identificador (ex.: `function --output=x`) é descartado sem chamar o git; fora de repo git, payload inválido ou com a chave `aviso-duplicata` desligada sai 0 sem saída; o hook nunca imprime `decision` — provado por `bash hooks/testa-aviso-duplicata.sh`. O `git grep` roda por `execFileSync` sem shell, com `--` antes do padrão e orçamento interno de 3 s; o hook está em `hooks/hooks.json` sob `PostToolUse` com matcher `Write|Edit|MultiEdit` e `timeout` 5, carrega `// @categoria: sensor`, a chave está em `CHAVES` de `hooks/lib/config.cjs` com linha na tabela de `skills/setup/SKILL.md` (`scripts/testa-conferir-setup.sh` verde), `docs/travas-mecanicas.md` ganha a linha do hook, e `scripts/testa-conferir-categoria.sh` passa contando 64 peças e 36 sensores.

### 3. Regras implícitas com id, verificação e teste [tipo: implementar]
atende: D2, D5
arquivos: `scripts/conferir-ancoras.cjs`, `skills/arqueologia/SKILL.md`, `agents/arqueologo.md`, `scripts/testa-conferir-ancoras-regras.sh`
depende de: nenhuma
prova: `bash scripts/testa-conferir-ancoras-regras.sh`
mutacao:
  arquivo: `scripts/conferir-ancoras.cjs`
  de: if (!regra.verificada || !regra.teste) regra.estado = 'sem-campos';
  para: if (false) regra.estado = 'sem-campos';
  bateria: `bash scripts/testa-conferir-ancoras-regras.sh`
  fixture: testa-conferir-ancoras-regras.sh, caso "regra R3 sem Verificada em sai sem-campos e exit 1"
pronto quando: num mapa temporário com `## Regras implícitas` contendo `**R1 — Período fechado barra**` com `Verificada em: abc1234` e `Teste: scripts/testa-x.sh`, `**R2 — Outra**` com `Verificada em: abc1234` e `Teste: nenhum`, e `**R3 — Terceira**` sem `Verificada em:`, `node scripts/conferir-ancoras.cjs <mapa> --repo <raiz>` imprime `regra R1 testada`, `regra R2 sem-teste`, `regra R3 sem-campos`, conta as três no resumo e sai 1; sem R3 sai 0 (R2 é aviso); um parágrafo de regra no formato antigo (sem `**R<n> — ...**`) sai `regra sem-id` como aviso, sem mudar o exit; parágrafo de descrição entre o título `**R<n> — ...**` e os campos (separado por linha em branco) é corpo da regra aberta, não `sem-id`; `Teste: Nenhum` em qualquer caixa é `sem-teste`; mapa sem a seção sai como hoje — provado por `bash scripts/testa-conferir-ancoras-regras.sh`. A forma é a linha do `de:`. `skills/arqueologia/SKILL.md` (seção e exemplo de `## Regras implícitas`) e `agents/arqueologo.md` mostram o formato `**R<n> — título**` com as duas linhas.

### 4. Co-mudança pelo histórico [tipo: implementar]
atende: D2, D6
arquivos: `scripts/co-mudanca.cjs`, `skills/arqueologia/SKILL.md`, `skills/plano/SKILL.md`, `scripts/testa-co-mudanca.sh`
depende de: 3
busca:
- repo | grep -rn "name-only" scripts | varrer.cjs:190-208 lê git log só com --grep; nada conta pares de arquivos
- livro | codebase-memory pass_githistory | co-change por commit, ignorando commit grande
desfecho: construir
prova: `bash scripts/testa-co-mudanca.sh`
mutacao:
  arquivo: `scripts/co-mudanca.cjs`
  de: if (arquivos.length > MAX_ARQUIVOS_COMMIT) continue;
  para: if (false) continue;
  bateria: `bash scripts/testa-co-mudanca.sh`
  fixture: testa-co-mudanca.sh, caso "commit com mais de 20 arquivos não conta par"
pronto quando: num repo git temporário com quatro commits que mudam `a.js` e `b.js` juntos, um commit que muda `a.js` com `c.js`, e três commits de 25 arquivos cada, todos com `a.js` e `d.js`, `node scripts/co-mudanca.cjs a.js --min 3` (rodado no repo) lista `b.js` com o score `juntos / mudancas_do_alvo` e não lista `c.js` (só 1 vez) nem `d.js` (só em commit grande); alvo com menos de `--min` mudanças diz "histórico insuficiente" e sai 0; alvo e vizinhos com acento no caminho (`Gestão de Contratos/MT100.prw`) contam o histórico e saem legíveis (`git -c core.quotePath=false`); fora de repo git sai ≠ 0 com motivo — provado por `bash scripts/testa-co-mudanca.sh`. A forma do corte é a linha do `de:`. `skills/arqueologia/SKILL.md` manda rodar o script por arquivo da fatia, e `skills/plano/SKILL.md` ganha uma frase (folga de 555 B) sugerindo conferir o `arquivos:` contra ele.

### 5. Versão 1.77.0, CHANGELOG e README [tipo: docs]
atende: D1, D8
arquivos: `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `CHANGELOG.md`, `README.md`
depende de: 1, 2, 3, 4
mutacao: n/a
  motivo: metadado de versão e documentação, sem comportamento a inverter
pronto quando: com o diff real das tarefas 1 a 4, os dois `plugin.json` dizem `1.77.0`, o badge do README diz 1.77.0, o CHANGELOG tem a entrada `1.77.0 — 2026-10-25` com uma linha por decisão entregue (D3 a D6) citando o `arquivo:linha` do furo, e o README documenta os dois scripts novos e o hook novo onde documenta os vizinhos — provado por `node -e "for (const f of ['.claude-plugin/plugin.json','.codex-plugin/plugin.json']) console.log(require('./'+f).version)"` devolvendo `1.77.0` duas vezes e pela leitura do revisor casando cada linha do CHANGELOG com o diff.
