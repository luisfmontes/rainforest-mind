# Plano: conferir-publicacao: `Authorization` com template JS ou concatenação de variável não é credencial (#494)

Design: docs/rainforest/design/2026-10-14-bearer-variavel.md

## O que não pode quebrar
- Os casos da #410 em `scripts/testa-conferir-publicacao.sh` (seção 10c) seguem com o mesmo resultado: f-string, `.format` e `"Bearer ${VAR}"` passam; literal hex, literal colado e `{KEY}` sem f-string são barrados.
- Toda a bateria `bash scripts/testa-conferir-publicacao.sh` segue com zero falha, e a do gate `bash hooks/testa-gate-publicacao-destino.sh` também.
- `password`, `secret`, `api_key` e as outras chaves não ganham isenção nova (D3).

## Tarefas

### 1. Template JS e concatenação no ramo `Authorization` da #410, com bateria [tipo: implementar]
atende: D1, D2, D3, D4
arquivos: `scripts/conferir-publicacao.cjs`, `scripts/testa-conferir-publicacao.sh`
depende de: nenhuma
prova: `node -e "const fs=require('fs'),os=require('os'),p=require('path'),cp=require('child_process');const q=String.fromCharCode(39);const f=p.join(os.tmpdir(),'rfm-494-prova.cjs');fs.writeFileSync(f,'const h = { authorization: '+q+'Bearer '+q+' + tok };\n');process.exit(cp.spawnSync(process.execPath,['scripts/conferir-publicacao.cjs',f]).status)"`
mutacao:
  arquivo: `scripts/conferir-publicacao.cjs`
  de: if (concatVariavel) return false;
  para: if (false) return false;
  bateria: `bash scripts/testa-conferir-publicacao.sh`
  fixture: testa-conferir-publicacao.sh, seção 10c, casos "494 concatenação ... passa"
pronto quando: com arquivos de código reais contendo cada linha abaixo, `node scripts/conferir-publicacao.cjs <arquivo>` sai 0 para as que passam e 2 (citando `credencial`) para as que barram, provado por `bash scripts/testa-conferir-publicacao.sh` com zero falha e pelo comando de `prova:` saindo 0.

Passam (exit 0):
- `` const h = { Authorization: `Bearer ${token}` }; ``
- `const h = { authorization: 'Bearer ' + tok };`
- `const h = { Authorization: "Bearer " + this.token };`
- `const h = { Authorization: 'Bearer ' + process.env.API_TOKEN };`
- `const h = { Authorization: 'Bearer ' + getToken() };`
- `const h = { Authorization: 'Basic ' + obterToken(conta) };`

Continuam barrados (exit 2):
- `` const h = { Authorization: `Bearer ${token}abc123literal` }; `` (literal colado)
- `` const h = { Authorization: `Bearer <32 hex>` }; `` (literal no lugar da referência)
- `const h = { Authorization: 'Bearer ' + '<32 hex>' };` (literal concatenado)
- `const h = { Authorization: 'Bearer ' + getToken('<32 hex>') };` (chamada com argumento literal)
- `api_key: 'Bearer ' + tok` (D3: só `Authorization`; emenda 2026-10-14: o `password: 'x' + y` original já passava na base pela isenção de prosa curta e não separava D3)

Forma do código (alvo de mutação em código a nascer): dentro do ramo `chave === 'authorization'` da #410, (a) o reconhecimento do esquema aceita crase de abertura além de `f`, `"` e `'`, e o template segue a mesma régua da referência `${ident}` sem literal colado; (b) a concatenação é decidida numa constante `concatVariavel`, calculada a partir do texto da linha depois do esquema (fecha-aspa, `+`, expressão), e o ramo tem exatamente uma linha `if (concatVariavel) return false;`. Expressão aceita: identificador ou cadeia de membros (`a.b.c`), opcionalmente terminada em chamada cujos argumentos são só identificadores/membros ou vazios. Nenhum caso de teste lê o texto do fonte; as linhas de teste montam chave e esquema em pedaços, como a seção 10c já faz.

### 2. CHANGELOG, README e versão [tipo: docs]
atende: D1, D2, D3
arquivos: `CHANGELOG.md`, `README.md`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`
depende de: 1
mutacao: n/a
  motivo: tarefa de documentação e número de versão; não há comportamento a inverter
pronto quando: com a tarefa 1 no repo, a entrada nova do CHANGELOG (PATCH sobre a versão da `origin/main` no momento do despacho) descreve o contrato de D1–D3 — template com `${}` e concatenação com variável passam só em `Authorization` com esquema, literal continua barrado —, e as duas `plugin.json` e o selo do README batem com ela, provado por `node scripts/conferir-versao.cjs` saindo 0 e por leitura do revisor confrontando a entrada com D1–D3.
