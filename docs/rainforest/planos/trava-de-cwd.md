# Plano: a trava de cwd

Design: docs/rainforest/design/trava-de-cwd.md

Base: `origin/main` na ponta `d5d24b6`. Branch de trabalho `fix/trava-de-cwd`.

## O que não pode quebrar

- **A bateria `hooks/testa-contexto-sessao.sh` continua verde**, e o veredito é o
  **exit code** mais a linha de placar final (`ok: N falhou: 0`) — nunca um grep
  por `FALHA`. A seção 17.1 imprime `FALHA` de propósito dentro de sub-shells que
  não contam no placar, e ler por substring já custou uma Issue falsa hoje.
- **O núcleo do `SKILL.md` não cresce um byte.** Folga de 11 B (5589 de 5600).
  Nada deste plano entra no núcleo: a regra 3 já diz "Na abertura" lá.
- **Cada `references/regra-<n>.md` sob 10500 B** separadamente.
- **As três escotilhas de toda trava continuam funcionando** — `RAINFOREST_GATE_OFF`
  no env, `.rainforest-gate-off` no toplevel, e a chave em `CHAVES`. Trava sem
  escape é trava que o usuário desliga arrancando do `hooks.json`.
- **Nenhuma trava nova barra escrita fora de repo git.** O `~/.rainforest/`, o
  scratchpad e arquivo solto passam. É o critério que separa esta trava de uma
  que morre desligada.
- **`computarVeredito` continua devolvendo string vazia quando nada se aplica.**
  Ela é concatenada no rodapé da injeção; uma linha a mais sempre presente
  come orçamento de `FOCO.md`.
- Node continua a única dependência.

## Tarefas

### 1. A diretiva de prazo sai do mesmo lugar que a de desvio [tipo: implementar]
atende: D1, D2
arquivos: `hooks/lib/contexto-sessao.cjs`, `hooks/testa-contexto-sessao.sh`
depende de: nenhuma
paralela: sim
pronto quando: `bash hooks/testa-contexto-sessao.sh` sai **exit 0** com linha final `ok: N falhou: 0`, N ≥ 276 (as 273 de hoje mais os casos novos); **e** `node -e "const m=require('./hooks/lib/contexto-sessao.cjs');const foco='## Ativo\n\n**F** \`[trabalho]\`\nPastas: C:/x\nOciosidade máxima: 15 min.\n';const s=[{cwd:'C:/x',prompt_ts:Date.now()-60000,stop_ts:0}];const v=m.computarVeredito(foco,s,{expediente:undefined},Date.now());console.log(JSON.stringify(v));process.exit(/prazo/i.test(v)&&/NÃO cobrar desvio/.test(v)?0:1)"` sai **exit 0** — a diretiva de prazo e a de desvio saem juntas quando o foco está ativo em outra janela; **e** o mesmo comando com `prompt_ts: Date.now()-3600000` (sessão ociosa muito além dos 15 min) devolve string SEM `prazo`
nota: a diretiva nova sai só quando a isenção 1 (`foco ativo em outra janela`) dispara — nunca junto de `tempo pessoal` sozinho, e nunca quando `pastas`/`ociosidade` faltam, porque aí o radar já anuncia indeterminação e a nota seria palpite. O texto manda apresentar prazo como NOTA, não silenciar: silenciar contradiz o `README.md:196`. E `computarVeredito` continua devolvendo `''` quando nada se aplica.
mutacao:
  arquivo: `hooks/lib/contexto-sessao.cjs`
  de: a diretiva de prazo condicionada à isenção 1
  para: emitir a diretiva de prazo **sempre**, fora do `if`
  bateria: `bash hooks/testa-contexto-sessao.sh` — tem que sair **exit 1** com o caso que exige string vazia sem isenção acusando no placar. Se sair verde, é porque não existe caso cobrindo "nada se aplica devolve vazio", e ele entra nesta tarefa

### 2. README e regra 3 param de se contradizer sobre o prazo [tipo: documentar]
atende: D3
arquivos: `README.md`, `skills/rainforest-mind/references/regra-03.md`
depende de: nenhuma
paralela: sim
pronto quando: `node -e "const fs=require('fs');const r=fs.readFileSync('README.md','utf8');const g=fs.readFileSync('skills/rainforest-mind/references/regra-03.md','utf8');const mal=r.includes('continua saindo, sempre');const bom=/nota/i.test(g)&&/abertura/i.test(g);const b=Buffer.byteLength(g,'utf8');console.log(JSON.stringify({readme_contradiz:mal,regra_fala_de_nota:bom,bytes_regra:b}));process.exit(!mal&&bom&&b<10500?0:1)"` sai **exit 0**; e as duas prosas, lidas em sequência, dizem a MESMA coisa — conferido no `revisar`, não por máquina
nota: o parágrafo do README que muda é o `**A isenção cala só o aviso de desvio de escopo.**` (linha ~196). O raciocínio dele — informação não custa, cobrança custa — se PRESERVA; o que muda é a conclusão "continua saindo, sempre", que passa a ser "continua saindo, como nota e não como cobrança". Na regra 3, a frase de `d5d24b6` que diz "a frase de desvio ou a linha de prazo" é a que se estreita. E entra a proibição da D1: prazo é de abertura, nunca do fechamento.
mutacao:
  arquivo: `README.md`
  de: o parágrafo alinhado, sem a frase "continua saindo, sempre"
  para: devolver a frase "continua saindo, sempre" ao README, deixando o texto novo da regra 3 no lugar
  bateria: o `node -e` do `pronto quando:` acima — tem que sair **exit 1** com `readme_contradiz: true`, provando que o critério enxerga a contradição e não só a presença do texto novo

### 3. A trava de escrita em repo alheio [tipo: implementar]
atende: D4, D5, D6, D8
arquivos: `hooks/gate-repo-alheio.cjs` (novo), `hooks/hooks.json`, `hooks/lib/config.cjs`, `hooks/testa-gate-repo-alheio.sh` (novo)
depende de: nenhuma
paralela: sim
pronto quando: `bash hooks/testa-gate-repo-alheio.sh` sai **exit 0** com `== resultado: N ok, 0 falha(s) ==`, N ≥ 10, cobrindo obrigatoriamente estes casos: (a) escrita no repo da própria sessão → **exit 0**; (b) escrita em caminho fora de git → **exit 0**; (c) escrita dentro de OUTRO repo git → **exit 2**; (d) escrita em worktree linkado do MESMO repo → **exit 0** (worktree é o mesmo projeto); (e) `RAINFOREST_GATE_OFF=1` com o caso (c) → **exit 0**; (f) `.rainforest-gate-off` no toplevel do destino com o caso (c) → **exit 0**; (g) ferramenta que não é de escrita (Bash) → **exit 0**; (h) payload ilegível → **exit 0**; **e** `node -e "const c=require('./hooks/lib/config.cjs');const k=Object.keys(c.CHAVES||{});console.log(k.join(','));process.exit(k.includes('gate-repo-alheio')&&k.includes('gate-publicacao')?0:1)"` sai **exit 0** — as duas chaves registradas (a nova e a que estava inerte); **e** `node -e "const h=require('./hooks/hooks.json');const t=JSON.stringify(h);process.exit(t.includes('gate-repo-alheio.cjs')?0:1)"` sai **exit 0**
nota: `CHAVES` pode não estar exportado hoje — se não estiver, exportá-lo é parte desta tarefa (é o que torna o critério verificável). A comparação de repo é por `git rev-parse --show-toplevel` dos DOIS lados, normalizado com barra e minúscula; dois toplevels não-nulos e diferentes = repo alheio. Worktree linkado do mesmo repo tem toplevel diferente da árvore principal — trate como MESMO projeto comparando `git rev-parse --git-common-dir`, senão o caso (d) barra e a trava fica inútil nesta sessão, que trabalha em worktree. Não reaproveite `combina()` do `semear.cjs`: ele é substring bidirecional e casaria quase tudo.
mutacao:
  arquivo: `hooks/gate-repo-alheio.cjs`
  de: a comparação de toplevel que decide "repo alheio"
  para: inverter a condição — barrar quando os toplevels são IGUAIS
  bateria: `bash hooks/testa-gate-repo-alheio.sh` — tem que sair **exit 1** com os casos (a) e (d) acusando no placar, provando que a bateria distingue mesmo-repo de repo-alheio e não só "barrou/não barrou"

### 4. O texto da regra 13 passa a dizer o que é verdade [tipo: documentar]
atende: D7
arquivos: `skills/rainforest-mind/references/regra-13.md`
depende de: nenhuma
paralela: sim
pronto quando: `node -e "const t=require('fs').readFileSync('skills/rainforest-mind/references/regra-13.md','utf8');const b=Buffer.byteLength(t,'utf8');const mal=/esconde das sessões onde ela precisa reaparecer|a esconde justamente das sessões/.test(t);console.log(JSON.stringify({bytes:b,ainda_afirma_o_falso:mal}));process.exit(!mal&&b<10500?0:1)"` sai **exit 0**
nota: o que cai é a JUSTIFICATIVA falsa, não a prescrição — `projeto: solta` continua sendo o valor certo para observação de método, e continua sendo o único slug que nasce com `caminho: null`. O que o texto passa a dizer: hoje `projeto` quase não decide reaparecimento (o jardineiro mostra independente dele, e a abertura não lê o ledger), então o valor certo é `solta` por CATEGORIA — a observação não é daquele repositório — e o reaparecimento por sessão é mecanismo que ainda não existe, com ideia plantada e gancho. Citar o número: 58 das 62 observações abertas estão sob um projeto, 40 sob `rainforest-mind`.
mutacao:
  arquivo: `skills/rainforest-mind/references/regra-13.md`
  de: a justificativa corrigida
  para: devolver a frase "a esconde justamente das sessões onde ela precisa reaparecer" ao parágrafo
  bateria: o `node -e` do `pronto quando:` acima — tem que sair **exit 1** com `ainda_afirma_o_falso: true`

## Ordem

As quatro saem em **paralelo** — nenhuma toca arquivo de outra. A 1 e a 3 são
código com bateria e vão para agente em worktree; a 2 e a 4 são texto de precisão
e ficam na janela principal.

O plantio da ideia do reaparecimento (D7, segunda metade) é do fecho, pelo
`ideias.cjs plantar` — nunca à mão, e nunca dentro de uma tarefa de agente.
