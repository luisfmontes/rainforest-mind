# Plano: Agente arqueologo — passadas e triagem para fontes legados grandes

Design: docs/rainforest/design/2026-08-22-agente-arqueologo.md

## O que não pode quebrar

- A skill `arqueologia` continua **não gerando código e não modificando fonte nenhum**: escreve em `docs/rainforest/mapas/` e mais nada (`SKILL.md:26-27`).
- `arqueologia` continua **fora do gate**: `estado.cjs` nunca a barra e ela nunca barra ninguém (`scripts/estado.cjs:93`), e ela segue fora da lista de "proximo estagio".
- Nenhum arquivo de `C:\Microsiga\protheus-totvs-agro\inovacao` é lido com escrita, copiado para dentro do repo, ou alterado. A prova roda sobre cópia em diretório temporário.
- O bloco entre `<!-- perfil-de-trabalho:inicio -->` e `:fim` continua **gerado por `scripts/perfil.cjs`**, nunca escrito à mão, e aparece exatamente uma vez por agente.
- Frontmatter de agente continua com exatamente três chaves: `name`, `description`, `model`.
- As baterias que já existem continuam verdes — em especial `scripts/testa-perfil.sh` e `scripts/testa-conferir-fluxo.sh`.

## Tarefas

### 1. Script de triagem [tipo: implementar]
atende: D3, D4, D9, D11
arquivos: `scripts/triagem.cjs`
depende de: nenhuma
paralela: sim
mutacao:
  arquivo: `scripts/triagem.cjs`
  de: o corte de repetição `0.6` acima do qual a classe é dado-como-codigo
  para: `0.99`
  bateria: `bash scripts/testa-triagem.sh`
pronto quando: com cópias de `templates/Expordics/updiag.prw` (27.992 linhas, 18 funções, 96,7% de repetição) e `templates/OG/Fechamento_Financeiro/M - Miscelanea/IAG67M12.prw` (13.692 linhas, 219 funções, 32,3%) num diretório temporário, o script classifica o primeiro como `dado-como-codigo` e o segundo como `logica`, e devolve a contagem de funções por regex ancorada de declaração (não por ocorrência da palavra `function`) — provado por `node scripts/triagem.cjs <copia> --json` devolvendo `"classe":"dado-como-codigo","nfunc":18` e `"classe":"logica","nfunc":219`. O script **não** emite estratégia de leitura (D4): a chave `estrategia` não existe na saída.

### 2. Bateria da triagem [tipo: teste]
atende: D3, D9, D11
arquivos: `scripts/testa-triagem.sh`
depende de: 1
paralela: nao
mutacao:
  arquivo: `scripts/triagem.cjs`
  de: a faixa cinzenta `>= 0.4 && < 0.6` que devolve `indefinido`
  para: faixa vazia (`>= 0.4 && < 0.4`)
  bateria: `bash scripts/testa-triagem.sh`
pronto quando: com um fonte na faixa cinzenta (`templates/EST/Laudos de Lotes/V - Validacao/IAG04V02.tlpp`, 52,5% de repetição, 30 linhas/função) o script devolve `"classe":"indefinido"`, e com dois caminhos distintos de conteúdo idêntico (`receituario/BASE/.../nfesefaz.prw` e `receituario/COTRIEL/.../nfesefaz.prw`, 13.650 linhas cada) devolve o mesmo `hash` e marca o segundo como duplicata — provado por validação por mutação: trocando o corte de repetição de `0.6` para `0.99` em `triagem.cjs`, `bash scripts/testa-triagem.sh` sai diferente de 0; restaurado, sai 0.

### 3. Método na skill: passadas, triagem, fatia intra-arquivo e fragmento [tipo: docs]
atende: D2, D5, D6, D7, D8, D10
arquivos: `skills/arqueologia/SKILL.md`
depende de: nenhuma
paralela: sim
mutacao: n/a
  motivo: a tarefa é texto de skill — não há ramo de execução a inverter. O comportamento que o texto descreve é exercitado pela tarefa 5, e é lá que a mutação mora.
pronto quando: com a skill carregada por `/arqueologia`, o texto entrega sem ambiguidade os quatro parâmetros que o agente precisa para agir — teto de bloco em bytes, formato da âncora de função, caminho do fragmento e nome da seção de regra implícita — provado por `grep -ocE '40\.000 caracteres|\.prw#<funcao>|mapas/<fatia>/<bloco>\.md|## Regras implícitas' skills/arqueologia/SKILL.md` devolvendo 4 ocorrências distintas. A trava de fatia existente (`SKILL.md:22-24`) e a tabela de conferência de três saídas (`:48-52`) continuam no texto, sem alteração de significado.

### 4. Arquivo do agente [tipo: implementar]
atende: D1, D2
arquivos: `agents/arqueologo.md`
depende de: 3
paralela: nao
mutacao:
  arquivo: `agents/arqueologo.md`
  de: a linha que manda carregar `Skill(arqueologia)`
  para: linha removida
  bateria: `bash scripts/testa-gate-do-agente.sh` (a bateria antes declarada aqui, `testa-perfil.sh`, confere só o bloco de perfil e **não** morde esta mutação — achado 2 da revisão de 2026-08-23)
pronto quando: com o arquivo no lugar, o frontmatter tem exatamente `name`, `description`, `model` com `model: sonnet`, o corpo manda carregar `Skill(arqueologia)` em vez de repetir o método, e o bloco de perfil aparece uma vez só vindo do gerador — provado por `node scripts/perfil.cjs --conferir` (ou o modo de conferência que o script tiver) sem divergência, e por `bash scripts/testa-perfil.sh` verde com o agente novo incluído na contagem.

### 5. Prova ponta a ponta em cópia [tipo: teste]
atende: D5, D7, D10, D11
arquivos: `scripts/testa-arqueologo-ponta-a-ponta.sh`
depende de: 1, 3, 4
paralela: nao
mutacao:
  arquivo: `scripts/testa-arqueologo-ponta-a-ponta.sh`
  de: a conferência de que o `arquivo:linha` citado existe e não está vazio
  para: conferência trocada por `true`
  bateria: `bash scripts/testa-arqueologo-ponta-a-ponta.sh` com um mapa de fixture que cita uma linha inexistente
pronto quando: com cópia de `IAG67M12.prw` num diretório temporário e a fatia de um bloco, a rodada produz `docs/rainforest/mapas/<fatia>/<bloco>.md` contendo ao menos uma afirmação `CONFIRMADO` cujo `arquivo:linha` **existe no fonte** — provado por script que relê a linha citada na cópia e confirma que ela não está vazia; e o bloco produzido não passa de 40.000 caracteres, medido por `wc -c`. Nenhum arquivo fora do diretório temporário e de `docs/rainforest/mapas/` é criado ou alterado, verificado por `git status --short` limpo fora desses caminhos.

## Emenda de 2026-08-23 — achados da revisão

A revisão independente reprovou com quatro achados. Os dois primeiros são falha
de **critério**, não de execução: a tarefa 5 mediu outra coisa que não o que
prometia, e a mutação declarada da tarefa 4 aponta para uma bateria incapaz de
mordê-la — `scripts/testa-perfil.sh` confere só o bloco de perfil, nunca o corpo
do agente. A bateria daquela mutação passa a ser a da tarefa 7. Emendar é o
único jeito de destravar: justificar em prosa não conta.

### 6. Rodada real do arqueologo contra fonte legado [tipo: teste]
atende: D5, D7, D10
arquivos: `docs/rainforest/mapas/COBERTURA.md`, `docs/rainforest/mapas/IAG67M12/*.md`
depende de: 1, 3, 4, 5
paralela: nao
mutacao: n/a
  motivo: é execução de prova, não código com ramo a inverter — o instrumento que a julga é o validador da tarefa 5, cuja mutação já está declarada lá.
pronto quando: com cópia de `templates/OG/Fechamento_Financeiro/M - Miscelanea/IAG67M12.prw` num diretório temporário, um despacho real do agente `arqueologo` sobre **um** bloco produz `docs/rainforest/mapas/<fatia>/<bloco>.md`, e `scripts/testa-arqueologo-ponta-a-ponta.sh` rodado **sobre esse mapa real** (não sobre fixture) sai 0 — provado colando o caminho do mapa, o `wc -c` do bloco abaixo de 40.000, e ao menos um `CONFIRMADO` cuja linha citada, relida na cópia, não está vazia.

### 7. Gate que reprova agente duplicando a skill [tipo: teste]
atende: D1, D2
arquivos: `scripts/testa-gate-do-agente.sh`
depende de: 4
paralela: nao
mutacao:
  arquivo: `agents/arqueologo.md`
  de: a linha que manda carregar a skill de arqueologia
  para: linha removida
  bateria: `bash scripts/testa-gate-do-agente.sh`
pronto quando: com `agents/arqueologo.md` íntegro a bateria sai 0; removida a linha que carrega a skill, ela sai diferente de 0; e com a tabela de conferência da skill copiada para dentro do agente (duplicação do método, que é o que D2 proíbe), ela também sai diferente de 0 — provado colando as três saídas.

### 8. Consertos do triagem apontados pela revisão [tipo: implementar]
atende: D9, D11
arquivos: `scripts/triagem.cjs`, `scripts/testa-triagem.sh`
depende de: 1, 2
paralela: nao
mutacao:
  arquivo: `scripts/triagem.cjs`
  de: o apontamento direto de `duplicataDe` para o canônico
  para: a reatribuição em cadeia (o comportamento de hoje)
  bateria: `bash scripts/testa-triagem.sh`
pronto quando: com quatro cópias idênticas passadas na ordem `C B D A`, todas as três não canônicas apontam `duplicataDe` para `A` — hoje `C` e `D` apontam para `B`, que é ele próprio uma duplicata; e com arquivo vazio ou binário, a classe **não** é `dado-como-codigo` e o `--json` não devolve `densidade: null` silenciosamente — provado por `node scripts/triagem.cjs` nos dois cenários, com a saída colada.
