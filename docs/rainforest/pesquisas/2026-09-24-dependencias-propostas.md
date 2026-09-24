# Dependências propostas entre ideias abertas (tarefa 6)

Pesquisa da tarefa 6 do plano
`docs/rainforest/planos/2026-09-24-beads-por-cima-do-ideias.md`. Design de
referência: `docs/rainforest/design/2026-09-24-beads-por-cima-do-ideias.md`
(D2, D3). Lembrete de D2: `depende_de` é SÓ bloqueio — "B não deve ser feita
antes de A". Parentesco, irmandade, vizinhança ou "ver também" **não** é
dependência; nesses casos a classificação é `irma`, e o campo `depende_de`
continua sem efeito para elas (o vínculo de parentesco já existe em prosa,
como `[[id]]`).

Este documento só lê `~/.rainforest/ideias.jsonl` (leitura, nunca escrita). A
gravação real do `depende_de` aprovado, por `ideias.cjs editar`, acontece
depois do merge desta pesquisa, fora deste fluxo — ver a seção "Lista final
proposta" abaixo.

## Lista final proposta (pronta para aplicar)

Das 86 citações encontradas (ver critério e comando abaixo), só **uma** foi
classificada `depende_de`; as outras 45 são `irma` e 40 são `outro`. A
proposta de `depende_de` para aplicar com `node scripts/ideias.cjs editar` é:

```json
{
  "papel-de-advisor-que-observa-a-janela-principal": [
    "autoavaliacao-do-metodo-contra-o-rastro"
  ]
}
```

Justificativa: o `gancho` de `papel-de-advisor-que-observa-a-janela-principal`
diz, literalmente, "Quando a autoavaliação do método (ideia
`autoavaliacao-do-metodo-contra-o-rastro`) rodar a primeira vez e apontar qual
regra o usuário mais teve que cobrar a mão — [...] esse é o trabalho do
advisor e a ideia acorda; se não existir, ela morre com causa registrada." A
ideia fica dormente até a outra rodar — isso é bloqueio real, não parentesco
— e `autoavaliacao-do-metodo-contra-o-rastro` segue `plantada` (aberta), então
o bloqueio ainda vale.

### Checagem: sem id inexistente e sem ciclo

Script próprio (não usa a biblioteca da tarefa 1, `scripts/lib/dependencias-ideias.cjs`,
porque ela ainda não existe neste worktree — tarefa paralela, não mesclada
até este ponto da tarefa 6):

```
$ node checar-proposta.js
ids inexistentes: nenhum
ciclo: nenhum
total depende_de propostos: 1
```

Script (`checar-proposta.js`, salvo fora do repositório — cole aqui para
reproduzir):

```js
const fs = require('fs');
const path = require('path');
const os = require('os');
const file = path.join(os.homedir(), '.rainforest', 'ideias.jsonl');
const lines = fs.readFileSync(file, 'utf8').split('\n').filter(Boolean);
const objs = lines.map((l) => JSON.parse(l));
const idsValidos = new Set(objs.map((o) => o.id));

const proposta = {
  'papel-de-advisor-que-observa-a-janela-principal': ['autoavaliacao-do-metodo-contra-o-rastro'],
};

let erros = [];
for (const [id, deps] of Object.entries(proposta)) {
  if (!idsValidos.has(id)) erros.push(`id da chave nao existe: ${id}`);
  for (const dep of deps) {
    if (!idsValidos.has(dep)) erros.push(`${id} -> id inexistente: ${dep}`);
  }
}

function acharCiclo(grafo) {
  const cor = new Map();
  const caminho = [];
  function dfs(no) {
    cor.set(no, 1);
    caminho.push(no);
    for (const viz of grafo[no] || []) {
      if (cor.get(viz) === 1) {
        const ini = caminho.indexOf(viz);
        return caminho.slice(ini).concat(viz);
      }
      if (!cor.get(viz)) {
        const r = dfs(viz);
        if (r) return r;
      }
    }
    cor.set(no, 2);
    caminho.pop();
    return null;
  }
  for (const no of Object.keys(grafo)) {
    if (!cor.get(no)) {
      const r = dfs(no);
      if (r) return r;
    }
  }
  return null;
}

const ciclo = acharCiclo(proposta);
console.log('ids inexistentes:', erros.length ? erros : 'nenhum');
console.log('ciclo:', ciclo || 'nenhum');
console.log('total depende_de propostos:', Object.values(proposta).reduce((s, a) => s + a.length, 0));
```

## Medição: quem cita quem

Critério usado (a instrução original citava uma medição anterior de 59 entre
as plantadas, com ids de 12+ caracteres; a medição abaixo, feita agora, deu um
número diferente — ver nota no fim desta seção): entre as ideias com `status`
`plantada` OU `em-colheita` (336 no arquivo hoje: 335 `plantada` + 1
`em-colheita`), qualquer uma cujo texto — em **qualquer campo string** do
registro (`titulo`, `descricao`, `contexto`, `projeto`, `projeto_nota`,
`ao_colher`, `andamento`, `resultado`, `gancho`, `motivo`, `aprendizado`,
`titulo_curto`) — contém, como substring literal, o `id` de **outra** ideia
do mesmo arquivo, de **qualquer status** (`plantada`, `em-colheita`,
`colhida`, `descartada`, `unificada`). Testei com e sem piso de tamanho de id
(0 a 15 caracteres — o menor id do arquivo tem 15) e o resultado não muda,
porque nenhum id é curto o bastante para gerar falso positivo por acaso.

Comando exato:

```
$ node -e "
const fs = require('fs');
const path = require('path');
const os = require('os');
const file = path.join(os.homedir(), '.rainforest', 'ideias.jsonl');
const lines = fs.readFileSync(file, 'utf8').split('\n').filter(Boolean);
const objs = lines.map((l) => JSON.parse(l));
const ids = objs.map((o) => o.id).filter((id) => id.length >= 12);
const abertas = objs.filter((o) => o.status === 'plantada' || o.status === 'em-colheita');
function textoDe(o) {
  return Object.entries(o).filter(([, v]) => typeof v === 'string').map(([, v]) => v).join('\n');
}
const achados = [];
for (const o of abertas) {
  const texto = textoDe(o);
  const citadas = [];
  for (const id of ids) {
    if (id === o.id) continue;
    if (texto.includes(id)) citadas.push(id);
  }
  if (citadas.length) achados.push({ id: o.id, citadas });
}
console.log('abertas total:', abertas.length);
console.log('abertas que citam outra ideia:', achados.length);
console.log('total de citacoes (soma):', achados.reduce((s, a) => s + a.citadas.length, 0));
"
abertas total: 336
abertas que citam outra ideia: 55
total de citacoes (soma): 86
```

**Nota sobre a divergência com os 59 citados na tarefa**: com este mesmo
critério (qualquer campo string, qualquer status da citada, ids >= 12
caracteres), a contagem hoje é **55 ideias abertas / 86 citações**, não 59.
Testei variar o piso de tamanho do id (0, 5, 8, 10, 11, 12, 13, 14, 15) e o
resultado fica travado em 55 em todos os casos — não é o piso de 12
caracteres que explica a diferença. `~/.rainforest/ideias.jsonl` é editado
por várias sessões ao longo do mesmo dia (487 registros no total, com
colheitas e edições correndo em paralelo a este plano), então a medição de 59
citada no briefing e a de 55 feita agora provavelmente vêm de estados
diferentes do arquivo no mesmo dia — LACUNA: não tenho como reconstruir o
estado exato do arquivo no momento em que os 59 foram contados, então não dá
para confirmar a causa exata da diferença, só registrar que o critério
declarado (texto de qualquer campo contendo o id de outra ideia, aberta ou
não) foi seguido à risca e é estável a variações de piso de tamanho.

## Classificação por ideia

Cada bloco abaixo é uma ideia aberta que cita outra. Quando cita mais de uma,
cada citação vem com seu próprio trecho e classificação. `[[id]]` na citação
colada é o formato de link que o próprio `ideias.jsonl` usa em prosa.

### `claude-central-despachante` (plantada)

- cita `obs-2026-09-04-listagents-nao-cruza-config-dir` (plantada) — **irma**
  - (`contexto`) "nçar a janela funciona, ela virar interlocutora não. Terceiro limite, plantado à parte em obs-2026-09-04-listagents-nao-cruza-config-dir: ListAgents não atravessa config dir, então sessão do perfil de trabalho (~/.claude) é in"
  - Porquê: cita a outra como um 'terceiro limite' plantado à parte, sem dizer que esta espera por ela — são obstáculos vizinhos do mesmo projeto, não bloqueio declarado.

### `vigia-de-resposta-whatsapp-sem-token` (plantada)

- cita `whatsapp-mcp-windows-multiconta` (colhida) — **outro**
  - (`andamento`) "brainstorm, nao plano. DESBLOQUEIO: a decisao de 2026-08-22 de nao esperar o mantenedor original (ver whatsapp-mcp-windows-multiconta) tira o obstaculo -- mexer no bridge deixou de exigir PR upstream. E a regua do rainfores"
  - Porquê: o texto usa a palavra DESBLOQUEIO, mas descreve um obstáculo que JÁ caiu (decisão de não esperar o mantenedor upstream) e a bloqueadora está colhida — a dependência, se existiu, já se cumpriu.

- cita `vigias-dependem-do-bridge-whatsapp` (colhida) — **outro**
  - (`contexto`) "s vigias (run-vigia.ps1, sentinela-foco) e há lição plantada sobre dependência do bridge (vigias-dependem-do-bridge-whatsapp): ler porta/caminho de config, não hardcode."
  - (`ao_colher`) "leitura apenas (SELECT por chat_jid + timestamp > marco), reaproveitando a lição da ideia vigias-dependem-do-bridge-whatsapp (caminho do store e porta vindos de config/env, nunca fixos); 3) ao detectar resposta: no"
  - (`andamento`) ". O argumento a favor do push nao e latencia, e LIVENESS, e ataca direto a licao da ideia vigias-dependem-do-bridge-whatsapp: um vigia que consulta o SQLite NAO distingue 'um contato ainda nao respondeu' de 'a bridge"
  - Porquê: cita a outra como lição já registrada para reaproveitar (ler porta/caminho de config), não como algo que precisa terminar antes; e está colhida.

### `sol-foreman-delegacao-verificada` (plantada)

- cita `gate-do-p1-e-hook-nao-texto` (colhida) — **outro**
  - (`ao_colher`) "ler os skills/ inteiros em ~20 minutos e aproveitar duas coisas para o gate do P1 (ver [[gate-do-p1-e-hook-nao-texto]]) - (1) o vocabulario, que ja vem afiado: 'builder nao certifica o proprio trabalho' e '"
  - Porquê: referencia vocabulário/lição já pronta para copiar de uma ideia colhida — uso de precedente, não bloqueio.

- cita `batedor-vigia-de-repos-ancorado` (colhida) — **outro**
  - (`ao_colher`) "|| LICAO DE METODO, que vale mais que o repo e precisa entrar no prompt do batedor (ver [[batedor-vigia-de-repos-ancorado]]): o repo de 238 mil estrelas nao tinha nada pra copiar neste problema, e o de 4 estrela"
  - Porquê: mesma forma: 'LIÇÃO DE MÉTODO... ver [[id]]' de ideia já colhida, reaproveitamento de lição, não dependência viva.

### `task-observer-e-a-regra-13-com-diff` (plantada)

- cita `sol-foreman-delegacao-verificada` (plantada) — **irma**
  - (`ao_colher`) "r semana continua sendo teto e nao meta. Cuidado ao ler o repo: a licao do sol-foreman ([[sol-foreman-delegacao-verificada]]) vale aqui tambem - o que interessa e o mecanismo do cruzamento, nao adotar a skill del"
  - Porquê: 'a lição do sol-foreman vale aqui também' é reaproveitamento de raciocínio entre irmãs, não uma espera declarada.

### `mapa-que-ninguem-confere-envelhece-em-silencio` (plantada)

- cita `escala-de-confianca-em-toda-afirmacao` (colhida) — **irma**
  - (`contexto`) "a mesma leitura da skill arqueologia — sao irmaos e provavelmente se colhem juntos, ver [[escala-de-confianca-em-toda-afirmacao]]. Ganhou peso no mesmo dia por dois motivos independentes: o hook passou a resumir os av"
  - Porquê: o próprio texto diz 'são irmãos e provavelmente se colhem juntos'.

- cita `mutirao-de-gancho-nas-35-abertas-herdadas` (plantada) — **irma**
  - (`gancho`) "ez que alguem for abrir mais de duas ideias antigas na mesma sessao. Tambem cabe junto do mutirao-de-gancho-nas-35-abertas-herdadas, que ja varre a fila inteira."
  - Porquê: 'também cabe junto do mutirão X' é sugestão de fazer junto, não pré-requisito.

- cita `conferir-entrega-nao-sabe-lidar-com-despacho-paralelo` (colhida) — **outro**
  - (`ao_colher`) "ra local da arvore de trabalho, e a economia de bytes que ela mandava medir era ZERO; (3) conferir-entrega-nao-sabe-lidar-com-despacho-paralelo ja estava quase toda implementada desde 14/08, e o que sobra dela esta acoplado a uma per"
  - Porquê: menção histórica dentro de um relato de mutirão ('já estava quase toda implementada'); ideia colhida, sem relação de bloqueio.

- cita `gitattributes-exige-lf-mas-arquivos-estao-em-crlf-no-disco` (colhida) — **outro**
  - (`ao_colher`) "13/08, foi consertada em 15/08 pela nota D5 e ficou aberta so por falta de colheita; (2) gitattributes-exige-lf-mas-arquivos-estao-em-crlf-no-disco tinha a premissa errada — index e HEAD ja estavam em LF, o CRLF era sujeira local da arvo"
  - Porquê: mesmo relato histórico do mutirão, listando ideias cuja premissa já estava resolvida; colhida.

- cita `testa-saude-quebra-com-historico-nao-linear` (colhida) — **outro**
  - (`ao_colher`) "de CINCO ideias que foram abertas para trabalho, TRES tinham a premissa ja resolvida. (1) testa-saude-quebra-com-historico-nao-linear, plantada em 13/08, foi consertada em 15/08 pela nota D5 e ficou aberta so por falta de c"
  - Porquê: mesmo relato histórico do mutirão ('a premissa já resolvida'); colhida, sem bloqueio.

### `publicar-o-rainforest-separando-codigo-de-dado` (plantada)

- cita `rainforest-publico-em-ingles` (plantada) — **irma**
  - (`ao_colher`) "essa parte mora). O que NAO e desta ideia e ja tem casa propria: traducao para ingles ([[rainforest-publico-em-ingles]]), CI fora do Windows ([[rainforest-fora-do-windows]]) e o CONTRIBUTING, que ja existe."
  - Porquê: texto diz explicitamente que tradução para inglês 'NÃO é desta ideia e já tem casa própria' — escopo vizinho, não bloqueio.

- cita `rainforest-fora-do-windows` (plantada) — **irma**
  - (`ao_colher`) "a propria: traducao para ingles ([[rainforest-publico-em-ingles]]), CI fora do Windows ([[rainforest-fora-do-windows]]) e o CONTRIBUTING, que ja existe."
  - Porquê: mesmo carve-out de escopo ('CI fora do Windows... já tem casa própria'), sibling de escopo.

- cita `ao-publicar-so-issue-e-pr-e-a-main-protegida` (plantada) — **irma**
  - (`ao_colher`) "ongela como arquivo privado; (3) na mesma sessao da publicacao, a protecao da main (ver [[ao-publicar-so-issue-e-pr-e-a-main-protegida]], que e onde essa parte mora). O que NAO e desta ideia e ja tem casa propria: traducao p"
  - Porquê: mesmo carve-out de escopo ('proteção da main... é onde essa parte mora').

### `prompt-da-psicologa-converge-com-as-regras-7-8-9` (plantada)

- cita `segundo-cerebro` (colhida) — **outro**
  - (`descricao`) "transcrito aqui e nao pode entrar no repo nem no historico dele. Destino certo e o vault segundo-cerebro ou a pasta de dados."
  - (`ao_colher`) "regra 8 ja dispara, sem criar gatilho novo. E decidir o destino do texto integral: vault segundo-cerebro ou pasta de dados, nunca este repo."
  - Porquê: cita 'vault segundo-cerebro' como destino de texto, referência a ideia colhida, não bloqueio.

- cita `publicar-o-rainforest-separando-codigo-de-dado` (plantada) — **irma**
  - (`contexto`) "om falta-a-regra-de-comecar-ativacao-comportamental, que e a parte nova de verdade, e com publicar-o-rainforest-separando-codigo-de-dado, que e o que torna a pergunta de onde guardar urgente em vez de teorica."
  - Porquê: diz que a outra 'torna a pergunta de onde guardar urgente' — motivação/contexto cruzado, não espera declarada.

- cita `falta-a-regra-de-comecar-ativacao-comportamental` (plantada) — **irma**
  - (`contexto`) "gnorar o aviso, mesmo raciocinio do corte de 75 min da regra 8. Tem parentesco direto com falta-a-regra-de-comecar-ativacao-comportamental, que e a parte nova de verdade, e com publicar-o-rainforest-separando-codigo-de-dado, que"
  - Porquê: o próprio texto diz 'tem parentesco direto com' a outra ideia.

### `falta-a-regra-de-comecar-ativacao-comportamental` (plantada)

- cita `prompt-da-psicologa-converge-com-as-regras-7-8-9` (plantada) — **irma**
  - (`contexto`) "Saiu da leitura do prompt de 2026-08-09 as 17:01, plantado junto com prompt-da-psicologa-converge-com-as-regras-7-8-9. A separacao entre os dois e proposital: aquele e avaliacao de encaixe e decisao de onde"
  - Porquê: 'plantada junto com... a separação entre os dois é proposital' — irmãs por desenho, cada uma segue sozinha.

### `canal-fora-do-terminal-para-o-que-nao-cabe-na-sessao` (plantada)

- cita `whatsapp-mcp-windows-multiconta` (colhida) — **outro**
  - (`contexto`) "esponder na sessao anterior, entao a confiabilidade dela e desconhecida, e existe a ideia whatsapp-mcp-windows-multiconta ainda aberta. Antes de escrever qualquer agendamento, medir se a ponte fica de pe sozinha"
  - Porquê: o texto chama a outra de 'ainda aberta', mas ela já está colhida no arquivo atual — a dependência, se existiu, já se cumpriu.

- cita `prompt-da-psicologa-converge-com-as-regras-7-8-9` (plantada) — **irma**
  - (`descricao`) "Consequencia direta de prompt-da-psicologa-converge-com-as-regras-7-8-9. Alimentacao, atividade fisica e o fecho da noite nao cabem no rainforest-mind por um mot"
  - Porquê: 'consequência direta de' descreve origem/motivação da ideia, não uma espera — a outra segue aberta e as duas podem avançar em paralelo.

### `revisao-dos-nomes-de-comando-antes-da-traducao` (plantada)

- cita `rainforest-publico-em-ingles` (plantada) — **irma**
  - (`gancho`) "cou: a primeira Issue ou PR aberta por alguem que nao e o usuário, que e o que a ideia irma `rainforest-publico-em-ingles` usa como marco."
  - Porquê: o próprio texto chama a outra de 'ideia irmã'.

### `ao-publicar-so-issue-e-pr-e-a-main-protegida` (plantada)

- cita `relatorio-vira-gerador-de-issue` (colhida) — **outro**
  - (`contexto`) "2026-08-11, conversa sobre transformar o /relatorio em gerador de Issue (ver [[relatorio-vira-gerador-de-issue]]). O usuário acrescentou a preocupacao de governanca: 'nao sei se depois que tiver publico"
  - (`ao_colher`) "defeito, e ai a triagem custa uma ida e volta que o template evitaria. Isso encosta em [[relatorio-vira-gerador-de-issue]], que e quem vai GERAR esses Issues."
  - Porquê: 'encosta em [[id]], que é quem vai GERAR esses Issues' é referência de tema vizinho a uma ideia já colhida, não bloqueio.

### `trazer-a-memoria-pra-dentro-do-rainforest` (plantada)

- cita `divulgacao-progressiva-no-skill-md` (colhida) — **outro**
  - (`ao_colher`) "injetada entra nessa briga, não em espaço livre. Ver [[foco-md-injetado-por-partes]] e [[divulgacao-progressiva-no-skill-md]]: a resposta provavelmente é ponteiro + busca sob demanda, que é a própria tese do claud"
  - Porquê: 'a resposta provavelmente é...' cita lição já colhida para orientar o desenho, não pré-requisito vivo.

- cita `foco-md-injetado-por-partes` (colhida) — **outro**
  - (`ao_colher`) "á brigam por esse espaço — memória injetada entra nessa briga, não em espaço livre. Ver [[foco-md-injetado-por-partes]] e [[divulgacao-progressiva-no-skill-md]]: a resposta provavelmente é ponteiro + busca s"
  - Porquê: mesma frase, mesma ideia colhida citada como referência de lição.

- cita `guarda-saude-worker-claude-mem` (colhida) — **outro**
  - (`contexto`) "14 medida pelo scripts/jornada.cjs). Veio logo depois de o /saude nascer e colher a ideia guarda-saude-worker-claude-mem no mesmo dia — aquela colheita entregou o PROBE pela porta, que anuncia a degradação; est"
  - Porquê: menção histórica ('aquela colheita entregou o PROBE'); ideia colhida, não bloqueio.

### `quebrar-macro-em-micro-iniciavel` (plantada)

- cita `foco-md-injetado-por-partes` (colhida) — **outro**
  - (`ao_colher`) "na injeção: empurraria REGRA para fora dela em silêncio, que é o mesmo modo de falha de [[foco-md-injetado-por-partes]]. Então: lista em arquivo próprio, FOCO.md com uma linha de ponteiro, e essa linha entra"
  - Porquê: 'mesmo modo de falha de [[id]]' é analogia com ideia já colhida, não dependência.

### `mutirao-de-gancho-nas-35-abertas-herdadas` (plantada)

- cita `mutirao-de-curadoria-dos-ganchos-herdados` (unificada, unificada_em_id: mutirao-de-gancho-nas-35-abertas-herdadas) — **outro**
  - (`contexto`) "no mesmo dia por sessoes diferentes: esta (ao fechar a Issue #3, com o numero certo) e a `mutirao-de-curadoria-dos-ganchos-herdados`, plantada por uma sessao em outro repo que rodou /ideia e leu o 72 do `reparar` antes da"
  - Porquê: a ideia citada foi UNIFICADA nesta mesma ideia (unificada_em_id aponta de volta para ela) — é registro do próprio merge, não bloqueio.

### `creep-se-mede-no-diff-contra-o-plano` (plantada)

- cita `cobertura-do-design-no-plano` (plantada) — **irma**
  - (`contexto`) "verge.md antes de escrever qualquer coisa: e uma pagina, e ja e o desenho. Irma da ideia `cobertura-do-design-no-plano`, que pega a deriva do outro lado (design para plano, ANTES de existir codigo); esta pega"
  - Porquê: o próprio texto chama a outra de 'irmã... que pega a deriva do outro lado'.

### `autoavaliacao-do-metodo-contra-o-rastro` (plantada)

- cita `segunda-opiniao-cross-model-no-revisor` (colhida) — **irma**
  - (`contexto`) "a por quem escreveu as regras. Vizinha de duas ideias ja plantadas, e distinta das duas: `segunda-opiniao-cross-model-no-revisor` e `council-hibrido-multi-modelo` aplicam troca de auditor a ENTREGA; esta aplica ao METO"
  - Porquê: o próprio texto diz 'vizinha de duas ideias já plantadas' e as distingue pela camada (entrega vs. método), não por ordem.

- cita `council-hibrido-multi-modelo` (colhida) — **irma**
  - (`contexto`) "uas ideias ja plantadas, e distinta das duas: `segunda-opiniao-cross-model-no-revisor` e `council-hibrido-multi-modelo` aplicam troca de auditor a ENTREGA; esta aplica ao METODO. A dependencia que travava as"
  - Porquê: mesma frase, mesma classificação de vizinhança explícita.

### `papel-de-advisor-que-observa-a-janela-principal` (plantada)

- cita `autoavaliacao-do-metodo-contra-o-rastro` (plantada) — **depende_de**
  - (`gancho`) "Quando a autoavaliacao do metodo (ideia `autoavaliacao-do-metodo-contra-o-rastro`) rodar a primeira vez e apontar qual regra o usuário mais teve que cobrar a mao — se existi"
  - Porquê: o gancho é literal: 'Quando a autoavaliação do método... rodar a primeira vez e apontar qual regra... esse é o trabalho do advisor e a ideia acorda; se não existir, ela morre' — esta ideia fica dormente até a outra rodar, e a outra segue aberta (plantada).

### `cobertura-do-design-no-plano` (plantada)

- cita `creep-se-mede-no-diff-contra-o-plano` (plantada) — **irma**
  - (`contexto`) "as duas viraram ideia: esta (analyze, deriva antes do codigo) e a taxonomia absorvida em `creep-se-mede-no-diff-contra-o-plano` (converge, deriva depois). Esta foi marcada na conversa como o buraco mais barato dos do"
  - Porquê: mesmo par de irmãs do item anterior, visto do outro lado ('a taxonomia absorvida em [[id]]... esta pega o outro lado').

### `divergir-como-estagio-da-esteira` (plantada)

- cita `segunda-opiniao-cross-model-no-revisor` (colhida) — **outro**
  - (`contexto`) "caminho foi reimplementar o contrato — precedente que ele ja tinha fixado duas vezes, em `segunda-opiniao-cross-model-no-revisor` e em `council-hibrido-multi-modelo`. Ele pediu explicitamente para plantar o que nao des"
  - Porquê: cita como precedente já fixado duas vezes ('ele já tinha fixado... em'); ideias colhidas, servem de exemplo, não de bloqueio.

- cita `council-hibrido-multi-modelo` (colhida) — **outro**
  - (`contexto`) "nte que ele ja tinha fixado duas vezes, em `segunda-opiniao-cross-model-no-revisor` e em `council-hibrido-multi-modelo`. Ele pediu explicitamente para plantar o que nao desse para fazer na hora, e esta e a pa"
  - Porquê: mesmo uso de precedente já colhido.

### `semantica-agi-grafo-para-segundo-cerebro` (plantada)

- cita `segundo-cerebro` (colhida) — **outro**
  - (`contexto`) "omo candidato para ajudar o 'graphy' -- a parte de graph view do Obsidian dentro da ideia segundo-cerebro (id segundo-cerebro, colhida em 2026-08-07, que usa Obsidian so como visualizador, nao co"
  - (`contexto`) "judar o 'graphy' -- a parte de graph view do Obsidian dentro da ideia segundo-cerebro (id segundo-cerebro, colhida em 2026-08-07, que usa Obsidian so como visualizador, nao como dono do formato)."
  - (`projeto`) "segundo-cerebro"
  - (`gancho`) "Se a limitacao do graph view nativo do Obsidian virar dor real no uso do vault segundo-cerebro, ou se o usuário quiser explorar raciocinio causal/proveniencia sobre as ligacoes do vault."
  - Porquê: descreve o que a ideia colhida já faz ('usa Obsidian só como visualizador') como contexto histórico, não como algo pendente.

### `comportamento-observado-antes-de-virar-falha-checar-o-ciclo-normal` (plantada)

- cita `regra-13-nao-tem-saida-para-fato-so-para-tarefa` (colhida) — **outro**
  - (`contexto`) "vacao que originalmente entrou a mao no ideias.jsonl misturando as duas naturezas — ver [[regra-13-nao-tem-saida-para-fato-so-para-tarefa]], plantada no mesmo dia, sobre a lacuna da regra 13 que produziu essa mistura."
  - Porquê: 'plantada no mesmo dia, sobre a lacuna da regra 13 que produziu essa mistura' é explicação de origem de uma ideia colhida, não bloqueio.

### `entrega-vazia-com-paralelo-nunca-cruza` (plantada)

- cita `ancestralidade-sem-paralelo-nao-tem-teste` (colhida) — **irma**
  - (`contexto`) "Pareto — nao quebra nada hoje, e mexer nisso e mudar D2, nao corrigir codigo. Irmao do [[ancestralidade-sem-paralelo-nao-tem-teste]]."
  - Porquê: o próprio texto diz 'irmão do [[id]]'.

### `skill-pessoal-vive-em-duas-config-dirs-e-ja-divergiu` (plantada)

- cita `segundo-cerebro` (colhida) — **outro**
  - (`descricao`) "d tinha 13.100 bytes (mtime 08/08). A diferenca nao e cosmetica: a secao 'Fundo do vault (segundo-cerebro)', que manda puxar Rosenberg/Carnegie/calibragem quando a mensagem e dificil (recusa, cob"
  - (`descricao`) "tem esse fundo ha 11 dias, e ninguem percebeu. Duplicadas do mesmo jeito: book-to-skill e segundo-cerebro. A CLAUDE.md ja registrava esse modo de falha em prosa desde 2026-08-10 ('editar uma acer"
  - (`gancho`) "icao de QUALQUER skill que exista nas duas config dirs (message-standards, book-to-skill, segundo-cerebro) — o momento em que a divergencia se aprofunda e tambem o momento em que ela e barata de"
  - Porquê: lista como exemplo de skill duplicada nas duas config dirs, ideia colhida citada por precedente.

- cita `pilha-de-voz-local-voicestudio` (colhida) — **outro**
  - (`contexto`) "2026-08-19 a noite, durante a colheita da ideia pilha-de-voz-local-voicestudio. A politica de voz decidida pelo usuário (o audio anuncia falado que foi o assistente, no in"
  - Porquê: âncora temporal ('durante a colheita da ideia X'); ideia colhida, referência histórica.

### `limiar-calibrado-em-fatia-nao-vale-na-gravacao-inteira` (plantada)

- cita `pilha-de-voz-local-voicestudio` (colhida) — **outro**
  - (`contexto`) "Colheita da ideia pilha-de-voz-local-voicestudio, madrugada de 2026-08-19 para 20. O custo foi 78 minutos de CPU e a descoberta so aparece"
  - Porquê: 'colheita da ideia X, madrugada de...' é âncora temporal de uma ideia já colhida, não bloqueio.

### `orcamento-e-run-log-por-loop-de-vigia` (plantada)

- cita `nivel-de-autonomia-declarado-no-briefing-do-vigia` (plantada) — **irma**
  - (`contexto`) "budget e run-log que o loop-init cria). O framework nao foi adotado — ver a ideia irma [[nivel-de-autonomia-declarado-no-briefing-do-vigia]] para o motivo. A regra 10 tem limiar de 3.000 tokens para DECIDIR se despacha, o que e"
  - Porquê: o próprio texto chama a outra de 'ideia irmã'.

### `portao-mecanico-para-a-regra-15` (plantada)

- cita `checador-deterministico-de-conformidade-de-regra-no-stop` (plantada) — **irma**
  - (`contexto`) "ist/allowlist'). Mesmo raciocinio que sobreviveu da analise do nopus no mesmo dia — ver [[checador-deterministico-de-conformidade-de-regra-no-stop]]: regra em prosa depende de o modelo lembrar, regra em codigo nao depende. A evidencia d"
  - Porquê: 'mesmo raciocínio que sobreviveu da análise... ver [[id]]' é reaproveitamento de raciocínio entre abertas, não espera.

- cita `nivel-de-autonomia-declarado-no-briefing-do-vigia` (plantada) — **irma**
  - (`contexto`) "inventa diagnostico e o que ignora restricao escrita. O framework nao foi adotado — ver [[nivel-de-autonomia-declarado-no-briefing-do-vigia]]."
  - Porquê: 'o framework não foi adotado — ver [[id]]' é referência de contexto, não bloqueio.

### `mit041-cliente-diagramas-de-fluxo-da-v2` (plantada)

- cita `gerador-de-mits-no-plugin-tbc` (plantada) — **irma**
  - (`ao_colher`) "formatacao, PYTHONIOENCODING=utf-8). VINCULO: esta tarefa e o primeiro caso de teste de [[gerador-de-mits-no-plugin-tbc]] -- se o gerador de MITs sair antes, os diagramas do cliente nascem por ele, e nao a mao."
  - Porquê: 'SE o gerador sair antes, os diagramas nascem por ele' é condicional/oportunista — esta ideia não precisa que a outra termine, pode seguir à mão.

### `gerador-de-mits-no-plugin-tbc` (plantada)

- cita `mit041-cliente-diagramas-de-fluxo-da-v2` (plantada) — **irma**
  - (`ao_colher`) "tem por item na descricao desta ideia e da para reescrever sem redescobrir. Amarrar com [[mit041-cliente-diagramas-de-fluxo-da-v2]], que e a tarefa concreta dos diagramas do cliente e vira o primeiro caso de teste do gera"
  - Porquê: 'amarrar com [[id]]... vira o primeiro caso de teste' é vínculo de uso futuro, mesma relação condicional do item anterior, vista do outro lado.

### `teste-que-le-saida-externa-cola-a-saida-crua-medida` (plantada)

- cita `timestamp-de-log-e-utc-nao-local` (colhida) — **outro**
  - (`descricao`) "ia: premissa-afirmada-sem-ser-olhada, medidor-improvisado-mentiu-duas-vezes-no-mesmo-dia, timestamp-de-log-e-utc-nao-local e controle-que-compartilha-o-confundidor-nao-e-controle (colhida em 2026-09-05). CASO 1,"
  - Porquê: 'já colhidos da mesma família' — lista quatro ideias colhidas citadas como precedente de uma mesma lição, não bloqueio.

- cita `medidor-improvisado-mentiu-duas-vezes-no-mesmo-dia` (colhida) — **outro**
  - (`descricao`) "a um passo de distancia. Ja colhidos da mesma familia: premissa-afirmada-sem-ser-olhada, medidor-improvisado-mentiu-duas-vezes-no-mesmo-dia, timestamp-de-log-e-utc-nao-local e controle-que-compartilha-o-confundidor-nao-e-controle"
  - Porquê: mesma lista de precedentes já colhidos.

- cita `premissa-afirmada-sem-ser-olhada` (colhida) — **outro**
  - (`descricao`) "lhar, tendo o comando que responde a um passo de distancia. Ja colhidos da mesma familia: premissa-afirmada-sem-ser-olhada, medidor-improvisado-mentiu-duas-vezes-no-mesmo-dia, timestamp-de-log-e-utc-nao-local e c"
  - Porquê: mesma lista de precedentes já colhidos.

- cita `controle-que-compartilha-o-confundidor-nao-e-controle` (colhida) — **outro**
  - (`descricao`) "a, medidor-improvisado-mentiu-duas-vezes-no-mesmo-dia, timestamp-de-log-e-utc-nao-local e controle-que-compartilha-o-confundidor-nao-e-controle (colhida em 2026-09-05). CASO 1, formato de saida de comando (2026-08-21): custou TRES te"
  - Porquê: mesma lista de precedentes já colhidos.

### `abertura-mede-e-anuncia-ultracode-e-workflows` (plantada)

- cita `regra-bloqueada-em-silencio` (colhida) — **outro**
  - (`descricao`) "tros sobre a regra 14 (regra bloqueada pelo ambiente se anuncia). Ja colhidos da familia: regra-bloqueada-em-silencio, aviso-de-bloqueio-chega-tarde-demais e observacao-2026-08-20-aviso-de-regra-10-bloqueada"
  - Porquê: 'já colhidos da família' lista três ideias colhidas como precedente, não bloqueio.

- cita `aviso-de-bloqueio-chega-tarde-demais` (colhida) — **outro**
  - (`descricao`) "bloqueada pelo ambiente se anuncia). Ja colhidos da familia: regra-bloqueada-em-silencio, aviso-de-bloqueio-chega-tarde-demais e observacao-2026-08-20-aviso-de-regra-10-bloqueada-nao-parou-o-turno. CASO 1, instrucao"
  - Porquê: mesma lista de precedentes já colhidos.

- cita `observacao-2026-08-20-aviso-de-regra-10-bloqueada-nao-parou-o-turno` (colhida) — **outro**
  - (`descricao`) "colhidos da familia: regra-bloqueada-em-silencio, aviso-de-bloqueio-chega-tarde-demais e observacao-2026-08-20-aviso-de-regra-10-bloqueada-nao-parou-o-turno. CASO 1, instrucao que colide com a regra 10 (2026-08-20, 21h50): no inicio do brainstorm"
  - Porquê: mesma lista de precedentes já colhidos.

### `obs-2026-08-22-escolhi-a-ideia-plantada-em-vez-de-perguntar` (plantada)

- cita `whatsapp-mcp-windows-multiconta` (colhida) — **outro**
  - (`descricao`) "u li 'background' como o processo/servico rodando de fundo e ancorei a analise inteira na whatsapp-mcp-windows-multiconta. Ele corrigiu: 'me expressei mal, o background era vigia-de-resposta-whatsapp-sem-token'"
  - (`contexto`) "sabado) no whatsapp-mcp, avaliando o que acoplar do ha-wa-bridge. As duas candidatas eram whatsapp-mcp-windows-multiconta (em-colheita, tema servico/background) e vigia-de-resposta-whatsapp-sem-token (plantada,"
  - Porquê: narra um incidente passado ('ancorei a análise inteira na X'); ideia colhida, contexto histórico.

- cita `vigia-de-resposta-whatsapp-sem-token` (plantada) — **irma**
  - (`descricao`) "ira na whatsapp-mcp-windows-multiconta. Ele corrigiu: 'me expressei mal, o background era vigia-de-resposta-whatsapp-sem-token' — ou seja, background era o VIGIA esperando de fundo, nao o daemon. O agravante nao e a"
  - (`contexto`) "candidatas eram whatsapp-mcp-windows-multiconta (em-colheita, tema servico/background) e vigia-de-resposta-whatsapp-sem-token (plantada, tema observar chat de fundo)."
  - Porquê: narra qual das duas ideias plantadas era a certa no incidente — cita como alternativa do mesmo momento, não como bloqueio.

### `nao-consulto-o-segundo-cerebro-sem-ser-mandado` (plantada)

- cita `segundo-cerebro` (colhida) — **outro**
  - (`titulo`) "Nao consulto o segundo-cerebro na pratica, mesmo com a skill mandando"
  - (`descricao`) "A skill segundo-cerebro diz literalmente 'Consulte SEM ele pedir' e lista os temas e situacoes que disparam. Na p"
  - Porquê: cita a SKILL chamada 'segundo-cerebro' ('a skill segundo-cerebro diz literalmente...'), não a ideia em si — e a ideia com esse id está colhida.

### `criterio-so-mede-o-que-a-maquina-le` (plantada)

- cita `evidencia-colada-vira-dado-pessoal-em-repo-publico` (colhida) — **outro**
  - (`ao_colher`) "ABSORVIDA em luisfmontes/rainforest-mind#83 (2026-08-24), junto com evidencia-colada-vira-dado-pessoal-em-repo-publico -- as duas sao a mesma forma: criterio de plano que so pergunta 'o comando devolve X?', n"
  - Porquê: 'ABSORVIDA em #83... junto com X' é registro de precedente já colhido no mesmo achado, não bloqueio.

### `briefing-que-proibe-background-nao-impede-o-background` (plantada)

- cita `o-checklist-pre-pr-passou-de-dez-minutos` (plantada) — **irma**
  - (`ao_colher`) "m integra, e o briefing pede do agente so o que cabe num turno dele (ataca tambem a ideia o-checklist-pre-pr-passou-de-dez-minutos); (b) o retorno do agente passa por uma checagem de FORMA antes de ser lido como entrega"
  - Porquê: 'ataca também a ideia X' é efeito colateral sobre tema vizinho, não pré-requisito.

### `contrato-de-veredito-de-uma-linha-no-revisar` (plantada)

- cita `reprovado-sem-diff-deixa-achado-auto-relatado` (plantada) — **irma**
  - (`descricao`) "oncreto e ja tem ideia irma aberta: hoje o `revisar` devolve parecer em prosa, e a ideia `reprovado-sem-diff-deixa-achado-auto-relatado` registra que fechar `revisar` como reprovado nao exige diff, entao o achados: N fica tao"
  - (`gancho`) "lhar se deu para registrar o veredito sem reler a prosa. Ou, antes disso, quando a ideia `reprovado-sem-diff-deixa-achado-auto-relatado` for colhida, porque as duas mexem no mesmo ponto."
  - Porquê: o próprio texto diz 'já tem ideia irmã aberta'; o gancho oferece um segundo gatilho independente ('na próxima vez que um revisar fechar reprovado'), então esta não fica presa a esperar a outra.

### `so-tres-eventos-honram-additionalcontext-o-resto-e-systemmessage` (plantada)

- cita `trazer-a-memoria-pra-dentro-do-rainforest` (plantada) — **outro**
  - (`gancho`) "Na proxima vez que o payload do SessionStart for mexido -- ou quando a ideia `trazer-a-memoria-pra-dentro-do-rainforest` for colhida, porque ela vai escolher por onde a memoria entra e essa escolha depende des"
  - Porquê: o texto diz que é a ESCOLHA da outra ideia que 'depende deste fato' — direção invertida: não é esta que espera a outra, e por isso não vira depende_de nesta ficha (a dependência real, se existir, seria da outra idea para esta).

### `obs-arqueologo-em-repo-de-terceiro-antes-de-avaliar` (plantada)

- cita `obs-arqueologia-antes-de-explorar-a-mao` (colhida) — **outro**
  - (`descricao`) "logo neles e dpois avaliar, seria mais completo'. E a SEGUNDA vez que ele faz esse corte: obs-arqueologia-antes-de-explorar-a-mao (2026-08-23, sessao do Sabia) diz a mesma coisa, e foi colhida em 25/08 como 'ja coberta'"
  - Porquê: 'foi colhida em 25/08 como já coberta' é precedente de ideia colhida, não bloqueio.

### `sonda-de-drift-do-mapa-por-stat-e-hash` (plantada)

- cita `mapa-que-ninguem-confere-envelhece-em-silencio` (plantada) — **irma**
  - (`descricao`) "ft em 2026-09-01, veredito Instalar -> Enxertar: enxerta. O defeito que ele resolve e o [[mapa-que-ninguem-confere-envelhece-em-silencio]]: hoje o mapa em docs/rainforest/mapas/ so envelhece, e nada avisa. O Graft nao usa flag"
  - Porquê: 'o defeito que ele resolve é [[id]]' aponta sobreposição de tema/solução, não uma espera — as duas podem avançar juntas ou se absorver.

### `memo-de-hash-com-tres-estados-pendente-pronto-velho` (plantada)

- cita `skill-advpl-graph-grafo-de-conhecimento` (plantada) — **irma**
  - (`descricao`) "EXATAMENTE o modo incremental por hash que ficou pendente no prototipo advpl-graph, ver [[skill-advpl-graph-grafo-de-conhecimento]], cujo ao_colher diz que o primeiro passo e empacotar como skill com modo incremental po"
  - (`ao_colher`) "Ler [[skill-advpl-graph-grafo-de-conhecimento]] junto - este mecanismo e a resposta ao primeiro passo declarado la. Nao esquecer o stam"
  - Porquê: 'este mecanismo é a resposta ao primeiro passo declarado lá' descreve peças complementares para ler juntas, não uma espera de uma pela outra.

- cita `sonda-de-drift-do-mapa-por-stat-e-hash` (plantada) — **irma**
  - (`contexto`) "2026-09-01 - mesma avaliacao de [[sonda-de-drift-do-mapa-por-stat-e-hash]]. Graft e MIT."
  - Porquê: 'mesma avaliação de [[id]]' — nasceram da mesma leitura de repositório no mesmo dia, irmãs de origem.

### `escada-de-confianca-derivada-da-estrategia` (plantada)

- cita `lacuna-declarada-por-maquina-no-mapa` (plantada) — **irma**
  - (`ao_colher`) "do piso o fato NAO ENTRA no mapa, em vez de entrar rotulado como fraco. Fazer junto com [[lacuna-declarada-por-maquina-no-mapa]], que mexe no mesmo formato."
  - Porquê: 'fazer junto com [[id]], as duas mexem no mesmo formato' é sugestão de execução conjunta, não pré-requisito.

### `lacuna-declarada-por-maquina-no-mapa` (plantada)

- cita `arqueologia-e-o-estagio-zero-que-falta-na-esteira` (colhida) — **outro**
  - (`contexto`) "- mesma avaliacao de [[escada-de-confianca-derivada-da-estrategia]]. Casa com a ancora [[arqueologia-e-o-estagio-zero-que-falta-na-esteira]]."
  - Porquê: 'casa com a âncora [[id]]' é referência de encaixe temático a ideia colhida, não bloqueio.

- cita `escada-de-confianca-derivada-da-estrategia` (plantada) — **irma**
  - (`contexto`) "2026-09-01 - mesma avaliacao de [[escada-de-confianca-derivada-da-estrategia]]. Casa com a ancora [[arqueologia-e-o-estagio-zero-que-falta-na-esteira]]."
  - (`gancho`) "Junto com [[escada-de-confianca-derivada-da-estrategia]] - as duas mexem no mesmo formato de mapa e no mesmo COBERTURA.md, fazer separado e mexe"
  - Porquê: 'junto com [[id]]... fazer separado mexeria duas vezes' — mesma relação de execução conjunta do item espelhado acima.

### `verbo-reaproveitado-ancora-a-leitura` (plantada)

- cita `menu-de-opcoes-quando-ele-pediu-conversa` (plantada) — **irma**
  - (`contexto`) "Caso 1: 2026-08-11 a noite, sessao do rainforest-mind; parente de menu-de-opcoes-quando-ele-pediu-conversa, mas a causa e outra — la o menu substituiu conversa, aqui o vocabulario interno do proje"
  - Porquê: o próprio texto diz 'parente de [[id]], mas a causa é outra'.

### `obs-2026-09-04-parser-de-shell-a-mao-troca-um-falso-positivo-por-outro` (plantada)

- cita `obs-2026-09-04-criterio-de-trava-precisa-de-contorno` (plantada) — **irma**
  - (`ao_colher`) "egex) — porque ali o conjunto de contraexemplos nao fecha. Conferir antes se a observacao obs-2026-09-04-criterio-de-trava-precisa-de-contorno ja cobre (a); se cobrir, esta aqui acrescenta so (b) e a proibicao de diagnostico fabrica"
  - Porquê: 'conferir antes se a observação X já cobre' é aviso para evitar duplicar trabalho, não uma espera obrigatória.

### `grupo-fiap-sem-rodape-assistente` (plantada)

- cita `grupo-fiap-mensagem-em-blocos` (plantada) — **irma**
  - (`contexto`) "cidida em sessao anterior e nao estava gravada em lugar que a sessao nova lesse — a ideia grupo-fiap-mensagem-em-blocos fala so de blocos."
  - (`ao_colher`) "cecoes por destinatario' listando o grupo FIAP como canal sem rodape, e atualizar a ideia grupo-fiap-mensagem-em-blocos para citar a excecao."
  - Porquê: esta ideia usa o ao_colher para propor atualizar a outra ('atualizar a ideia X para citar a exceção') — ação sobre uma irmã do mesmo canal, não espera por ela.

### `sabia-trava-permanente-contra-segredo` (plantada)

- cita `sabia-gitleaks-no-historico-antes-de-abrir` (colhida) — **outro**
  - (`contexto`) "durante a esteira 2026-09-07-sabia-gitleaks-e-caminho-feliz-do-narrar, que colheu a ideia sabia-gitleaks-no-historico-antes-de-abrir. O design daquela esteira registra esta ideia na secao 'Fora de escopo' com o motivo: a e"
  - Porquê: o próprio título diz 'agora que a varredura única já passou' — a varredura (ideia citada) está colhida, então a pré-condição já se cumpriu.

### `sabia-pico-de-ram-sem-guarda-no-codigo` (plantada)

- cita `sabia-boca-de-url-o-que-nunca-foi-medido` (plantada) — **irma**
  - (`contexto`) "6-09-08: nenhuma ideia existia sobre isso, e o codigo segue sem guarda. Separada da ideia sabia-boca-de-url-o-que-nunca-foi-medido de proposito: aquelas sao medicoes de rede, esta e risco de a maquina travar no meio de u"
  - Porquê: 'separada de X de propósito: aquelas são medições de rede, esta é risco de travar' — separação deliberada de escopo entre abertas.

### `whatsapp-mensagem-de-voz-em-nome-do-luis` (plantada)

- cita `pilha-de-voz-local-voicestudio` (colhida) — **outro**
  - (`descricao`) "Ultimo pedaco da metade (B) da [[pilha-de-voz-local-voicestudio]] que continua fora. O que ja existe: o Sabia gera fala local com sherpa-onnx (vits-piper"
  - (`contexto`) "Plantada em 2026-09-08, ao colher a [[pilha-de-voz-local-voicestudio]] depois de 20 dias em colheita. O design de 2026-08-23 do Sabia ja tinha empurrado este"
  - Porquê: esta ideia nasceu como o 'último pedaço' deixado de fora ao colher a outra — a ideia-mãe já está colhida, então o corte de escopo já aconteceu, não é espera.

### `sabia-comparar-parakeet-com-whisper-no-mesmo-audio` (plantada)

- cita `pilha-de-voz-local-voicestudio` (colhida) — **outro**
  - (`descricao`) "Medicao registrada no andamento da [[pilha-de-voz-local-voicestudio]] como 'plantada e nao feita' -- e que nunca teve linha propria no acervo ate 2026-09-08."
  - (`contexto`) "Plantada em 2026-09-08, ao colher a [[pilha-de-voz-local-voicestudio]]. O Sabia hoje roda whisper.cpp large-v3-turbo, medido em 23x tempo real com CUDA na tra"
  - Porquê: mesmo padrão: plantada 'ao colher' a ideia-mãe, que já está colhida — recorte de escopo já resolvido.

### `sabia-cadastrar-vozes-com-amostra-presencial` (plantada)

- cita `pilha-de-voz-local-voicestudio` (colhida) — **outro**
  - (`descricao`) "Teto medido em 2026-08-20 e registrado no andamento da [[pilha-de-voz-local-voicestudio]]: na gravacao presencial daquele dia, 40% das falas ficaram sem lado atribuido, e so Lui"
  - (`contexto`) "Plantada em 2026-09-08, ao colher a [[pilha-de-voz-local-voicestudio]]. Conecta com [[sabia-refazer-so-um-estagio-depois-de-resolver-a-parada]]: cadastrar a v"
  - Porquê: mesmo padrão de recorte plantado 'ao colher' a ideia-mãe, já colhida.

- cita `sabia-refazer-so-um-estagio-depois-de-resolver-a-parada` (plantada) — **irma**
  - (`contexto`) "Plantada em 2026-09-08, ao colher a [[pilha-de-voz-local-voicestudio]]. Conecta com [[sabia-refazer-so-um-estagio-depois-de-resolver-a-parada]]: cadastrar a voz que estava ambigua e exatamente a acao que invalida a parada do identi"
  - Porquê: 'conecta com [[id]]: cadastrar a voz... é exatamente a ação que invalida a parada' descreve efeito cruzado entre abertas, não uma espera de uma pela outra.

### `obs-2026-09-08-worktree-de-agente-nasceu-na-main-e-o-plano-nao-estava-la` (plantada)

- cita `obs-2026-09-08-agente-instalou-pacote-com-a-proibicao-no-briefing` (plantada) — **irma**
  - (`contexto`) "Segunda violacao de briefing pelo mesmo despacho, no mesmo dia: a primeira foi [[obs-2026-09-08-agente-instalou-pacote-com-a-proibicao-no-briefing]], em que o mesmo agente instalou psutil no venv com 'Nao instale nada' escrito duas veze"
  - Porquê: 'segunda violação de briefing pelo mesmo despacho, no mesmo dia: a primeira foi [[id]]' — observações irmãs do mesmo incidente, sem ordem de bloqueio.

### `obs-2026-09-08-catraca-de-mutacao-satisfeita-por-teste-que-le-o-fonte` (plantada)

- cita `prova-real-que-mede-outro-portao` (plantada) — **irma**
  - (`contexto`) "ue ninguem verifica; esta e sobre verificacao que passa pelo motivo errado. Conecta com [[prova-real-que-mede-outro-portao]] e com o incidente de 2026-08-21 ja citado na skill executar (49/49 verde com a trava re"
  - Porquê: 'conecta com [[id]] e com o incidente de 2026-08-21' é agrupamento temático, não espera.

- cita `obs-2026-09-08-agente-instalou-pacote-com-a-proibicao-no-briefing` (plantada) — **irma**
  - (`contexto`) "egracao da tarefa 2 da guarda de RAM. Terceira observacao do dia sobre a mesma familia: [[obs-2026-09-08-agente-instalou-pacote-com-a-proibicao-no-briefing]] e [[obs-2026-09-08-worktree-de-agente-nasceu-na-main-e-o-plano-nao-estava-la]] sao sobr"
  - Porquê: 'terceira observação do dia sobre a mesma família' agrupa três observações irmãs do mesmo dia.

- cita `obs-2026-09-08-worktree-de-agente-nasceu-na-main-e-o-plano-nao-estava-la` (plantada) — **irma**
  - (`contexto`) "mesma familia: [[obs-2026-09-08-agente-instalou-pacote-com-a-proibicao-no-briefing]] e [[obs-2026-09-08-worktree-de-agente-nasceu-na-main-e-o-plano-nao-estava-la]] sao sobre instrucao que ninguem verifica; esta e sobre verificacao que passa pelo motiv"
  - Porquê: mesma família de observações do mesmo dia, sem ordem declarada.

### `consultar-rainforest-antes-de-desenhar` (plantada)

- cita `replicador-dependencias-cascata` (plantada) — **irma**
  - (`descricao`) "gistrada no rainforest, da uma olhada antes'. Havia cinco registros relevantes. Um deles, replicador-dependencias-cascata (plantada 06/08), tinha ao_colher explicito mandando passar pelo brainstorm ANTES de qual"
  - Porquê: cita como um dos 'cinco registros relevantes' encontrados no mutirão que motivou esta observação — exemplo, não pré-requisito.

- cita `codigoexistedestino-seek-por-prefixo` (plantada) — **irma**
  - (`descricao`) "ia passado batido. Outras duas ideias eram defeitos tecnicos que o design encosta direto: codigoexistedestino-seek-por-prefixo, que e justamente o metodo que a conferencia ia usar, e replicar-fku-grid-fou-linhas-fixa"
  - Porquê: mesmo uso como exemplo de defeito técnico que o design 'encosta direto', não bloqueio.

- cita `replicar-fku-grid-fou-linhas-fixas` (plantada) — **irma**
  - (`descricao`) "igoexistedestino-seek-por-prefixo, que e justamente o metodo que a conferencia ia usar, e replicar-fku-grid-fou-linhas-fixas."
  - Porquê: mesmo uso como exemplo do mutirão que gerou a observação.

### `poda-verbatim-de-tool-calls-na-compaction` (plantada)

- cita `contrato-de-compressao-do-headroom-reimplementado` (plantada) — **irma**
  - (`contexto`) "r.md. Soma as ideias poda-de-resultado-com-invariante-de-convergencia (heuristica fixa) e contrato-de-compressao-do-headroom-reimplementado (proxy). Plantada por escolha do usuário."
  - Porquê: 'soma as ideias X (heurística fixa) e Y (proxy)' agrupa alternativas de projeto sendo comparadas, não uma espera.

- cita `poda-de-resultado-com-invariante-de-convergencia` (plantada) — **irma**
  - (`contexto`) "PR #319, relatorios/2026-09-23-fast-jev-e-laya-poda-por-classificador.md. Soma as ideias poda-de-resultado-com-invariante-de-convergencia (heuristica fixa) e contrato-de-compressao-do-headroom-reimplementado (proxy). Plantada p"
  - Porquê: mesma frase, mesmo agrupamento de alternativas.

### `obs-2026-09-23-avaliador-despachou-teammates-que-ficaram-no-roster` (plantada)

- cita `revisor-que-despacha-sub-revisores-nomeados` (plantada) — **irma**
  - (`descricao`) "roibia despachar subagente nem exigia encerrar o que abriu - mesma classe do incidente de revisor-que-despacha-sub-revisores-nomeados. Eu tambem nao conferi o ListAgents ao fechar a rodada."
  - Porquê: 'mesma classe do incidente de [[id]]' agrupa duas observações da mesma família de defeito.

### `rodar-relatorio-de-utilidade-da-memoria` (plantada)

- cita `memoria-sinal-de-utilidade-no-ranking` (plantada) — **outro**
  - (`ao_colher`) "essoes alguma observacao nao-servida pontua acima da melhor servida; abaixo disso a ideia memoria-sinal-de-utilidade-no-ranking fecha com o achado recencia basta."
  - Porquê: o texto diz que é a OUTRA ideia que fecha dependendo do resultado desta ('abaixo disso a ideia X fecha com o achado recência basta') — direção invertida: esta não espera a outra.

## Resumo das contagens

- Citações totais examinadas: 86 (55 ideias abertas, algumas citando mais de
  uma outra).
- `depende_de`: 1.
- `irma`: 45.
- `outro`: 40.
- 1 + 45 + 40 = 86.

## Premissas aceitas sem conferência extra

- O `commit-base` (`2622f1bd`) trazido no briefing bateu com `git log -1`
  depois do `git merge --ff-only`, conferido no início do trabalho.
- Aceitei sem conferir que o arquivo `~/.rainforest/ideias.jsonl` lido nesta
  sessão é a mesma cópia que qualquer outra sessão concorrente também lê e
  grava — não há trava de leitura durante a pesquisa (só a escrita usa
  `comTrava`), então uma edição concorrente durante a leitura teoricamente
  poderia produzir uma foto inconsistente; não tenho como confirmar que isso
  não aconteceu, só que os números batem internamente (55/86, com e sem
  variação do piso de tamanho do id).
- Aceitei que os campos listados como `string` em todos os 487 registros
  (`ao_colher`, `andamento`, quando não são `string`, são sempre `null`) são
  os únicos lugares onde uma citação em prosa poderia aparecer — não há
  campo adicional fora dos listados.
