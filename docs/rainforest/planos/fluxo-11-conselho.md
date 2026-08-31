# Plano: Fluxo 11 — Conselho (debate estruturado de decisões de design)

Design: docs/rainforest/design/fluxo-11-conselho.md
(narrativa completa e emenda Q2: docs/rainforest/design/fluxo-11-design-conselho.md)

## O que não pode quebrar
- Nenhuma dependência npm entra no repo; `child_process` e `path.join` puros (D14).
- Nenhuma bateria depende de CLI externo instalado — membro de teste é fixture (D11).
- Falha de membro ligado nunca vira "segue sem ele": reprovação com motivo (D9).
- Credencial (GEMINI_API_KEY etc.) nunca entra em arquivo versionado (D8).
- `estado.cjs`, `poda.cjs` e o motor de portões não são tocados.
- A branch `fluxo/ponte` e seus arquivos não são tocados; conflito com ela se resolve na integração, nunca antecipando código de lá.

## Tarefas

### 1. Contrato de membro, resolução e quórum [tipo: implementar]
atende: D6, D7, D10, D13
arquivos: `scripts/conselho.cjs`, `scripts/testa-conselho.sh`, `scripts/fixtures/conselho/membro-ok.cjs`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `scripts/conselho.cjs`
  de: a reprovação de quórum quando a contagem de membros ligados é `< 3`
  para: `< 1`
  bateria: `bash scripts/testa-conselho.sh`
  fixture: caso `quorum-dois-membros` da bateria (membros.json com 2 ligados → abrir tem de sair ≠ 0)
pronto quando: com `.rainforest/conselho/membros.json` real declarando `[{nome, cmd, ligado}]` — 2 ligados —, `node scripts/conselho.cjs abrir --questao <md>` sai ≠ 0 listando os membros ligados; sem `membros.json`, o `abrir` gera o arquivo padrão com as 3 personas Claude (`cetico`, `arquiteto`, `usuario-final`) ligadas e `codex`/`gemini` desligados, e o cabeçalho de `conselho.cjs` contém a atribuição a karpathy/llm-council com URL — provado por `node scripts/conselho.cjs abrir --questao q.md` nos dois cenários e `head -20 scripts/conselho.cjs`.

### 2. Fase 1 — abrir, pareceres e falha fechada [tipo: implementar]
atende: D2, D9
arquivos: `scripts/conselho.cjs`, `scripts/testa-conselho.sh`, `scripts/fixtures/conselho/membro-sem-objecao.cjs`, `scripts/fixtures/conselho/membro-falha.cjs`, `scripts/fixtures/conselho/membro-json-invalido.cjs`
depende de: 1
paralela: nao
mutacao:
  arquivo: `scripts/conselho.cjs`
  de: o ramo que reprova a fase quando um membro ligado sai com exit ≠ 0 ou escreve saída vazia
  para: prosseguir com os pareceres que existirem
  bateria: `bash scripts/testa-conselho.sh`
  fixture: caso `membro-indisponivel-reprova` (membros.json com um `membro-falha.cjs` ligado → `conferir --fase pareceres` tem de sair ≠ 0 citando o membro)
pronto quando: com uma rodada real aberta em `.rainforest/conselho/<id>/` e um prompt-arquivo por membro, membro fixture que escreve `parecer` válido fecha a fase; membro que sai exit 1, escreve vazio ou JSON fora do schema (`posicao`, `argumentos`, `objecoes`, `riscos`) reprova a fase apontando membro e campo — provado por `node scripts/conselho.cjs conferir --fase pareceres` devolvendo exit 0 no cenário completo e ≠ 0 com motivo não vazio em cada cenário de falha.

### 3. Fase 2 — anonimização e revisões [tipo: implementar]
atende: D4
arquivos: `scripts/conselho.cjs`, `scripts/testa-conselho.sh`, `scripts/fixtures/conselho/membro-revisor-ok.cjs`, `scripts/fixtures/conselho/membro-ranking-incompleto.cjs`
depende de: 2
paralela: nao
mutacao:
  arquivo: `scripts/conselho.cjs`
  de: o renome anonimizado (membro-A/B/C embaralhado) aplicado aos pareceres antes da distribuição da fase 2
  para: distribuir os pareceres com o nome real da persona
  bateria: `bash scripts/testa-conselho.sh`
  fixture: caso `identidade-nao-vaza` (grep dos nomes das personas nos arquivos distribuídos da fase 2 tem de não casar)
pronto quando: com os 3 pareceres válidos da fase 1 no disco, `node scripts/conselho.cjs revisar` gera para cada membro um pacote só com os pareceres DOS OUTROS, renomeados membro-A/B/C — provado por `grep -rE 'cetico|arquiteto|usuario-final' .rainforest/conselho/<id>/fase2/` não casando nada, e por revisão fixture com ranking incompleto ou com empate fazendo `conferir --fase revisao` sair ≠ 0.

### 4. Fase 3 — chairman mecânico e síntese [tipo: implementar]
atende: D5
arquivos: `scripts/conselho.cjs`, `scripts/testa-conselho.sh`
depende de: 3
paralela: nao
mutacao:
  arquivo: `scripts/conselho.cjs`
  de: a agregação por posição média com desempate por contagem de primeiros lugares
  para: usar somente o ranking do primeiro revisor
  bateria: `bash scripts/testa-conselho.sh`
  fixture: caso `agregacao-conhecida` (três rankings fixos cujo agregado correto é calculado à mão no teste e diverge do ranking do primeiro revisor)
pronto quando: com três `revisao-*.json` fixos cujos rankings têm agregado conhecido calculado à mão, `node scripts/conselho.cjs sintetizar` grava `sintese.json` com `ranking_agregado` exatamente igual ao esperado, sem invocar modelo nenhum na agregação — provado pelo caso `agregacao-conhecida` da bateria comparando o array inteiro.

### 5. Catracas por exit code e teto ABANDONA [tipo: implementar]
atende: D3
arquivos: `scripts/conselho.cjs`, `scripts/testa-conselho.sh`
depende de: 4
paralela: nao
mutacao:
  arquivo: `scripts/conselho.cjs`
  de: a exigência `objecoes.length >= 1` na validação de parecer
  para: `>= 0`
  bateria: `bash scripts/testa-conselho.sh`
  fixture: caso `parecer-sem-objecao` (parecer com `objecoes: []` → `conferir --fase pareceres` tem de sair ≠ 0 citando o membro)
pronto quando: com artefatos reais no diretório da rodada: parecer com `objecoes: []` reprova citando o membro; síntese sem `divergencias_nao_resolvidas` e sem `--unanime` reprova; com `--unanime` explícito passa; terceira tentativa consecutiva reprovada na mesma fase grava `ABANDONA` no estado da rodada (`.rainforest/conselho/<id>/estado.json`) e a segunda não — provado por `node scripts/conselho.cjs conferir --fase <f>` e pela leitura do estado da rodada em cada cenário.

### 6. Interruptores no /setup e seção no /saude [tipo: implementar]
atende: D8, D12
arquivos: `hooks/lib/config.cjs`, `scripts/saude.cjs`, `scripts/testa-saude.sh`, `scripts/conselho.cjs`, `scripts/testa-conselho.sh`, `skills/setup/SKILL.md`
depende de: 1
paralela: nao
mutacao:
  arquivo: `scripts/conselho.cjs`
  de: membro externo entra na resolução somente quando a chave `conselho-<nome>` está ligada no config
  para: entrar sempre
  bateria: `bash scripts/testa-conselho.sh`
  fixture: caso `externo-desligado-fica-fora` (config padrão → resolução lista só as 3 personas Claude)
pronto quando: com o config padrão (nenhuma chave ligada), a resolução de membros lista só as 3 personas Claude; após `node scripts/setup.cjs --ligar conselho-codex --escopo projeto`, o membro `codex` entra na resolução com o cmd embutindo os fatos operacionais do design (D8) e o quórum passa a contar 4; `node scripts/saude.cjs` com uma rodada aberta parada e uma ABANDONA imprime a seção do conselho como `aviso` com exit 0, e sem rodada nenhuma não imprime seção — provado pelos três comandos com as saídas comparadas nos dois estados de config e de rodada.

### 7. Gancho opt-in no estágio design e documentação [tipo: docs]
atende: D1
arquivos: `skills/brainstorm/SKILL.md`, `README.md`, `docs/rainforest/design/fluxo-11-design-conselho.md`
depende de: 5, 6
paralela: nao
mutacao: n/a
  motivo: tarefa de doc não tem comportamento a inverter; a falsificação é a coerência com a interface real das tarefas 1-6
pronto quando: a seção nova do `skills/brainstorm/SKILL.md` instrui o estágio design a rodar o conselho quando `.rainforest/conselho/` existe, e cada comando citado nela (`abrir`, `revisar`, `sintetizar`, `conferir --fase`, `--unanime`, chaves `conselho-codex`/`conselho-gemini`) existe de fato no `conselho.cjs`/`config.cjs` entregues — provado rodando cada comando citado no texto contra o script real (exit e flags reconhecidas) e por `README.md` mencionando o conselho na lista de peças com o mesmo contrato.

### 8. Bateria completa, fixtures ruins e lint de dependência [tipo: teste]
atende: D11, D14
arquivos: `scripts/testa-conselho.sh`, `scripts/fixtures/conselho/membro-ok.cjs`, `scripts/fixtures/conselho/membro-sem-objecao.cjs`, `scripts/fixtures/conselho/membro-falha.cjs`, `scripts/fixtures/conselho/membro-json-invalido.cjs`, `scripts/fixtures/conselho/membro-revisor-ok.cjs`, `scripts/fixtures/conselho/membro-ranking-incompleto.cjs`
depende de: 5
paralela: nao
mutacao: n/a
  motivo: a tarefa é a própria bateria e as fixtures; o que a falsifica é cada caso vermelho das mutações declaradas nas tarefas 1-6, re-rodadas na integração
pronto quando: com o repo como está (nenhum CLI externo instalado é pré-requisito), `bash scripts/testa-conselho.sh` roda no Windows desta máquina cobrindo os casos nomeados nas tarefas 1-6 com zero `skipped`, e um lint de require (grep por `require(` que não seja módulo nativo nem caminho relativo) em `scripts/conselho.cjs` e `scripts/fixtures/conselho/*.cjs` não casa nada — provado pelas duas saídas coladas.

### 9. Validação manual com codex e gemini reais [tipo: teste]
atende: D8, D9
arquivos: `relatorios/2026-08-31-conselho-validacao-externa.md`
depende de: 6, 8
paralela: nao
mutacao: n/a
  motivo: validação manual de integração externa; o comportamento mutável já está coberto pelas tarefas 2 e 6, e bateria não pode depender de CLI instalado (D11)
pronto quando: com os dois CLIs autenticados desta máquina e as chaves `conselho-codex`/`conselho-gemini` ligadas em escopo projeto, uma rodada real com questão real fecha as 3 fases com 5 membros, e o relatório cola a saída real: `sintese.json` gerado, `ranking_agregado` com 5 posições, e o cenário de indisponibilidade real (chave GEMINI_API_KEY removida do ambiente) reprovando a fase com motivo — provado pelo relatório com os comandos e saídas verbatim e o `sintese.json` da rodada de teste anexado.
