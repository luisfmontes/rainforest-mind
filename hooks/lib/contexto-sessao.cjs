'use strict';
const fs = require('fs');
const path = require('path');
const { resolverRaiz } = require('./raiz.cjs');

/**
 * contexto-sessao.cjs — motor puro do SessionStart (foco-session-start.cjs).
 *
 * É PURO de propósito: entra TEXTO, sai TEXTO. Não lê arquivo, não escreve na tela,
 * não abre socket. Quem faz I/O é o adaptador (foco-session-start.cjs). A divisão é
 * a mesma do sonar-engine.cjs de um plugin interno de cliente, e existe pelo mesmo motivo: sem
 * ela, testar a injeção exige subir uma sessão de verdade — e o que não se testa
 * barato não se testa.
 *
 * UMA EXCEÇÃO, declarada (2026-08-21): `sessaoColocada` lê o `sessoes.json` da raiz
 * de dados. O motor puro dela é `sessoesColocadas`, que continua recebendo o estado
 * já parseado e é onde a bateria mede. A leitura mora aqui, e não no chamador, pelo
 * motivo que `hooks/heartbeat.cjs:12-20` já pagou: quando quem lê e quem escreve o
 * mesmo arquivo resolvem o caminho por conta própria, a divergência não aparece como
 * erro — aparece como dado que sumiu, em silêncio, e o radar cega inteiro. Esta é a
 * terceira peça a olhar esse arquivo; ela usa a MESMA `resolverRaiz` das outras duas.
 * Este comentário existe porque documentação que contradiz o arquivo em que mora é
 * pior que documentação ausente.
 *
 * Origem (2026-08-09): diff contra o session-context-lib.cjs de um plugin interno de cliente,
 * ancestral deste hook. Três coisas vieram de lá — teto mecânico de tamanho,
 * degradação barulhenta e a própria separação motor/adaptador.
 *
 * ORÇAMENTO DE ENTREGA (2026-08-10) — por que este arquivo tem um teto em bytes:
 * o harness limita o que ENTREGA ao modelo por hook. Passando do limite, ele grava
 * o stdout num arquivo, injeta um preview de ~2 KB e **sai com exit 0**, o que é
 * indistinguível de sucesso. Este hook emitia 32 KB e foi cortado a ~2,2 KB em
 * **50 de 50 sessões** desde o primeiro registro: as regras 4 a 17 nunca chegaram
 * a sessão nenhuma — inclusive a 14, que é a regra que mandaria anunciar isto.
 *
 * Medido nos transcripts (`python scripts/medir-injecao.py --entrega`):
 *   - 9.766 B de `additionalContext` entregues inteiros, zero truncados;
 *   - este hook era o ÚNICO emitindo texto cru; todos os outros emitem JSON e
 *     nenhum deles foi truncado.
 * Daí as duas metades do conserto: o adaptador emite JSON (`additionalContext`),
 * e o texto cabe num orçamento com folga sob o maior passe observado.
 */

/** Tetos. Mexer aqui muda o custo de TODA sessão — o número é a política. */
const TETOS = {
  /**
   * Teto do bloco "Avanços", em BYTES.
   *
   * Era contagem (`AVANCOS_RESIDENTES: 3`), calibrada em 2026-08-09 com entradas
   * de ~110 tokens. Em 2026-08-10 as entradas passaram a ter ~1,5 KB cada — o dia
   * rendeu e o registro acompanhou — e as mesmas 3 entradas viraram 2.271 B, mais
   * que o bloco de foco inteiro. Contagem não é teto quando o tamanho do item
   * varia 10x, e o pior é que nada avisa: a unidade do parâmetro (entradas) não é
   * a unidade do problema (bytes), então o número continua parecendo certo.
   */
  AVANCOS_MAX_BYTES: 900,
  /** Marcos AINDA DE PÉ que ficam residentes. Cumprido não entra em nenhum caso. */
  MARCOS_RESIDENTES: 2,
  /**
   * Teto do payload inteiro, em BYTES. 8.000 contra 9.766 B observados passando
   * inteiros — ~18% de folga. O limite exato do harness não é documentado; este
   * número é dimensionado para não depender de descobri-lo.
   */
  ORCAMENTO_BYTES: 8000,
  /**
   * Teto do bloco de REGRAS (só os núcleos), em BYTES. É um **catraca**, não uma
   * medida do harness: fica pouco acima do tamanho de hoje justamente para que
   * crescer doa na hora de escrever.
   *
   * Existe porque o `ORCAMENTO_BYTES` sozinho não dá retorno a quem edita regra.
   * As regras entram ANTES do foco (`sobra = ORCAMENTO - fixo`, e o foco leva o
   * que restar até `FOCO_MAX_BYTES`), então núcleo que engorda não estoura nada:
   * ele come em silêncio o espaço do foco, e o sintoma aparece longe da causa —
   * numa sessão futura, com o FOCO.md chegando mais pobre. O teste do orçamento
   * também não pega: ele roda com os dados de FIXTURE do repo (~6,3 KB) e não
   * com os dados reais de quem usa (7.924 B medidos em 2026-08-12, 76 B de folga).
   *
   * Quem quiser passar daqui paga por **subtração** — é a mesma regra que vale
   * para skill neste repo. Subir o número é decisão consciente e vem com a conta
   * escrita: cada byte a mais aqui é um byte a menos de FOCO.md em toda sessão.
   */
  NUCLEOS_MAX_BYTES: 5600,
  /**
   * Teto e piso do bloco de foco, em BYTES — a mesma unidade do orçamento.
   * Misturar as duas unidades é erro silencioso aqui: em português acentuado
   * 1 char ≈ 1,08 byte, então um teto em chars deixa o payload passar do teto
   * em bytes e a trava dispara sem ninguém entender por quê.
   */
  FOCO_MAX_BYTES: 2600,
  FOCO_MIN_BYTES: 700,
  /**
   * Teto do bloco de sessões paralelas, em BYTES. É o único bloco do payload que
   * cresce com o USO da máquina e não com o texto que alguém escreveu: em
   * 2026-08-10 o `sessoes.json` tinha 21 janelas vivas em 7 pastas, 1.373 B de
   * linhas — quase o dobro do piso do foco — e foi o que estourou o orçamento.
   * O corte precede a dedução por pasta, então este teto só morde numa máquina
   * com muitas pastas distintas abertas ao mesmo tempo.
   */
  SESSOES_MAX_BYTES: 300,
  /**
   * Quantas pastas o radar LISTA por nome. O resto vira contagem.
   *
   * A regra 17 pergunta duas coisas — "tem sessão paralela?" e "a janela do foco
   * esfriou?" — e as duas se respondem com as pastas mais RECENTES. Listar as oito
   * não responde melhor: em 2026-08-11 o bloco chegou a 691 B com 11 janelas e
   * empurrou os Marcos para fora da injeção; a entrega de sexta parou de chegar na
   * abertura por causa de `repo-de-trabalho` aparecendo três vezes.
   *
   * Contagem no lugar do nome mantém o sinal ("há trabalho paralelo") e devolve o
   * espaço ao foco, que é o que o usuario precisa ler.
   */
  SESSOES_PASTAS_LISTADAS: 3,
  /**
   * Piso do bloco de regras. Abaixo disto considera-se que NÃO carregou.
   * Não é `if (!regras)`: SKILL.md truncado ou heading renomeado produzem
   * bloco curto e não-vazio, e essa falha é tão grave quanto o vazio.
   */
  REGRAS_MIN_CHARS: 500,
  /**
   * Teto do MAIOR arquivo de `skills/rainforest-mind/references/`, em BYTES —
   * é o custo de CONSULTAR a elaboração de uma regra (D9, issue #73: "menos de
   * 3k tokens, medido"). 10.500 B equivalem a ~3,0k tokens. O maior arquivo
   * hoje é `regra-12.md`, com 8.884 B — **15% de folga**.
   *
   * A margem fica ESCRITA aqui, e não implícita, por dois incidentes desta
   * mesma semana com o mesmo formato: o `NUCLEOS_MAX_BYTES` abaixo chegou a
   * 7 B do teto sem ninguém perceber até virar a issue #79, e o teto agregado
   * do `orcamento.cjs` está estourado em +220 B na máquina do dono e verde no
   * CI (issue #81) — o mesmo tipo de descuido, de novo. Se esta margem cair
   * perto de zero, é hora de decidir encurtar `references/regra-NN.md` ou
   * subir o teto de propósito — nunca de deixar a folga sumir calada.
   */
  REFERENCE_MAX_BYTES: 10500,
  /**
   * Teto do `skills/rainforest-mind/SKILL.md` inteiro, em BYTES — é o custo de
   * carregar o ÍNDICE (núcleos + ponteiros) antes de decidir qual
   * `references/regra-NN.md` vale a pena abrir. Ele mede 9.535 B hoje, contra
   * este teto de 11.000 B — **13% de folga**.
   *
   * Mesma margem escrita, e não implícita, pelo mesmo motivo do
   * `REFERENCE_MAX_BYTES` acima: ver o comentário dele.
   */
  SKILL_MAX_BYTES: 11000,
};

/**
 * Incidente citado em blockquote sai da injeção e continua no arquivo, ao lado da
 * regra que ele fundamenta. Narrativa (o que aconteceu, quando, quem corrigiu) vai
 * pro blockquote; instrução nunca — se a frase diz o que fazer, ela fica residente.
 */
const CITACAO = /^>.*(?:\r?\n|$)/gm;

/** Início de uma entrada datada de "Avanços": `- 2026-08-09: ...` */
const ENTRADA_DATADA = /\n(?=- \d{4}-\d{2}-\d{2})/;

/**
 * Linha que o `scripts/foco.cjs` escreve no topo dos Avanços quando move entradas
 * antigas para o `AVANCOS.md`. Sem `g`: é usada com `.test()`, e regex global guarda
 * `lastIndex` entre chamadas — testar a mesma linha duas vezes daria `false` na segunda.
 */
const PONTEIRO_HISTORICO = /^- \(histórico:.*\)$/;

/** Início de uma regra numerada: `**7. Tom sênior.** ...` */
const INICIO_REGRA = /\n(?=\*\*\d+\.)/;

/** Linha que separa o núcleo da regra da sua elaboração. */
const MARCA_DETALHE = /^<!--\s*detalhe\s*-->[ \t]*$/m;

/** Seções do FOCO.md que ficam residentes. O resto vira ponteiro. */
const SECOES_RESIDENTES = ['Ativo', 'Compromissos com prazo'];

/** Extrai o bloco de regras do SKILL.md e remove as citações. */
function filtrarRegras(skillText) {
  // CRLF -> LF ANTES de qualquer coisa. Nao e cosmetica: no Windows o
  // `core.autocrlf=true` (padrao) reescreve o SKILL.md no checkout, e cada linha
  // ganha um `\r` que vai inteiro para dentro da injecao de TODA sessao. Em
  // 2026-08-13 o arquivo voltou de um merge com 827 CRLF, e 56 desses bytes
  // caiam dentro dos nucleos — a catraca acusou 5648 B onde o autor tinha
  // medido 5592 B, sem uma linha de regra ter mudado. Pior que o teto: o mesmo
  // commit custava bytes diferentes em maquinas diferentes, e ninguem via.
  // `\r` na injecao nao carrega significado nenhum; e desperdicio puro.
  const texto = String(skillText || '').replace(/\r\n/g, '\n');
  const bruto = (texto.split('## As regras')[1] || '').split('## Comando')[0] || '';
  return bruto.replace(CITACAO, '').replace(/\n{3,}/g, '\n\n').trim();
}

/**
 * Reduz cada regra ao seu NÚCLEO — o texto antes da linha `<!-- detalhe -->`.
 *
 * A elaboração continua no SKILL.md e se carrega sob demanda com `Skill`. A regra
 * cujo detalhe foi deixado de fora ganha `↳` no fim, e o cabeçalho da injeção diz
 * o que a marca significa: sem isso, uma regra pela metade **parece completa**, que
 * é pior que ausente — foi exatamente o que aconteceu com a regra 3 durante 50
 * sessões, cortada no meio da frase por um corte que ninguém anunciava.
 *
 * Regra sem a marca é injetada inteira (é curta o bastante para caber). Isso mantém
 * o arquivo válido enquanto regras novas ainda não foram divididas.
 */
function extrairNucleo(regrasTexto) {
  return String(regrasTexto || '')
    .split(INICIO_REGRA)
    .map((bloco) => {
      const corte = bloco.search(MARCA_DETALHE);
      if (corte === -1) return bloco.trim();
      const nucleo = bloco.slice(0, corte).trim();
      return nucleo ? `${nucleo} ↳` : '';
    })
    .filter(Boolean)
    .join('\n\n');
}

/**
 * Bloco de regras com degradação BARULHENTA.
 *
 * O hook antigo imprimia o cabeçalho seguido de nada quando o SKILL.md não era
 * legível: a sessão subia sem regra nenhuma e ninguém ficava sabendo. O próprio
 * texto injetado dizia "silêncio faz o usuario acreditar que a regra rodou" — e o
 * hook cometia exatamente essa falha. Reproduzido em 2026-08-09 rodando o hook
 * com RFM_ROOT numa pasta vazia.
 */
function blocoRegras(regras, caminhoSkill) {
  const texto = String(regras || '').trim();
  if (texto.length >= TETOS.REGRAS_MIN_CHARS) return texto;

  const diagnostico = texto.length === 0
    ? 'o arquivo não foi lido, ou não tem a seção `## As regras`'
    : `só ${texto.length} caracteres foram extraídos (piso: ${TETOS.REGRAS_MIN_CHARS}) — arquivo truncado ou heading renomeado`;

  return [
    '⚠️ **FALHA AO CARREGAR AS REGRAS — esta sessão está SEM o rainforest-mind.**',
    '',
    `Origem esperada: \`${caminhoSkill}\``,
    `Diagnóstico: ${diagnostico}.`,
    '',
    'Nenhuma regra numerada está valendo nesta sessão: nem responder tudo na ordem,',
    'nem o radar de escopo, nem os guarda-corpos de agente e de jornada.',
    '',
    '**Diga isto ao usuario na primeira resposta do turno, antes de qualquer trabalho.**',
    'Não trabalhe como se as regras estivessem ativas — elas não estão.',
  ].join('\n');
}

/**
 * Mantém residentes os avanços mais recentes que cabem num teto de BYTES, e troca o
 * resto por um ponteiro explícito. Nada se perde: o arquivo continua inteiro em disco.
 *
 * Motivo (medido em 2026-08-09): "Avanços" era 42% do FOCO.md, append-only e sem
 * teto. Num projeto de 3 meses ultrapassaria o bloco de regras inteiro. É o mesmo
 * movimento do filtro de citação, agora no FOCO.
 *
 * O teto era em ENTRADAS até 2026-08-10, e a diferença não é cosmética: entrada de
 * avanço não tem tamanho fixo. Três entradas de ~110 tokens custavam ~350 B; três
 * entradas de um dia produtivo custaram 2.271 B, e o parâmetro continuou dizendo
 * "3" o tempo todo. Teto na unidade errada não avisa quando para de valer.
 */
function resumirAvancos(focoText, maxBytes = TETOS.AVANCOS_MAX_BYTES) {
  const foco = String(focoText || '');
  const marcador = '\nAvanços:';
  const inicio = foco.indexOf(marcador);
  if (inicio === -1) return foco;

  const corpoInicio = inicio + marcador.length;
  const resto = foco.slice(corpoInicio);
  const fim = resto.search(/\n## /);
  const corpo = fim === -1 ? resto : resto.slice(0, fim);
  const cauda = fim === -1 ? '' : resto.slice(fim);

  // A linha de histórico (escrita pelo `scripts/foco.cjs`) é residente e não conta
  // como entrada omitida. Sem isso o ponteiro daqui — "elas continuam no FOCO.md" —
  // vira afirmação FALSA no dia em que a rotação tira entrada do arquivo: quem lesse
  // o FOCO.md inteiro atrás delas não acharia, e não saberia que existe AVANCOS.md.
  const todas = corpo.split(ENTRADA_DATADA).map((e) => e.trim()).filter(Boolean);
  const historico = todas.find((e) => PONTEIRO_HISTORICO.test(e)) || null;
  const entradas = todas.filter((e) => e !== historico);
  if (Buffer.byteLength(corpo, 'utf8') <= maxBytes) return foco;

  // Do mais recente para o mais antigo, enquanto couber. Pelo menos uma entrada
  // fica sempre: "Avanços:" com ponteiro e nada embaixo esconde a data que a
  // regra 3 usa para ver foco parado, e o iparAvancoRecente depende dela.
  const mantidas = [];
  let usado = 0;
  for (const entrada of [...entradas].reverse()) {
    const custo = Buffer.byteLength(entrada, 'utf8') + 1;
    if (mantidas.length && usado + custo > maxBytes) break;
    mantidas.unshift(entrada);
    usado += custo;
  }

  const ocultas = entradas.length - mantidas.length;
  if (!ocultas && !historico) return foco;
  const ponteiro = ocultas
    ? `- (${ocultas} ${ocultas === 1 ? 'entrada anterior' : 'entradas anteriores'} ` +
      `${ocultas === 1 ? 'foi omitida' : 'foram omitidas'} desta injeção para conter o custo por sessão. ` +
      'Elas continuam no FOCO.md — **leia o arquivo antes de afirmar o que já foi decidido ou feito neste foco**.)'
    : null;

  return foco.slice(0, corpoInicio) + '\n' +
    [historico, ponteiro, ...mantidas].filter(Boolean).join('\n') + cauda;
}

/**
 * Mantém residentes só os marcos que ainda estão de pé, e os PRÓXIMOS.
 *
 * Marco cumprido já cumpriu sua função: a regra 3 mede contra prazo **vencido ou a
 * ≤2 dias**, e nenhum marco com ✅ pode disparar isso. Injetar os cinco custava 641 B
 * — mais que a sobra inteira do bloco de foco — e o efeito medido em 2026-08-10 era
 * o pior possível: o bloco não cabia, saía inteiro, e a sessão subia sem prazo
 * nenhum. Dois marcos de pé custam ~260 B e respondem a pergunta que a regra faz.
 *
 * O cabeçalho do bloco fica sempre: é ele que diz que a data é a REUNIÃO e que a
 * entrega vence antes. Marco sem essa regra de leitura vira prazo errado por 1 dia.
 */
function resumirMarcos(secao, mantidos = TETOS.MARCOS_RESIDENTES) {
  const texto = String(secao);
  const inicio = texto.search(/^Marcos/m);
  if (inicio === -1) return texto;

  const resto = texto.slice(inicio);
  const fimRelativo = resto.search(/\n\n/);
  const bloco = fimRelativo === -1 ? resto : resto.slice(0, fimRelativo);
  const cauda = fimRelativo === -1 ? '' : resto.slice(fimRelativo);

  const partes = bloco.split(/\n(?=- )/);
  const cabecalho = partes.shift();
  const cumpridos = partes.filter((m) => m.includes('✅'));
  const dePe = partes.filter((m) => !m.includes('✅'));
  if (!cumpridos.length && dePe.length <= mantidos) return texto;

  const residentes = dePe.slice(0, mantidos);
  const adiante = dePe.length - residentes.length;
  const nota = [];
  if (adiante) nota.push(`${adiante} marco${adiante > 1 ? 's' : ''} adiante`);
  if (cumpridos.length) nota.push(`${cumpridos.length} já cumprido${cumpridos.length > 1 ? 's' : ''}`);
  const ponteiro = nota.length ? `\n- (${nota.join(' e ')} — estão no FOCO.md.)` : '';

  return texto.slice(0, inicio) + [cabecalho, ...residentes].join('\n') + ponteiro + cauda;
}

/**
 * Iça a data do avanço mais recente para logo abaixo do cabeçalho da seção.
 *
 * O bloco de foco recebe a sobra do orçamento e é cortado pelo FIM quando não cabe
 * — e os "Avanços" moram no fim da seção Ativo, então eram a primeira coisa a
 * sumir. A data do último avanço não é decoração: a regra 3 avisa quando o foco
 * ativo está há 7+ dias sem avanço, e sem a data essa checagem não tem como rodar.
 * Uma linha no topo custa ~35 B e sobrevive a qualquer corte que preserve o
 * cabeçalho; o histórico completo continua no arquivo.
 */
function iparAvancoRecente(secao) {
  // Sem exigir o `:` colado na data: a entrada real escreve "- 2026-08-10 (tarde):"
  // e a versão anterior do padrão simplesmente não a via — some a linha inteira, e
  // com ela a checagem de foco parado da regra 3.
  const datas = (String(secao).match(/(?:^|\n)- (\d{4}-\d{2}-\d{2})/g) || [])
    .map((s) => s.trim().slice(2, 12))
    .sort();
  if (!datas.length) return secao;
  const cabecalho = secao.match(/^## .+$/m);
  if (!cabecalho) return secao;
  const corte = secao.indexOf(cabecalho[0]) + cabecalho[0].length;
  return `${secao.slice(0, corte)}\nÚltimo avanço datado: ${datas[datas.length - 1]}.${secao.slice(corte)}`;
}

/**
 * Mantém residentes só as seções do FOCO.md contra as quais a regra 3 mede, e
 * nomeia as que ficaram de fora.
 *
 * O critério sai da própria regra 3: o desvio se mede **só contra o foco ativo**, e
 * as frentes e concluídos existem para a troca ser barata, não para disparar aviso.
 * Injetá-los custava o orçamento de toda sessão para responder uma pergunta que
 * ninguém faz na abertura. O ponteiro nomeia o que saiu — omissão anunciada é
 * recuperável, omissão silenciosa vira afirmação errada sobre o que já foi decidido.
 */
function resumirFoco(focoText) {
  const texto = resumirAvancos(String(focoText || '')).trim();
  if (!texto) return '';

  const partes = texto.split(/\n(?=## )/);
  const mantidas = [];
  const omitidas = [];
  for (const parte of partes) {
    const cabecalho = parte.match(/^## (.+)$/m);
    if (!cabecalho || SECOES_RESIDENTES.includes(cabecalho[1].trim())) {
      mantidas.push(iparAvancoRecente(resumirMarcos(parte.trim())));
    } else {
      omitidas.push(cabecalho[1].trim());
    }
  }
  if (omitidas.length) {
    mantidas.push(`(Seções do FOCO.md omitidas desta injeção: ${omitidas.join(', ')}. ` +
      'Elas continuam no arquivo — **leia o FOCO.md antes de afirmar o que está fora de escopo, ' +
      'em que frente algo mora, ou o que já foi concluído**.)');
  }
  return mantidas.filter(Boolean).join('\n\n');
}

/**
 * Ordem de prioridade dos blocos do foco. O primeiro padrão que casa manda.
 *
 * Existe porque o corte do foco era por POSIÇÃO: o bloco recebia a sobra do
 * orçamento e era truncado de cima para baixo. Medido em 2026-08-10, isso parava
 * no meio do "Critério de pronto" — ou seja, **os marcos e prazos não chegavam a
 * sessão nenhuma**, que é exatamente contra o que a regra 3 mede. Cortar por
 * importância entrega prazo e marcos dentro dos mesmos bytes.
 *
 * Parágrafo que não casa com padrão nenhum cai no fim da fila de propósito: é o
 * lugar da prosa explicativa do arquivo, que documenta o formato do FOCO.md e não
 * diz nada sobre o que o usuario está entregando.
 */
const PRIORIDADE_FOCO = [
  { rank: 0, teste: (b) => /^#{1,2} /.test(b) || /^Último avanço datado:/.test(b) },
  { rank: 1, teste: (b) => /^\*\*/.test(b) },
  // Lista solta abaixo de um cabeçalho residente: sai junto com ele ou não sai.
  // Cabeçalho sem o conteúdo dele ("## Compromissos com prazo" e nada embaixo) lê
  // como "não há compromisso", que é afirmação — e pode ser falsa.
  // MARCOS TEM RANK PRÓPRIO, acima de qualquer outra lista. Prazo é o que mais
  // dói perder, e até 2026-08-11 ele empatava em rank 2 com toda lista solta: o
  // preenchimento é guloso, levou o `- (nenhum além do foco ativo)` de 30 B e
  // deixou os Marcos — com a entrega de sexta — fora da injeção. Empate resolvido
  // por ordem no arquivo não é prioridade, é acaso.
  // CONTEÚDO DE "Compromissos com prazo" ENTRA ANTES DOS MARCOS, e por construção:
  // compromisso datado é o prazo mais PRÓXIMO, marco é cronograma. A regra 3 diz que
  // prazo é o que mais dói perder, e em 2026-08-13 (00h) a conta ficou explícita — o
  // foco recebe o que as regras deixam (1.686 B de um orçamento de 8.000 com 5.513 de
  // núcleos), e o compromisso de hoje (456 B) e os Marcos (475 B) não cabem juntos.
  // Sem este rank, quem entrava era o bloco de cronograma e quem saía era a entrega
  // do dia — nomeada no ponteiro, mas fora da injeção.
  // ...mas só o compromisso que TEM DATA. Promover a seção inteira devolveria o
  // acidente de 11/08 por outra porta: o placeholder `- (nenhum além do foco ativo)`,
  // de 30 B, passaria na frente dos Marcos de novo. Compromisso com prazo sem data
  // não é prazo, e cai no rank de lista comum. Duas checagens da bateria (marco
  // sobrevive ao corte, marco vence a lista pequena) pegaram isso na hora.
  {
    rank: 1,
    teste: (b, secao) =>
      /^Compromissos com prazo/i.test(secao || '') &&
      /\d{4}-\d{2}-\d{2}|\d{1,2}\/\d{1,2}/.test(b),
  },
  { rank: 2, teste: (b) => /^Marcos/.test(b) },
  { rank: 3, teste: (b) => /^- /.test(b) },
  { rank: 4, teste: (b) => /^Avanços:/.test(b) || /^\(Seções do FOCO\.md omitidas/.test(b) },
];

/**
 * Nome curto do bloco, para o ponteiro de omissão. Curto de propósito: o ponteiro
 * disputa bytes com o conteúdo que ele está anunciando, e um ponteiro gordo tira
 * do foco justamente o espaço que faria o bloco caber.
 */
function nomeDoBloco(bloco) {
  const primeira = bloco.split('\n')[0].replace(/[*#`]/g, '').split(/[—(:]/)[0].trim();
  return primeira.length > 24 ? `${primeira.slice(0, 24)}…` : primeira;
}

/**
 * Corta a IDENTIDADE do foco ativo (o primeiro bloco `**...**` logo abaixo do
 * cabeçalho `## Ativo`) por DENTRO em vez de descartá-la inteira quando ela
 * sozinha não cabe no teto — Issue #63, medido em 2026-08-23.
 *
 * O primeiro parágrafo de "## Ativo" (título, natureza, projeto, pastas,
 * prioridade, prazo final, critério de pronto) chega a ~1,3 KB contra um teto
 * de ~1,2 KB. Ele é o bloco de MAIOR prioridade de conteúdo (rank 1) — e era
 * exatamente o que caía fora inteiro, com os ponteiros de rank 4 (bem mais
 * baratos) entrando no lugar dele. Não é estouro de orçamento: é composição.
 *
 * Preserva a PRIMEIRA linha (título — e é nela que a natureza `[trabalho]` ou
 * `[pessoal]` normalmente mora) e qualquer linha com data (prazo, o que a
 * regra 3 mede). O resto vira um aviso de corte; o FOCO.md continua inteiro em
 * disco.
 *
 * @param {string} bloco    texto do bloco de identidade
 * @param {number} maxBytes espaço disponível, em bytes
 * @returns {string} versão cortada que cabe em `maxBytes`, ou '' se nem a
 *   primeira linha coubesse
 */
function cortarIdentidade(bloco, maxBytes) {
  const linhas = String(bloco || '').split('\n');
  if (!linhas.length || !linhas[0].trim() || maxBytes <= 0) return '';

  const RE_ESSENCIAL = /\d{4}-\d{2}-\d{2}|\[(trabalho|pessoal)\]/;
  const essencial = [linhas[0]];
  for (let i = 1; i < linhas.length; i++) {
    if (RE_ESSENCIAL.test(linhas[i])) essencial.push(linhas[i]);
  }

  const cortou = essencial.length < linhas.length;
  const aviso = cortou ? '\n(identidade cortada por espaço — o restante está no FOCO.md.)' : '';
  const texto = essencial.join('\n') + aviso;
  if (Buffer.byteLength(texto, 'utf8') <= maxBytes) return texto;

  // Nem o essencial + aviso coube: corta bruto, SEM o aviso — ele custaria
  // exatamente o espaço que falta, e título pela metade é melhor que título
  // pela metade mais um aviso truncado no meio de uma palavra.
  return cortarBytes(essencial.join('\n'), maxBytes);
}

/**
 * Encaixa o foco no teto tirando os blocos MENOS importantes primeiro, e nomeando
 * o que saiu. A ordem original é preservada na saída — prioridade decide quem
 * fica, não onde fica.
 *
 * Só cai no truncamento linear quando nem o bloco de maior prioridade cabe: aí o
 * problema é de orçamento, não de escolha, e o aviso de corte do `limitarBytes` é
 * a informação certa.
 */
function priorizarFoco(focoResumido, teto) {
  const texto = String(focoResumido || '').trim();
  if (!texto || Buffer.byteLength(texto, 'utf8') <= teto) return texto;

  // O ponteiro das SEÇÕES omitidas sai da fila e passa a ser RESIDENTE.
  //
  // Ele tinha `rank: 4` — o mais baixo da tabela —, então era o PRIMEIRO bloco a
  // cair quando o teto apertava. E ele é o único aviso de que "Fora de escopo",
  // "Frentes" e "Concluídos" existem no arquivo: sem ele a sessão afirma escopo sem
  // saber que existe uma seção de escopo, que é a afirmação falsa mais barata que
  // este bloco pode produzir.
  //
  // Medido em 2026-08-12 (23h40): outra sessão escreveu um compromisso novo no
  // FOCO.md, o arquivo foi de 8.412 para 10.946 B, e a injeção passou a sair SEM o
  // ponteiro — `omitidas desta injeção: false`. O corte que anuncia o corte não pode
  // ser cortável, e é a mesma correção que o bloco de sessões já tinha: reserva para
  // o próprio ponteiro dentro do teto.
  const RE_PONTEIRO_SECOES = /^\(Seções do FOCO\.md omitidas/;
  const partes = texto.split(/\n{2,}/).map((b) => b.trim());
  const ponteiroSecoes = partes.find((b) => RE_PONTEIRO_SECOES.test(b)) || '';
  // A SEÇÃO de cada bloco entra na decisão de prioridade: "- Telas entregues até
  // 13/08" é um item de lista igual a qualquer outro se olhado sozinho, e é a seção
  // que diz que ele é um compromisso com prazo.
  let secaoAtual = '';
  // O primeiro bloco `**...**` logo abaixo de "## Ativo" é a IDENTIDADE do foco
  // (título, natureza, prazo...) — o único que ganha corte por dentro em vez de
  // descarte inteiro quando não cabe (Issue #63). `identidadeUsada` some ao
  // trocar de heading, para não marcar um segundo bloco em negrito da mesma
  // seção como se fosse a identidade.
  let identidadeUsada = false;
  const blocos = partes
    .filter((b) => !RE_PONTEIRO_SECOES.test(b))
    .map((b, ordem) => {
      if (/^#{1,2} /.test(b)) {
        secaoAtual = b.split('\n')[0].replace(/^#+\s*/, '').trim();
        identidadeUsada = false;
      }
      const regra = PRIORIDADE_FOCO.find((p) => p.teste(b, secaoAtual));
      const identidade = !identidadeUsada && secaoAtual === 'Ativo' && /^\*\*/.test(b);
      if (identidade) identidadeUsada = true;
      return { texto: b, ordem, rank: regra ? regra.rank : 9, secao: secaoAtual, identidade };
    });

  const fila = [...blocos].sort((a, b) => a.rank - b.rank || a.ordem - b.ordem);
  const mantidos = [];
  const fora = [];
  let usado = 0;
  // Reserva para o ponteiro de omissão: ele PRECISA caber, senão o corte vira
  // silencioso — a falha que este arquivo inteiro existe para não cometer. O
  // ponteiro das seções entra na reserva pelo tamanho REAL dele, porque ele é
  // texto já montado (o outro só existe depois de saber quem saiu).
  const reserva = 120 + (ponteiroSecoes ? Buffer.byteLength(ponteiroSecoes, 'utf8') + 2 : 0);
  // PRIORIDADE É ABSOLUTA: no primeiro bloco que não couber, para. Nada de rank
  // pior entra depois dele.
  //
  // O preenchimento era guloso — seguia procurando bloco pequeno que caiba —, e o
  // efeito medido em 2026-08-12 foi o pior possível: a prosa-meta de 180 B (rank 9,
  // texto sobre o FORMATO do arquivo) ficou, e o compromisso com prazo de HOJE, de
  // ~450 B e rank 3, saiu. É o mesmo acidente que já tinha criado o rank próprio dos
  // Marcos em 11/08, e ele volta sempre que um bloco importante é grande. Espaço que
  // sobra e não é usado é preço de prioridade honesta: o ponteiro nomeia o que saiu,
  // então nada disso é silencioso.
  for (const bloco of fila) {
    const custo = Buffer.byteLength(bloco.texto, 'utf8') + 2;
    if (fora.length === 0 && usado + custo <= teto - reserva) {
      mantidos.push(bloco);
      usado += custo;
    } else if (bloco.identidade && fora.length === 0) {
      // A identidade do foco ativo NUNCA é descartada inteira quando não cabe
      // — ela é cortada por DENTRO, preservando título, natureza e prazo
      // (Issue #63). Se nem o essencial couber, cai no `else` como qualquer
      // outro bloco que não coube.
      const espacoLivre = teto - reserva - usado;
      const cortado = cortarIdentidade(bloco.texto, espacoLivre);
      const custoCortado = cortado ? Buffer.byteLength(cortado, 'utf8') + 2 : Infinity;
      if (cortado && custoCortado <= espacoLivre) {
        mantidos.push({ ...bloco, texto: cortado });
        usado += custoCortado;
      } else {
        fora.push(bloco);
      }
    } else {
      fora.push(bloco);
    }
  }

  // CABEÇALHO NÃO FICA SEM O CONTEÚDO DELE. "## Compromissos com prazo" seguido de
  // nada lê como "não há compromisso", que é afirmação — e pode ser falsa: em
  // 2026-08-12 havia um prazo para o dia seguinte embaixo dele. A regra já estava
  // escrita no comentário da tabela de prioridade e nada a fazia valer.
  // Órfão é o cabeçalho cuja seção INTEIRA saiu — não o cabeçalho cujo bloco
  // seguinte saiu. A primeira versão desta regra usava o vizinho imediato e
  // derrubou `## Ativo` porque o bloco depois dele é a prosa-meta (rank 9): junto
  // com o cabeçalho foi embora a linha `Último avanço datado`, que mora nele. Duas
  // checagens da bateria pegaram isso na hora.
  const mantidosPorOrdem = new Set(mantidos.map((b) => b.ordem));
  const ehCabecalho = (b) => /^#{1,2} /.test(b.texto);
  for (const bloco of [...mantidos]) {
    if (!ehCabecalho(bloco)) continue;
    const daSecao = blocos.filter(
      (b) => b.ordem > bloco.ordem && !ehCabecalho(b) &&
        !blocos.some((h) => ehCabecalho(h) && h.ordem > bloco.ordem && h.ordem < b.ordem)
    );
    if (!daSecao.length) continue; // cabeçalho sem conteúdo próprio (o título)
    if (daSecao.some((b) => mantidosPorOrdem.has(b.ordem))) continue;
    mantidos.splice(mantidos.indexOf(bloco), 1);
    fora.push(bloco);
    mantidosPorOrdem.delete(bloco.ordem);
  }

  if (!mantidos.length) return limitarBytes(texto, teto, 'Foco');

  // A reserva é estimativa: o ponteiro só tem tamanho depois de saber QUEM saiu, e
  // quem sai depende do espaço. Em vez de adivinhar, monta o texto final e devolve
  // blocos até caber de verdade — a versão que confiava na estimativa passou 25 B
  // do teto e fez a trava de orçamento cortar o próprio ponteiro.
  const montar = () => {
    const so = [...mantidos].sort((a, b) => a.ordem - b.ordem).map((b) => b.texto).join('\n\n');
    // Residente: entra sempre, e antes do outro ponteiro. Os dois anunciam coisas
    // diferentes — este, as seções que o `resumirFoco` trocou por ponteiro; o de
    // baixo, os blocos que não couberam no teto.
    const corpo = ponteiroSecoes ? `${so}\n\n${ponteiroSecoes}` : so;
    if (!fora.length) return corpo;
    const nomes = fora.map((b) => nomeDoBloco(b.texto)).filter(Boolean);
    const mostrados = nomes.slice(0, 3).join('; ') + (nomes.length > 3 ? `; +${nomes.length - 3}` : '');
    return `${corpo}\n\n(Fora desta injeção por espaço: ${mostrados}. ` +
      '**Leia o FOCO.md** antes de afirmar prazo, marco ou avanço.)';
  };

  let saida = montar();
  while (Buffer.byteLength(saida, 'utf8') > teto && mantidos.length > 1) {
    // Devolve sempre o de MENOR prioridade entre os mantidos.
    mantidos.sort((a, b) => a.rank - b.rank || a.ordem - b.ordem);
    fora.push(mantidos.pop());
    saida = montar();
  }
  return Buffer.byteLength(saida, 'utf8') > teto ? limitarBytes(saida, teto, 'Foco') : saida;
}

/**
 * Descarta do estado as sessões cujo processo morreu, e devolve só as vivas.
 *
 * O `sessoes.json` não tinha noção de sessão ENCERRADA: guardava `cwd`,
 * `prompt_ts` e `stop_ts`, e fechar a janela não gerava evento nenhum. A última
 * linha de uma sessão morta ficava idêntica à de uma sessão viva e ociosa. Medido
 * em 2026-08-10: 3 `claude.exe` rodando de verdade contra 18 entradas contadas
 * como vivas na injeção — 15 fantasmas, e foi o que estourou o orçamento.
 *
 * O `SessionEnd` cobre o encerramento limpo; esta varredura cobre o resto (janela
 * fechada no X, crash, reboot), onde evento nenhum chega. Entrada sem `pid` é de
 * antes desta mudança e sobrevive pela idade — ela some sozinha em 24h.
 *
 * @param {object} state          conteúdo do sessoes.json
 * @param {number} agora          timestamp de referência
 * @param {number} janelaMs       idade máxima para a entrada contar
 * @param {(pid:number)=>boolean} vivo  predicado de vida (injetável no teste)
 */
/**
 * Sessão de SUBAGENTE, não janela do usuario.
 *
 * Subagente despachado com `isolation: "worktree"` abre sessão própria, com cwd
 * dentro de `.claude/worktrees/agent-...`. Ela entrava no radar como se fosse mais uma
 * janela paralela dele — e a regra 17 mede o paralelismo DELE, não o meu rastro.
 *
 * Dois danos, os dois medidos em 2026-08-11: o radar mentia sobre quantas
 * frentes ele tinha abertas, e o bloco de sessões disputa orçamento com o foco —
 * naquele dia a injeção chegou a 7992 B de 8000, com o radar em 676 B, e o prazo
 * mais próximo já tinha caído fora da injeção uma vez. Quanto mais eu despacho,
 * menos foco chegava.
 *
 * AJUSTE 2026-08-14: O filtro foi estreitado para exigir o prefixo `agent-` no
 * segmento imediatamente após `worktrees/`. A razão: o usuario pode ter worktrees
 * de seus próprios projetos (ex.: gestao-projetos-template) dentro de `.claude/worktrees/`,
 * e essas NÃO devem ser filtradas. Apenas worktrees criadas pelo harness
 * (nomeadas `agent-<hash>`) devem sair do radar. O teste exato é:
 * `/.../worktrees/agent-` — não substring, mas limite de segmento.
 */
function ehWorktreeDeAgente(cwd) {
  if (!cwd) return false;
  // Aceita barras normais (/) e invertidas (\), e exige que o segmento
  // imediatamente após "worktrees" comece com "agent-".
  return /[\\/]\.claude[\\/]worktrees[\\/]agent-/.test(cwd);
}

/**
 * Janela em que uma sessão ainda é DONA do `cwd` dela, em ms.
 *
 * Quatro horas, e é longo de propósito: dono de branch dura mais que atenção. Em
 * 2026-08-21 o usuario pausou a outra janela por um tempo, e ela continuou dona da
 * branch — uma janela de 15 min teria liberado o `git checkout` exatamente no
 * momento em que ele ia doer. Entrada PARADA (`stop_ts > prompt_ts`) conta igual.
 */
const JANELA_COLOCADA_MS = 4 * 3600 * 1000;

/**
 * Normaliza `cwd` para comparação por IGUALDADE. Nunca por prefixo.
 *
 * `\` vira `/` e tudo vira minúscula porque o mesmo diretório chega escrito das duas
 * formas no Windows — o harness manda `C:\Projetos\x`, o FOCO.md e os scripts mandam
 * `C:/Projetos/x`, e comparar cru trata os dois como pastas diferentes.
 */
function normalizarCwd(caminho) {
  if (!caminho) return '';
  const barras = String(caminho).replace(/\\/g, '/');
  return path.posix.normalize(barras).replace(/(?!^)\/+$/, '').toLowerCase();
}

/**
 * Motor puro: quais OUTRAS sessões estão no MESMO `cwd`, dentro da janela.
 *
 * O INCIDENTE (2026-08-21, Issues #25 e #38, 11 registros no acervo): duas janelas
 * abertas no mesmo diretório, um `git checkout -b` numa delas arrancou a OUTRA da
 * branch em que ela estava trabalhando — e ela commitou três vezes na branch alheia
 * sem saber. As duas vezes que isso aconteceu, o que as sessões tinham em comum era
 * o `cwd` idêntico, e é por isso que a medida é essa e não "mesmo repositório":
 * `git-common-dir` pegaria também quem está numa worktree própria, que é justamente
 * o comportamento que o método quer premiar, e trava que atrapalha vira trava
 * desligada.
 *
 * Vivacidade é SÓ TEMPO, e não é escolha de desenho: das 5 entradas reais do
 * `sessoes.json` em 2026-08-21, ZERO tinham `pid` — o filtro `!s.pid || estaVivo(s.pid)`
 * do `sessoesVivas` logo abaixo nunca dispara. Fingir que há checagem de processo
 * aqui seria descrever um mecanismo que não existe.
 *
 * @param {object} state          conteúdo do sessoes.json (objeto indexado por session_id)
 * @param {object} o
 * @param {string} o.cwd          diretório da sessão que está perguntando
 * @param {string} [o.sessionId]  session_id de quem pergunta — SEMPRE excluído do resultado
 * @param {number} [o.agora]      timestamp de referência (default: Date.now())
 * @param {number} [o.janelaMs]   janela de dono (default: JANELA_COLOCADA_MS)
 * @returns {Array<{session_id: string, cwd: string, ultimo_ts: number, parada: boolean}>}
 */
function sessoesColocadas(state, o = {}) {
  const alvo = normalizarCwd(o.cwd);
  if (!alvo) return [];
  const agora = Number.isFinite(o.agora) ? o.agora : Date.now();
  const janelaMs = Number.isFinite(o.janelaMs) ? o.janelaMs : JANELA_COLOCADA_MS;
  // Sem `session_id` no evento, quem pergunta não se distingue de quem está lá: as
  // duas entradas do incidente tinham `cwd` idêntico. O chamador é quem decide o que
  // fazer com isso (o gate libera, por fail-open); aqui só não se exclui ninguém.
  const eu = o.sessionId || '';

  return Object.entries(state || {})
    .filter(([id, s]) => id !== eu && s && s.cwd)
    // Worktree de subagente é rastro MEU, não janela dele — mesmo motivo pelo qual
    // ela já sai do radar da regra 17.
    .filter(([, s]) => !ehWorktreeDeAgente(s.cwd))
    .filter(([, s]) => normalizarCwd(s.cwd) === alvo)
    .map(([id, s]) => ({
      session_id: id,
      cwd: s.cwd,
      ultimo_ts: Math.max(s.prompt_ts || 0, s.stop_ts || 0),
      // Parada = o último evento foi o Claude terminando o turno. Continua dona.
      parada: (s.stop_ts || 0) > (s.prompt_ts || 0),
    }))
    .filter((s) => agora - s.ultimo_ts < janelaMs)
    .sort((a, b) => b.ultimo_ts - a.ultimo_ts);
}

/**
 * Adaptador: resolve a raiz de DADOS, lê o `sessoes.json` de lá e delega.
 *
 * A raiz sai da `resolverRaiz`, nunca de um `path.join` com a raiz do repositório —
 * é o tropeço de `hooks/heartbeat.cjs:12-20` repetido pela terceira vez. O
 * `sessoes.json` versionado no repo tem UMA entrada, de 2026-08-12, e não recebe
 * escrita há tempo nenhum: quem ler dele acha que nunca há sessão paralela, e a
 * trava fica verde para sempre sem nunca ter olhado o dado vivo.
 *
 * FALHA PARA O LADO DE LIBERAR: arquivo ausente, ilegível, JSON quebrado ou raiz não
 * resolvida devolvem lista vazia. É o mesmo princípio de fail-open que o gate já
 * aplica quando o git não responde — trava que barra por não conseguir medir é trava
 * que o usuário desliga no primeiro dia.
 */
function sessaoColocada(o = {}) {
  let state;
  try {
    const raiz = o.raiz || resolverRaiz({ cwd: o.cwd }).raiz;
    if (!raiz) return [];
    state = JSON.parse(fs.readFileSync(path.join(raiz, 'sessoes.json'), 'utf8'));
  } catch {
    return [];
  }
  return sessoesColocadas(state, o);
}

function sessoesVivas(state, agora, janelaMs, vivo) {
  const estaVivo = typeof vivo === 'function' ? vivo : processoVivo;
  return Object.entries(state || {})
    .filter(([, s]) => s && agora - Math.max(s.prompt_ts || 0, s.stop_ts || 0) < janelaMs)
    .filter(([, s]) => !s.pid || estaVivo(s.pid))
    .filter(([, s]) => !ehWorktreeDeAgente(s.cwd));
}

/** Existência de processo por PID. O sinal 0 não mata nada — só pergunta. */
function processoVivo(pid) {
  try {
    process.kill(pid, 0);
    return true;
  } catch (e) {
    // EPERM = existe e é de outro usuário. Só ESRCH prova que morreu.
    return e && e.code === 'EPERM';
  }
}

/**
 * Reduz o radar multi-janela a UMA linha por pasta, e cabe num teto.
 *
 * A regra 17 pergunta duas coisas por PASTA — "tem sessão paralela aqui?" e "a
 * janela do foco esfriou?" —, e as duas se respondem com a janela mais recente
 * daquela pasta. Nove linhas da mesma pasta em ordem qualquer não respondem
 * melhor: custam 9x e ainda enterram as outras pastas no fim do bloco, que é
 * exatamente onde o corte do orçamento cai.
 *
 * Foi este bloco que estourou a injeção de 2026-08-10 (8.306 B para um teto de
 * 8.000): 21 janelas vivas, 7 pastas. Ele é o único pedaço do payload que cresce
 * com quantas janelas o usuario abriu no dia — os outros crescem com texto escrito,
 * que alguém revisa; este ninguém revisa.
 *
 * @param {Array<{cwd?: string, trabalhando?: boolean, minutos?: number}>} entradas
 * @param {string} ociosidade minutos de ociosidade máxima do foco ativo
 * @param {string} [cwdAtual] cwd da sessão atual para marcar linhas co-locadas
 */
function resumirSessoes(entradas, ociosidade, teto = TETOS.SESSOES_MAX_BYTES, cwdAtual) {
  const lista = Array.isArray(entradas) ? entradas.filter(Boolean) : [];
  if (!lista.length) return '';

  const porPasta = new Map();
  for (const e of lista) {
    const pasta = e.cwd || '(pasta desconhecida)';
    const min = Number.isFinite(e.minutos) ? e.minutos : Infinity;
    const atual = porPasta.get(pasta);
    // Mais recente = menos minutos desde o último evento.
    if (!atual || min < atual.minutos) porPasta.set(pasta, { pasta, minutos: min, trabalhando: !!e.trabalhando, janelas: (atual ? atual.janelas : 0) + 1 });
    else porPasta.set(pasta, { ...atual, janelas: atual.janelas + 1 });
  }

  // Separar sessões co-locadas das remotas, se cwdAtual foi fornecido.
  const sessoesPorTipo = [...porPasta.values()].reduce((acc, p) => {
    if (cwdAtual && p.pasta === cwdAtual) {
      acc.colocadas.push(p);
    } else {
      acc.remotas.push(p);
    }
    return acc;
  }, { colocadas: [], remotas: [] });

  // Ordenar remotas por tempo. Colocadas ficam todas na frente, sem sort.
  sessoesPorTipo.remotas.sort((a, b) => a.minutos - b.minutos);

  const linhas = [...sessoesPorTipo.colocadas, ...sessoesPorTipo.remotas]
    .map((p) => {
      const estado = p.trabalhando
        ? `Claude trabalhando (turno em curso há ${p.minutos} min)`
        : `esperando o usuario há ${p.minutos} min`;
      const extras = p.janelas > 1 ? ` [${p.janelas} janelas nesta pasta; estado da mais recente]` : '';
      const marca = cwdAtual && p.pasta === cwdAtual ? 'MESMO DIRETORIO — git checkout aqui move o HEAD da janela dela · ' : '';
      return `- ${marca}${p.pasta} — ${estado}${extras}`;
    });

  // Corte em DOIS passos, e o primeiro é por quantidade, não por bytes.
  //
  // Só o teto de bytes deixava o bloco crescer até 691 B com 11 janelas — e o que
  // ele empurrava para fora era o foco, com os Marcos e o prazo mais próximo
  // dentro. Listar pasta fria não responde nenhuma das duas perguntas da regra 17
  // e custa exatamente o espaço de que o foco precisa.
  const listadas = linhas.slice(0, TETOS.SESSOES_PASTAS_LISTADAS);
  // Reserva para o ponteiro de omissão, quando ele for existir. Sem ela o teto
  // mente: as linhas cabiam em 300 B, o ponteiro entrava DEPOIS e o bloco saía
  // com 351. Parâmetro que não governa o número que ele nomeia é a mesma família
  // do teto em entradas que virou 2.271 B — o problema não é o valor, é a conta.
  const reserva = linhas.length > listadas.length ? 80 : 0;
  const cabidas = [];
  let usado = 0;
  for (const linha of listadas) {
    const custo = Buffer.byteLength(linha, 'utf8') + 1;
    if (usado + custo > teto - reserva) break;
    cabidas.push(linha);
    usado += custo;
  }
  // Pasta omitida em silêncio vira "não havia sessão lá", que é afirmação errada.
  // O que sai vira NÚMERO — o sinal "há trabalho paralelo" sobrevive ao corte.
  const fora = linhas.length - cabidas.length;
  if (fora) {
    const janelasFora = [...porPasta.values()]
      .sort((a, b) => a.minutos - b.minutos)
      .slice(cabidas.length)
      .reduce((n, p) => n + p.janelas, 0);
    cabidas.push(`- (+${janelasFora} janela(s) em ${fora} outra(s) pasta(s) — nomes no \`sessoes.json\`.)`);
  }

  return `\n## Outras sessões recentes (radar multi-janela, regra 17)\n${cabidas.join('\n')}\n` +
    `Ociosidade máxima deste foco: ${ociosidade} min.\n`;
}

/**
 * Um bloco de foco sem NENHUMA linha de conteúdo — só cabeçalho, "Último avanço
 * datado:" e/ou os dois ponteiros de omissão — é indistinguível de "não há foco
 * declarado" para quem lê, e pode ser uma afirmação FALSA (Issue #63, medido em
 * 2026-08-23: "## Ativo" saía removido por orfandade e só os ponteiros de espaço
 * sobravam, com um foco de prazo em dois dias por trás).
 */
function focoSoTemPonteiro(texto) {
  const linhas = String(texto || '').split('\n').map((l) => l.trim()).filter(Boolean);
  if (!linhas.length) return true;
  return linhas.every((l) =>
    /^#{1,2} /.test(l) ||
    /^Último avanço datado:/.test(l) ||
    /^\(Seções do FOCO\.md omitidas/.test(l) ||
    /^\(Fora desta injeção por espaço/.test(l));
}

/** Aviso explícito de foco que não coube — mesmo texto para o piso e para o caso pointer-only (Issue #63). */
function avisoFocoNaoCoube(tetoFoco) {
  return `⚠️ O foco não coube nesta injeção (${tetoFoco} B livres, piso ${TETOS.FOCO_MIN_BYTES} B).\n` +
    '**Leia o FOCO.md antes de medir desvio de escopo ou afirmar o que está em andamento** (regra 3).';
}

/** Teto duro, com aviso explícito de que houve corte. Nunca corta em silêncio. */
function limitar(texto, max, nomeDoBloco) {
  const s = String(texto || '');
  if (s.length <= max) return s;
  return s.slice(0, max).trimEnd() +
    `\n\n[${nomeDoBloco} truncado no teto de ${max} caracteres — o arquivo em disco está inteiro, leia-o se precisar do resto.]`;
}

/** Teto duro em BYTES, com aviso de corte que já cabe dentro do teto. */
function limitarBytes(texto, maxBytes, nomeDoBloco) {
  const s = String(texto || '');
  if (Buffer.byteLength(s, 'utf8') <= maxBytes) return s;
  const aviso = `\n\n[${nomeDoBloco} truncado no teto de ${maxBytes} bytes — o arquivo em disco está inteiro, leia-o se precisar do resto.]`;
  const espaco = Math.max(0, maxBytes - Buffer.byteLength(aviso, 'utf8'));
  return cortarBytes(s, espaco).trimEnd() + aviso;
}

/** Corta em `max` BYTES sem partir um caractere multibyte no meio. */
function cortarBytes(texto, max) {
  const s = String(texto || '');
  if (Buffer.byteLength(s, 'utf8') <= max) return s;
  let baixo = 0;
  let alto = s.length;
  while (baixo < alto) {
    const meio = Math.ceil((baixo + alto) / 2);
    if (Buffer.byteLength(s.slice(0, meio), 'utf8') <= max) baixo = meio;
    else alto = meio - 1;
  }
  return s.slice(0, baixo);
}

/**
 * Trava de orçamento: falha RUIDOSA quando o payload passa do teto.
 *
 * O aviso vai no TOPO, e a posição é o ponto todo. O corte do harness leva os
 * **primeiros** ~2 KB e descarta o resto — então rodapé não sobrevive a ele, e uma
 * salvaguarda escrita no fim do payload seria mais uma regra que nunca chega. Como
 * o corte próprio já traz o texto para dentro do orçamento, o aviso chega inteiro.
 *
 * Isto é o que faltava em 2026-08-10: o hook escrevia 32 KB, saía com exit 0, e
 * nada em lugar nenhum dizia que 93% do texto não tinha chegado.
 */
function travarOrcamento(payload, orcamento = TETOS.ORCAMENTO_BYTES) {
  const bytes = Buffer.byteLength(payload, 'utf8');
  if (bytes <= orcamento) return payload;

  const aviso = [
    `⚠️ **INJEÇÃO ACIMA DO ORÇAMENTO: ${bytes} B para um teto de ${orcamento} B.**`,
    '',
    'O texto abaixo foi cortado no FIM por este hook para caber na entrega do',
    'harness. O corte come de trás para frente: primeiro as dependências de',
    'ambiente e o radar de janelas, depois o foco, e só num estouro grande as',
    'últimas regras. **Nada do que foi cortado está valendo nesta sessão** — trate',
    'como bloqueio de ambiente (regra 14), diga isto ao usuario em uma linha, carregue',
    '`Skill(rainforest-mind)` antes de aplicar regra e leia o FOCO.md antes de medir',
    'escopo. Conserto: encurtar os núcleos no SKILL.md, apertar os tetos do rodapé',
    '(`SESSOES_MAX_BYTES`) ou revisar o orçamento aqui.',
    '',
    '---',
    '',
  ].join('\n');

  return aviso + cortarBytes(payload, Math.max(0, orcamento - Buffer.byteLength(aviso, 'utf8')));
}

/**
 * Monta o additionalContext. Recebe texto já lido pelo adaptador.
 *
 * A ordem de alocação importa: as regras têm custo fixo (são o contrato), e o foco
 * recebe **a sobra** do orçamento. O inverso — foco fixo, regras na sobra — é como
 * se chegou nas 50 sessões em que nenhuma regra passou da terceira.
 *
 * @param {object} o
 * @param {string} o.skillText      conteúdo do SKILL.md
 * @param {string} o.focoText       conteúdo do FOCO.md
 * @param {string} [o.caminhoSkill] caminho do SKILL.md, citado no diagnóstico de falha
 * @param {string} [o.root]         raiz dos arquivos de apoio
 * @param {string} [o.sessoes]      bloco do radar multi-janela
 * @param {string} [o.revisao]      aviso de revisão vencida
 * @param {string} [o.dependencias] bloco de dependências de ambiente
 */
function montarContexto(o) {
  const regras = blocoRegras(extrairNucleo(filtrarRegras(o.skillText)), o.caminhoSkill || '(caminho não informado)');
  const caminho = o.caminhoSkill || `${o.root || ''}\\skills\\rainforest-mind\\SKILL.md`;
  const pastaReferences = path.join(path.dirname(caminho), 'references').replace(/\\/g, '/');

  // O imóvel mais caro do payload é o começo: é o único pedaço que sobrevive a um
  // corte. Ele carrega a CONVOCAÇÃO, não a identidade — "quem eu sou" não faz nada
  // acontecer; "carregue a skill antes de aplicar a regra marcada" faz.
  const cabecalho = `RAINFOREST MIND ATIVO — memória de trabalho externa e radar de escopo do usuario (perfil 2e).

**Isto é o NÚCLEO das regras, não o texto completo.** Regra marcada com ↳ tem
elaboração que não está aqui — critérios finos, comandos exatos, incidentes.
**Antes de aplicar uma regra marcada, leia a elaboração:**
\`${pastaReferences}/regra-<n>.md\` (onde \`<n>\` é o número da regra).

## Regras (aplicar em toda resposta)
${regras}

## Foco declarado
`;

  // A separação é do rodapé, não dos blocos que ele recebe: quando não havia
  // sessão paralela, o `## Dependências` colava na última linha do foco e virava
  // continuação do texto dele. Normalizar aqui vale para qualquer combinação de
  // blocos presentes ou ausentes.
  const blocoRodape = [o.veredito, o.sessoes, o.revisao, o.dependencias]
    .filter(Boolean)
    .map((bloco) => String(bloco).replace(/^\n+/, '').trimEnd());
  blocoRodape.push(`Arquivos de apoio: ${o.root || ''}\\FOCO.md e ${o.root || ''}\\ideias.jsonl (uma ideia por linha)`);
  const rodape = '\n\n' + blocoRodape.join('\n\n');

  const fixo = Buffer.byteLength(cabecalho + rodape, 'utf8');
  const sobra = TETOS.ORCAMENTO_BYTES - fixo;
  const tetoFoco = Math.min(TETOS.FOCO_MAX_BYTES, Math.max(0, sobra));

  const focoResumido = resumirFoco(o.focoText).trim();
  let foco;
  if (!focoResumido) {
    foco = '(nenhum foco declarado — sugira /foco <texto> se o usuario disser no que precisa entregar)';
  } else if (tetoFoco < TETOS.FOCO_MIN_BYTES) {
    // Abaixo do piso, um excerto é pior que um ponteiro: sobrariam o título e o
    // cabeçalho, e o critério de pronto — que é contra o que a regra 3 mede —
    // ficaria de fora, com o bloco parecendo completo. O piso não vira alocação
    // forçada (isso estouraria o orçamento e faria a trava acusar as regras por um
    // defeito que é do foco); vira aviso.
    foco = avisoFocoNaoCoube(tetoFoco);
  } else {
    // Por prioridade, não por posição: cortar de cima para baixo deixava marcos e
    // prazos de fora de toda sessão enquanto a prosa do topo sobrevivia inteira.
    foco = priorizarFoco(focoResumido, tetoFoco);
    // Invariante (Issue #63): mesmo com teto acima do piso, a composição pode
    // deixar o bloco sem NENHUM conteúdo real (identidade cortada demais,
    // "## Ativo" removido por orfandade, só ponteiros sobrando) — o mesmo aviso
    // explícito do caso abaixo do piso vale aqui, em vez de um bloco que parece
    // completo e não é.
    if (focoSoTemPonteiro(foco)) foco = avisoFocoNaoCoube(tetoFoco);
  }

  return travarOrcamento(cabecalho + foco + rodape);
}

/**
 * Extrai a lista de pastas do campo "Pastas:" do FOCO.md.
 *
 * Precedente de extração por regex do FOCO.md (hooks/foco-session-start.cjs:196):
 * `Ociosidade máxima:\s*(\d+)\s*min`. Mesmo padrão aqui.
 *
 * O campo "Pastas:" é uma lista separada por vírgula (`Pastas: C:/a, C:/b`) OU a
 * primeira linha seguida de linhas de CONTINUAÇÃO indentadas — a forma que o
 * usuário usa quando a entrega tem mais de uma pasta:
 *   Pastas: C:/a
 *           C:/b
 *
 * Medido na Issue #63 (2026-08-23): com só a primeira linha extraída, a segunda
 * pasta ficava invisível em silêncio, e a isenção 1 (D6/regra 17) nunca disparava
 * para a sessão trabalhando ali — o radar cobrava desvio de escopo indevidamente.
 *
 * @param {string} textoDoFoco conteúdo do FOCO.md
 * @returns {string[]} array de caminhos aparados, ou [] se o campo não existe
 */
function pastasDoFoco(textoDoFoco) {
  const texto = String(textoDoFoco || '');
  const linhas = texto.split('\n');
  const idx = linhas.findIndex((l) => /^Pastas:/.test(l));
  if (idx === -1) return [];

  // `[ \t]*` (nunca `\s*`) entre os dois-pontos e o conteúdo da PRIMEIRA linha:
  // `\s` inclui quebra de linha, e um `Pastas:` seguido de linha em branco (a
  // forma exata que o `scripts/setup.cjs` semeia) atravessava para o próximo
  // heading não-vazio — `pastasDoFoco("Pastas:\n\n## Ativo\n")` devolvia
  // `["## Ativo"]` em vez de `[]`, e a isenção 1 (D6/regra 17) tratava isso
  // como pasta configurada de verdade. O GUARDA CONTINUA VALENDO: linha em
  // branco não é linha de continuação (não casa `/^[ \t]+\S/` abaixo), então
  // ela interrompe a busca antes de alcançar o próximo heading.
  const primeira = linhas[idx].replace(/^Pastas:[ \t]*/, '');
  const partes = [];
  if (primeira.trim()) partes.push(primeira);

  // Linhas de CONTINUAÇÃO: indentadas (começam com espaço/tab) e não vazias.
  // Para na primeira linha que não bate — em branco ou sem indentação (novo
  // heading, nova prosa) — para não atravessar seção, o mesmo cuidado do
  // guarda acima.
  for (let i = idx + 1; i < linhas.length; i++) {
    if (/^[ \t]+\S/.test(linhas[i])) partes.push(linhas[i]);
    else break;
  }

  if (!partes.length) return [];
  return partes.join(',').split(',').map((s) => s.trim()).filter(Boolean);
}

/**
 * Decide se um timestamp cai dentro do expediente declarado no config.
 *
 * A decisão é crucial para a regra 3 (D6): "sem data, cobra — e a ausência se
 * anuncia". Devolver false (não é expediente) quando não há config provocaria
 * falha aberta — o radar não cobraria e ninguém saberia que o dado desapareceu.
 * Devolver null (não sei) permite ao chamador distinguir entre "não é expediente"
 * (cobrança justificada) e "não tenho dado" (anúncio). A diferença impede silêncio.
 *
 * Expediente é dias da semana + uma ou mais faixas horárias, sem feriado (D8).
 * Forma antiga (uma faixa, ainda válida): `{"dias": [1,2,3,4,5], "de": "08:00",
 * "ate": "18:00"}` — config já escrito no disco do usuário usa esta forma, e
 * não pode virar erro nem mudar de significado.
 * Forma nova (N faixas, ex.: intervalo de almoço): `{"dias": [1,2,3,4,5],
 * "faixas": [{"de": "08:00", "ate": "12:00"}, {"de": "14:00", "ate": "18:00"}]}`.
 * `faixas` foi escolhido em vez de `de`/`ate` aceitando array porque preserva
 * o par de campos como está — zero ambiguidade sobre "de" é escalar ou lista — e
 * porque config sem `faixas` cai direto no fallback de uma faixa só, sem exigir
 * migração. `dias` continua único para todas as faixas (não há "faixas
 * diferentes por dia"): ninguém pediu jornada assimétrica por dia da semana, e
 * bifurcar o schema para isso hoje é escopo que a YAGNI recomenda cortar — se
 * aparecer, o schema atual comporta virar um array de `{dias, faixas}` sem
 * quebrar o que já existe.
 * Dias usa convenção de Date.getDay(): 0 = domingo, 1 = segunda, ..., 6 = sábado.
 *
 * @param {Date} agora timestamp a ser avaliado
 * @param {object} config contém {expediente: {...}} opcional
 * @returns {boolean|null} true/false se há config, null se expediente está ausente
 */
function dentroDoExpediente(agora, config) {
  if (!config || !config.expediente) return null;

  const exp = config.expediente;
  const dia = agora.getDay();
  const hora = String(agora.getHours()).padStart(2, '0');
  const minuto = String(agora.getMinutes()).padStart(2, '0');
  const agoras = `${hora}:${minuto}`;

  // Dia da semana não está na lista de trabalho.
  if (!Array.isArray(exp.dias) || !exp.dias.includes(dia)) return false;

  // N faixas (forma nova) ou uma faixa só de/ate (forma antiga, fallback).
  const faixas = Array.isArray(exp.faixas) && exp.faixas.length
    ? exp.faixas
    : [{ de: exp.de, ate: exp.ate }];

  // Dentro do expediente se a hora cair em QUALQUER faixa declarada.
  return faixas.some((faixa) => agoras >= faixa.de && agoras < faixa.ate);
}

/**
 * Verifica se existe uma sessão viva na pasta do foco com sinal humano recente.
 *
 * Respostas a D7: "Foco ativo em outra janela" = sinal humano dentro da ociosidade
 * máxima que o foco já declara. O `sessoes.json` só tem `cwd`, `prompt_ts` e `stop_ts`,
 * então "ativa" precisa de um limiar — reusar os minutos já declarados evita inventar
 * parâmetro.
 *
 * Comparação de caminho NORMALIZA separador (\ vs /) e caixa, porque `cwd` vem com as
 * duas variações no Windows. MAS NUNCA casa por prefixo — `C:/a` não pode casar `C:/abc`.
 *
 * Sinal humano é o `prompt_ts` (quando o usuario digitou algo), não `stop_ts` (quando
 * a resposta parou). Uma janela que parou há uma hora não está sendo trabalhada.
 *
 * @param {Array<{cwd?: string, prompt_ts?: number, stop_ts?: number}>} sessoes lista do sessoes.json
 * @param {string[]} pastasDoFoco array de caminhos do foco
 * @param {number} ociosidadeMin minutos de inatividade máxima (da "Ociosidade máxima" do foco)
 * @param {number} agora timestamp de referência (Date.now())
 * @returns {boolean} true se existe sessão no foco com sinal dentro da ociosidade; false caso contrário
 */
function focoAtivoEmOutraJanela(sessoes, pastasDoFoco, ociosidadeMin, agora) {
  // Não há foco ou não há sessões = sem atividade detectada.
  if (!pastasDoFoco || !pastasDoFoco.length) return false;
  if (!sessoes || !sessoes.length) return false;

  // Normaliza um caminho para comparação: resolve .., separador \ -> /, e minúscula.
  // Não é substring: `C:/a` não casa `C:/abc`.
  const normalizarCaminho = (caminho) => {
    if (!caminho) return '';
    // path.normalize resolve .. e .
    const resolvido = path.normalize(caminho);
    return resolvido.replace(/\\/g, '/').toLowerCase();
  };

  const pastasFocoNormalizadas = pastasDoFoco.map(normalizarCaminho);

  for (const sessao of sessoes) {
    const { cwd, prompt_ts } = sessao;
    if (!cwd) continue;

    const cwdNormalizado = normalizarCaminho(cwd);

    // Verifica se a sessão está numa pasta do foco (igualdade exata OU subpasta).
    // A comparação por prefixo com separador evita casar irmão com nome comum:
    // C:/a não casa C:/abc, e .../gestao-projetos-template não casa
    // .../gestao-projetos-template-outro.
    const estaNoFoco = pastasFocoNormalizadas.some((pasta) => {
      return cwdNormalizado === pasta || cwdNormalizado.startsWith(pasta + '/');
    });
    if (!estaNoFoco) continue;

    // Sessão no foco, mas sem sinal humano registrado: não conta como ativa.
    if (!prompt_ts) continue;

    // Calcula minutos desde o último sinal (prompt_ts).
    const minutosSinal = (agora - prompt_ts) / (1000 * 60);

    // Se o sinal está dentro da ociosidade máxima, o foco está ativo em outra janela.
    if (minutosSinal <= ociosidadeMin) {
      return true;
    }
  }

  return false;
}


/**
 * Extrai a ociosidade máxima declarada no FOCO.md.
 *
 * @param {string} textoDoFoco conteúdo do FOCO.md
 * @returns {number|null} minutos de ociosidade, ou null se não declarado
 */
function ociosidadeDoFoco(textoDoFoco) {
  const texto = String(textoDoFoco || '');
  const match = texto.match(/Ociosidade máxima:\s*(\d+)\s*min/i);
  if (!match || !match[1]) return null;
  return Number.parseInt(match[1], 10);
}

/**
 * Extrai a natureza do foco ativo (trabalho ou pessoal).
 *
 * Lê a linha em negrito da seção "## Ativo", que declara a natureza entre colchetes.
 * Ignora o boilerplate que explica o formato no topo do arquivo.
 *
 * @param {string} textoDoFoco conteúdo do FOCO.md
 * @returns {'trabalho'|'pessoal'|null} natureza do foco ativo, ou null se não encontrada
 */
function naturezaDoFocoAtivo(textoDoFoco) {
  const texto = String(textoDoFoco || '');
  // Procura a seção "## Ativo"
  const inicioAtivo = texto.search(/^## Ativo/m);
  if (inicioAtivo === -1) return null;

  // Procura a próxima seção (##) ou fim do texto
  const depois = texto.slice(inicioAtivo + 8); // Pula "## Ativo"
  const fimSecao = depois.search(/^## /m);
  const secaoAtivo = fimSecao === -1 ? depois : depois.slice(0, fimSecao);

  // Procura a linha em negrito (**....**) — pode ter conteúdo após o negrito
  const linhaEmNegrito = secaoAtivo.match(/^\*\*.+?\*\*.*$/m);
  if (!linhaEmNegrito) return null;

  // Extrai a natureza [trabalho] ou [pessoal]
  const natureza = linhaEmNegrito[0].match(/\[(trabalho|pessoal)\]/);
  return natureza ? natureza[1] : null;
}

/**
 * Computa o veredito de isenção de desvio de escopo (D10, D6 corrigido).
 *
 * Analisa cada isenção independentemente:
 * - Alguma isenção DETERMINADA e SATISFEITA → emite veredito
 * - Alguma isenção INDETERMINADA → emite anúncio daquela
 * - Os dois PODEM sair juntos quando tratam de isenções diferentes
 * - Nenhuma satisfeita e nenhuma indeterminada → string vazia
 *
 * Isenção aplica quando:
 * - O foco está sendo trabalhado em outra janela agora (regra 17), OU
 * - É tempo pessoal e o foco é de trabalho (regra 3)
 *
 * @param {string} textoDoFoco conteúdo do FOCO.md
 * @param {Array<{cwd?: string, prompt_ts?: number, stop_ts?: number}>} sessoes lista do sessoes.json
 * @param {object} config contém {expediente: {...}} opcional
 * @param {number} agora timestamp de referência (Date.now())
 * @returns {string} veredito e/ou anúncio, ou string vazia se nenhum aplica
 */
function computarVeredito(textoDoFoco, sessoes, config, agora) {
  const texto = String(textoDoFoco || '');

  // Extrai dados necessários
  const pastas = pastasDoFoco(texto);
  const expediente = config && config.expediente;
  const ociosidade = ociosidadeDoFoco(texto);

  // Natureza do foco ativo, não boilerplate
  const natureza = naturezaDoFocoAtivo(texto);
  const ehFocoTrabalho = natureza === 'trabalho';

  // Analisa cada isenção INDEPENDENTEMENTE (D6 corrigido)
  const vereditos = [];
  const anuncios = [];

  // ISENÇÃO 1: Foco ativo em outra janela (regra 17)
  // Precisa de: Pastas: configurado E Ociosidade máxima: declarada
  if (!pastas.length) {
    // Indeterminada: faltam dados
    anuncios.push('Pastas: ausente no FOCO.md — o radar vai cobrar desvio mesmo com o foco aberto em outra janela.');
  } else if (ociosidade === null) {
    // Indeterminada: faltam dados (ociosidade)
    anuncios.push('Ociosidade máxima: ausente no FOCO.md — o radar não pode determinar se o foco está ativo em outra janela.');
  } else {
    // Determinada: pode decidir
    if (focoAtivoEmOutraJanela(sessoes, pastas, ociosidade, agora)) {
      vereditos.push('foco ativo em outra janela');
    }
  }

  // ISENÇÃO 2: Tempo pessoal (regra 3)
  // Precisa de: expediente no config E foco [trabalho]
  if (ehFocoTrabalho && expediente === undefined) {
    // Indeterminada: faltam dados (expediente)
    anuncios.push('expediente: ausente no config.json — o radar vai cobrar desvio fora do expediente (tempo pessoal).');
  } else if (ehFocoTrabalho && expediente !== undefined) {
    // Determinada: pode decidir
    const dentro = dentroDoExpediente(new Date(agora), config);
    if (dentro === false) {
      // false = não é expediente, logo é tempo pessoal
      vereditos.push('tempo pessoal');
    }
  }
  // Se ehFocoTrabalho = false, esta isenção não se aplica (foco não é de trabalho)

  // Monta a resposta final
  const linhas = [];

  // Veredito: se há motivos aplicáveis
  if (vereditos.length) {
    linhas.push(`**NÃO cobrar desvio de escopo nesta sessão** — ${vereditos.join(' e ')}.`);
  }

  // Anúncios: um por isenção indeterminada (podem sair com veredito ou sozinhos)
  linhas.push(...anuncios);

  return linhas.join('\n');
}

module.exports = {
  TETOS,
  filtrarRegras,
  extrairNucleo,
  blocoRegras,
  resumirAvancos,
  resumirFoco,
  limitar,
  limitarBytes,
  cortarBytes,
  priorizarFoco,
  cortarIdentidade,
  focoSoTemPonteiro,
  avisoFocoNaoCoube,
  sessoesVivas,
  ehWorktreeDeAgente,
  JANELA_COLOCADA_MS,
  normalizarCwd,
  sessoesColocadas,
  sessaoColocada,
  processoVivo,
  resumirSessoes,
  travarOrcamento,
  montarContexto,
  pastasDoFoco,
  dentroDoExpediente,
  focoAtivoEmOutraJanela,
  computarVeredito,
  ociosidadeDoFoco,
  naturezaDoFocoAtivo,
};
