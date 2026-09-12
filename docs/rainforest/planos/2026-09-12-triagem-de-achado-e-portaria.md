# Plano: Triagem de achado (defeito ≠ ideia) e portaria fora do fluxo

Design: docs/rainforest/design/2026-09-12-triagem-de-achado-e-portaria.md

Medições que este plano usa, todas feitas antes de escrevê-lo:

```
NUCLEOS hoje                      5598 / 5600 B   (folga 2 B)
Agregado hoje (orcamento.cjs)    14927 / 15000 B  (folga 73 B, limiar de aviso 300 B)
Núcleo da regra 6 hoje             251 B
Núcleo da regra 6 proposto         557 B          (delta +306 B)
NUCLEOS depois                    5904 B
Agregado depois                  15233 B
Transcript da sessão de origem   1.076.811 B, 444 linhas
```

Tetos escolhidos: `NUCLEOS_MAX_BYTES` 5600 → **6000** (folga 96 B, 1,6%);
agregado 15000 → **15600** (folga 367 B, acima do limiar de aviso de 300 B).

## O que não pode quebrar

- A portaria continua **fail-closed** sem autorização: manifesto ausente ou
  inválido, agente não declarado e `escreve: true` sem `isolation: "worktree"`
  continuam negando, com ou sem autorização no transcript.
- Toda negação continua saindo com **motivo não vazio** — negação muda é bug.
- Nenhuma bateria existente da portaria fica vermelha:
  `hooks/testa-portaria.sh`, `testa-portaria-nucleo.cjs`,
  `testa-portaria-portoes.cjs`, `testa-portaria-lint.cjs`,
  `testa-portaria-captura.cjs`, `testa-portaria-diagnostico.cjs`,
  `testa-portaria-gitignore.cjs`, `testa-portaria-tools-bloco.cjs`.
- O bloco de regras continua sendo extraído: `blocoRegras` não cai no piso de
  caracteres e a sessão nunca abre com "FALHA AO CARREGAR AS REGRAS".
- A regra 11 **não afrouxa**: autorização dispensa o portão de ESTÁGIO e nada
  mais.
- O leitor de transcript não pode pendurar o hook: lê cauda, nunca o arquivo
  inteiro.
- `.rainforest/portaria/despachos.jsonl` continua append-only e com uma linha
  JSON autocontida por decisão.

## Tarefas

### 1. Subir os dois tetos de orçamento, com o motivo escrito ao lado do número [tipo: configurar]
atende: D2
arquivos: `hooks/lib/contexto-sessao.cjs`, `scripts/orcamento.cjs`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `hooks/lib/contexto-sessao.cjs`
  de: `NUCLEOS_MAX_BYTES: 6000`
  para: `NUCLEOS_MAX_BYTES: 5600`
  bateria: `bash hooks/testa-contexto-sessao.sh`
  fixture: caso do teto de núcleos com o SKILL.md já emendado (tarefa 2)
pronto quando: com o `SKILL.md` desta branch, `node scripts/orcamento.cjs` sai com exit 0 e imprime `Total: 15233 B` sem a linha `Aviso de folga em agregado`; e `node -e "const m=require('./hooks/lib/contexto-sessao.cjs'); console.log(m.TETOS.NUCLEOS_MAX_BYTES)"` devolve `6000`

### 2. Emendar o núcleo da regra 6 com a triagem de achado [tipo: implementar]
atende: D1
arquivos: `skills/rainforest-mind/SKILL.md`
depende de: 1
paralela: nao
mutacao:
  arquivo: `skills/rainforest-mind/SKILL.md`
  de: o parágrafo do núcleo da regra 6 com a triagem
  para: o parágrafo antigo, só "Plantio de ideias"
  bateria: `node hooks/testa-portaria-nucleo.cjs` não serve; usar `bash hooks/testa-contexto-sessao.sh`
  fixture: caso que extrai o núcleo da regra 6 e exige a palavra `Issue` dentro dele
pronto quando: `node -e "const fs=require('fs'),m=require('./hooks/lib/contexto-sessao.cjs');const n=m.extrairNucleo(m.filtrarRegras(fs.readFileSync('skills/rainforest-mind/SKILL.md','utf8')));const r6=n.split(/\n\n/).find(b=>b.startsWith('**6.'));console.log(/Issue/.test(r6), /conserta na hora/.test(r6), Buffer.byteLength(r6,'utf8'))"` imprime `true true 557`

### 3. Corrigir o ponteiro de elaboração para o nome real do arquivo [tipo: implementar]
atende: D3
arquivos: `hooks/lib/contexto-sessao.cjs`
depende de: 1
paralela: nao
mutacao:
  arquivo: `hooks/lib/contexto-sessao.cjs`
  de: o `regra-<n>.md` corrigido para dois dígitos
  para: `regra-<n>.md` sem zero à esquerda
  bateria: `bash hooks/testa-contexto-sessao.sh`
  fixture: caso que monta a injeção e confirma que o caminho impresso existe em disco
pronto quando: o texto injetado cita `regra-06.md` (não `regra-6.md`), e `node -e "const fs=require('fs');console.log(fs.existsSync('skills/rainforest-mind/references/regra-06.md'))"` devolve `true` para o caminho tal como impresso

### 4. Levar a triagem para a elaboração da regra 6 [tipo: docs]
atende: D1
arquivos: `skills/rainforest-mind/references/regra-06.md`
depende de: 2
paralela: nao
mutacao: n/a
  motivo: é texto de referência, lido por humano e por sessão que decidiu abrir o arquivo; não tem comportamento a inverter. O teto dele é conferido pela tarefa 1.
pronto quando: `node -e "const fs=require('fs');const t=fs.readFileSync('skills/rainforest-mind/references/regra-06.md','utf8');console.log(/defeito/i.test(t), /feedback/.test(t), Buffer.byteLength(t,'utf8') < 10500)"` imprime `true true true`

### 5. Leitor de autorização do usuário no transcript [tipo: implementar]
atende: D4, D5
arquivos: `hooks/lib/autorizacao-usuario.cjs`, `test/fixtures/transcript-autorizacao.jsonl`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `hooks/lib/autorizacao-usuario.cjs`
  de: o retorno `false` do ramo de marcador subordinado (`falo que`, `disse que`, `que autorizo`)
  para: `true`
  bateria: `node hooks/testa-portaria-autorizacao.cjs`
  fixture: `turno-reclamacao` — o turno real desta sessão que menciona a autorização dentro de "…falo que autorizo subagentes…"
pronto quando: com a fixture derivada do transcript real, `node -e "const a=require('./hooks/lib/autorizacao-usuario.cjs');console.log(a.autorizado('test/fixtures/transcript-autorizacao.jsonl'))"` devolve `true` (a mensagem de meio de turno, em linha `queue-operation`/`attachment`, é reconhecida) e o mesmo leitor com a fixture reduzida só ao turno-reclamação devolve `false`

### 6. Portaria consulta a autorização antes de negar por estágio [tipo: implementar]
atende: D4, D6, D8
arquivos: `hooks/portaria.cjs`
depende de: 5
paralela: nao
mutacao:
  arquivo: `hooks/portaria.cjs`
  de: a consulta à autorização no ramo "sem estágio ativo"
  para: negar direto, como hoje
  bateria: `node hooks/testa-portaria-autorizacao.cjs`
  fixture: `sem-estagio-com-autorizacao`
pronto quando: com um payload sem fluxo aberto e `transcript_path` apontando para a fixture autorizada, o hook sai com **exit 0** e o `despachos.jsonl` ganha uma linha com `"decisao":"allow"` e `"via":"autorizacao-do-usuario"`; com o mesmo payload e a fixture do turno-reclamação, sai com **exit 2** e motivo `sem estágio ativo — abra um fluxo`

### 7. Bateria da autorização, incluindo o que ela NÃO pode liberar [tipo: teste]
atende: D4, D5, D6, D8
arquivos: `hooks/testa-portaria-autorizacao.cjs`
depende de: 6
paralela: nao
mutacao:
  arquivo: `hooks/testa-portaria-autorizacao.cjs`
  de: a asserção do caso `escreve-true-sem-worktree-continua-negado`
  para: asserção invertida (esperar exit 0)
  bateria: `node hooks/testa-portaria-autorizacao.cjs`
  fixture: `escreve-true-sem-worktree-continua-negado`
pronto quando: `node hooks/testa-portaria-autorizacao.cjs` sai com exit 0 cobrindo, no mínimo, os casos: autorização em turno digitado (`promptSource: "typed"`), autorização em linha `queue-operation`/`attachment`, turno-reclamação (nega), negação explícita "não autorizo" (nega), manifesto ausente com autorização (**continua negando**), `escreve: true` com autorização mas sem `isolation: "worktree"` (**continua negando**), e `escreve: true` com autorização e `name` preenchido (**continua negando**)

### 8. Declarar os agentes nativos no manifesto deste repositório [tipo: configurar]
atende: D7
arquivos: `.rainforest/agentes.json`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `.rainforest/agentes.json`
  de: a entrada `"Explore"` do manifesto
  para: entrada removida
  bateria: `node hooks/testa-portaria-lint.cjs`
  fixture: caso de lint do manifesto real
pronto quando: `node hooks/portaria.cjs --lint` sai com exit 0, e um payload com `subagent_type: "Explore"` dentro de um fluxo aberto sai com exit 0 em vez do atual `agente 'Explore' não consta no manifesto`

### 9. Issue de decisão: portaria no nível do plugin [tipo: docs]
atende: D10
arquivos: (nenhum no repo — Issue no GitHub)
depende de: nenhuma
paralela: sim
mutacao: n/a
  motivo: a entrega é um registro externo pedindo decisão do usuário, não código com comportamento a inverter.
pronto quando: `gh issue list --repo luisfmontes/rainforest-mind --state open --search "portaria nivel do plugin"` devolve exatamente uma Issue, cujo corpo contém as quatro medições da correção da D7 (`skills/setup/SKILL.md`, `scripts/*.cjs`, `hooks/hooks.json`, `.claude/settings.json`)

### 10. Colher a observação de 2026-08-24 [tipo: docs]
atende: D9
arquivos: (nenhum no repo — `ideias.jsonl` da pasta de dados, via script)
depende de: 2, 6
paralela: nao
mutacao: n/a
  motivo: a escrita é do `scripts/ideias.cjs`, que já tem suas próprias provas (backup, gravação atômica, conferência byte a byte das linhas não-alvo).
pronto quando: `node scripts/ideias.cjs conferir` sai com exit 0 e `obs-2026-08-24-defeito-do-plugin-oferecido-como-ideia` aparece com `status: "colhida"`, `colhida_em: "2026-09-12"` e `resultado` citando este fluxo e as Issues #239/#240

## Em aberto

(vazio)
