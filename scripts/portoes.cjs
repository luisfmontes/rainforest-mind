#!/usr/bin/env node
/**
 * Portões — oráculos executáveis para o ciclo do rainforest.
 *
 * Reescrito a partir de unlazy (MIT), Leonxlnx. O mecanismo adotado é o do
 * original — um portão declara o comando que o decide e o marcador que o output
 * precisa conter, e cumprido é exit 0 E match, os dois, re-executáveis a
 * qualquer momento. O que NÃO veio junto está nomeado no design
 * (`docs/rainforest/design/fluxo-6-design-portoes.md`, seção "O que fica de
 * fora"): aprovação de comandos herdados, `OWNS:`, waves, dispatch paralelo.
 *
 * O PROBLEMA QUE ISTO RESOLVE. O fluxo 1 endureceu `executar`/`verificar`: `ok`
 * exige evidência colada. Mas evidência colada é prosa — o modelo cola um output
 * e afirma que ele prova o critério, e nada re-executa. Nada impede que o
 * critério seja "tudo funciona" com evidência `echo ok`. O portão troca a
 * afirmação pela re-execução.
 *
 * E O QUE ELE NÃO RESOLVE SOZINHO. O checker prova que o oráculo declarado rodou
 * e devolveu o prometido; ele não pergunta se o oráculo vale alguma coisa.
 * `CHECK: echo ok` / `ESPERA: ok` passa em tudo. Por isso o `lint` existe, e por
 * isso ele é a peça de maior valor deste arquivo — a autoria do portão é o elo
 * fraco, e o lint audita a autoria sem executar nada.
 *
 * Uso:
 *   node scripts/portoes.cjs status <arquivo>        # parse + estado, NUNCA executa
 *   node scripts/portoes.cjs lint   <arquivo>        # qualidade dos oráculos, NUNCA executa
 *   node scripts/portoes.cjs rodar  <arquivo>        # executa os CHECKs pendentes, em ordem
 *   node scripts/portoes.cjs rodar --reverificar <a> # re-executa TODOS, inclusive cumpridos
 *
 * Exit codes — o contrato, porque quem chama decide por ele:
 *   0  tudo certo (status/lint limpos; rodar com todos os portões cumpridos)
 *   1  veredito negativo (lint achou erro; rodar teve portão não cumprido ou ABANDONA)
 *   2  arquivo malformado, ou uso errado — nunca é conclusão sobre os portões
 *
 * A distinção entre 1 e 2 é o ponto: "os portões reprovaram" e "eu não consegui
 * ler os portões" são respostas diferentes, e tratá-las igual foi o que fez o
 * guarda do Issue #142 responder com confiança sobre o repositório errado.
 */

'use strict';

const fs = require('fs');
const path = require('path');

/** Estados possíveis de um portão. */
const CUMPRIDO = 'cumprido';
const PENDENTE = 'pendente';
const ABANDONADO = 'abandonado';
/**
 * `inconsistente` é o estado que o design não previu e a implementação obrigou a
 * nomear: checkbox `[x]` com `EVIDENCIA: pendente`. O design diz "checkbox
 * marcado com EVIDENCIA pendente conta como não cumprido" — mas contar como
 * pendente em silêncio esconde que alguém marcou o checkbox à mão. Não-cumprido
 * ele é; mudo é que não pode ser.
 */
const INCONSISTENTE = 'inconsistente';

/** Lê markdown normalizando BOM e CRLF. Mesma forma de `conferir-fluxo.cjs`. */
function lerMarkdown(arquivo) {
  if (!fs.existsSync(arquivo)) return null;
  let conteudo = fs.readFileSync(arquivo, 'utf8');
  if (conteudo.charCodeAt(0) === 0xFEFF) conteudo = conteudo.slice(1);
  return conteudo.replace(/\r\n/g, '\n');
}

/** Erro de parse — carrega a mensagem que o usuário vai ler, já pronta. */
class ErroDeParse extends Error {}

const RE_PORTAO = /^\s*-\s*\[( |x|X)\]\s*(P\d+)\s*:\s*(.*)$/;
const RE_CAMPO = /^\s*(CHECK|ESPERA|EVIDENCIA)\s*:\s*(.*)$/;
const RE_ABANDONA = /^\s*ABANDONA\s*:\s*(P\d+)\s*(.*)$/;

/**
 * Parseia o arquivo de portões.
 *
 * @returns {{portoes: Array, abandonos: Map<string,string>}}
 * @throws {ErroDeParse} em id duplicado, arquivo sem portão, CHECK sem ESPERA
 *   (ou vice-versa), ABANDONA sem razão, ou ABANDONA de portão inexistente.
 */
function parsear(conteudo) {
  const linhas = conteudo.split('\n');
  const portoes = [];
  const abandonos = new Map();
  const vistos = new Set();
  let atual = null;

  for (let i = 0; i < linhas.length; i++) {
    const linha = linhas[i];
    const numero = i + 1;

    const mAbandona = RE_ABANDONA.exec(linha);
    if (mAbandona) {
      const id = mAbandona[1];
      const razao = mAbandona[2].trim();
      if (!razao) {
        throw new ErroDeParse(
          `linha ${numero}: ABANDONA de ${id} sem razão. Abandono sem razão é `
          + `desistência muda — a razão é obrigatória e diz o que precisa de decisão humana.`
        );
      }
      if (abandonos.has(id)) {
        throw new ErroDeParse(`linha ${numero}: ABANDONA repetido para ${id}.`);
      }
      abandonos.set(id, razao);
      atual = null;
      continue;
    }

    const mPortao = RE_PORTAO.exec(linha);
    if (mPortao) {
      const marcado = mPortao[1].toLowerCase() === 'x';
      const id = mPortao[2];
      const titulo = mPortao[3].trim();
      if (vistos.has(id)) {
        throw new ErroDeParse(
          `linha ${numero}: id de portão duplicado: ${id}. Id é a chave pela qual `
          + `a evidência é gravada e o ABANDONA aponta — duplicado torna as duas ambíguas.`
        );
      }
      vistos.add(id);
      atual = {
        id, titulo, marcado, linha: numero,
        check: null, espera: null, evidencia: null,
      };
      portoes.push(atual);
      continue;
    }

    const mCampo = RE_CAMPO.exec(linha);
    if (mCampo && atual) {
      const chave = mCampo[1];
      const valor = mCampo[2].trim();
      if (chave === 'CHECK') atual.check = valor;
      else if (chave === 'ESPERA') atual.espera = valor;
      else atual.evidencia = valor;
    }
  }

  if (portoes.length === 0) {
    throw new ErroDeParse(
      'arquivo sem portão nenhum. Arquivo de portões vazio não é "tudo cumprido" — '
      + 'é arquivo que não diz nada, e tratar isso como sucesso é o furo clássico.'
    );
  }

  for (const p of portoes) {
    const temCheck = p.check !== null && p.check !== '';
    const temEspera = p.espera !== null && p.espera !== '';
    if (temCheck !== temEspera) {
      const falta = temCheck ? 'ESPERA' : 'CHECK';
      throw new ErroDeParse(
        `linha ${p.linha}: ${p.id} tem ${temCheck ? 'CHECK' : 'ESPERA'} sem ${falta}. `
        + `Portão executável tem os dois; portão manual não tem nenhum. Meio-termo é `
        + `oráculo pela metade: ou roda um comando cujo sucesso ninguém definiu, ou `
        + `espera um marcador que nada produz.`
      );
    }
  }

  for (const id of abandonos.keys()) {
    if (!vistos.has(id)) {
      throw new ErroDeParse(
        `ABANDONA aponta para ${id}, que não existe no arquivo.`
      );
    }
  }

  return { portoes, abandonos };
}

/**
 * Estado de um portão, decidido pela EVIDÊNCIA, nunca pelo checkbox sozinho.
 *
 * O arquivo não é a verdade; a execução é. O checkbox é conveniência de leitura
 * humana — e é editável por qualquer um, inclusive por um modelo com pressa.
 */
function estadoDe(portao, abandonos) {
  if (abandonos.has(portao.id)) return ABANDONADO;

  let evidenciaReal = false;
  if (portao.evidencia && portao.evidencia !== 'pendente') {
    try {
      const j = JSON.parse(portao.evidencia);
      evidenciaReal = j && j.match === true && j.exit === 0;
    } catch (_) {
      evidenciaReal = false;
    }
  }

  if (portao.marcado && !evidenciaReal) return INCONSISTENTE;
  if (!portao.marcado && evidenciaReal) return INCONSISTENTE;
  return evidenciaReal ? CUMPRIDO : PENDENTE;
}

/** Carrega e parseia, ou sai com 2 dizendo por quê. */
function carregar(arquivo) {
  const conteudo = lerMarkdown(arquivo);
  if (conteudo === null) {
    console.error(`RECUSADO: arquivo de portões não existe: ${arquivo}`);
    process.exit(2);
  }
  try {
    return parsear(conteudo);
  } catch (err) {
    if (err instanceof ErroDeParse) {
      console.error(`RECUSADO: ${arquivo} malformado.`);
      console.error(`  ${err.message}`);
      process.exit(2);
    }
    throw err;
  }
}

/**
 * `status` — reporta o estado de cada portão. NUNCA executa CHECK nenhum.
 *
 * Esta é a garantia mais importante do arquivo, e a bateria a prova com um
 * fixture cujo CHECK criaria um arquivo-sentinela: depois do `status`, a
 * sentinela não existe. Um leitor de estado que executa comando é uma superfície
 * de execução que ninguém pediu — e `status` é justamente o modo que se roda
 * para decidir se vale a pena executar.
 */
function cmdStatus(arquivo) {
  const { portoes, abandonos } = carregar(arquivo);
  let pendentes = 0;
  for (const p of portoes) {
    const estado = estadoDe(p, abandonos);
    if (estado !== CUMPRIDO && estado !== ABANDONADO) pendentes++;
    let sufixo = '';
    if (estado === ABANDONADO) sufixo = ` — ${abandonos.get(p.id)}`;
    if (estado === INCONSISTENTE) {
      sufixo = ' — checkbox e EVIDENCIA discordam; vale a EVIDENCIA (não cumprido)';
    }
    console.log(`${p.id}: ${estado}${sufixo}`);
  }
  console.log(
    `PARSE OK — ${portoes.length} portão(ões), ${pendentes} não cumprido(s), `
    + `${abandonos.size} abandonado(s)`
  );
  process.exit(0);
}

/**
 * Comandos cuja saída não depende de nada — o oráculo que sempre diz sim.
 * `echo`, `printf`, `true`, `exit 0`. Detectado só quando é o comando INTEIRO:
 * `echo x && node teste.cjs` é legítimo (o `&&` faz o exit vir do node).
 */
const RE_SAIDA_FIXA = /^\s*(echo\b.*|printf\b.*|true|:|exit\s+0)\s*$/;

/** Marcadores que qualquer coisa imprime. `ESPERA: ok` não distingue nada. */
const ESPERA_TRIVIAL = new Set(['ok', 'done', '0', 'sucesso', 'success', 'pass', 'passou']);

/** Termos que aparecem em MENSAGEM DE ERRO — casar com eles é casar com a falha. */
const TERMOS_DE_ERRO = /\b(erro|error|fail|failed|falha|exception|traceback|refused|recusado)\b/i;

/**
 * ...exceto quando o termo vem CONTADO E ZERADO: `0 falha(s)`, `0 erros`,
 * `nenhum erro`. Aí ele não é mensagem de erro, é a AFIRMAÇÃO DE AUSÊNCIA dele —
 * e é justamente a forma mais forte de marcador que existe, porque só aparece
 * quando a contagem fechou em zero.
 *
 * Isto não é refinamento teórico: quando os portões DESTE fluxo foram submetidos
 * ao próprio lint, os quatro que apontam para uma bateria da casa acusaram aviso,
 * porque o formato canônico daqui é `== resultado: N ok, 0 falha(s) ==`. Um
 * detector que dispara contra o padrão correto do repositório não é rigoroso: ele
 * é ruído, e a primeira coisa que ruído ensina é a ignorar o detector.
 */
const RE_CONTAGEM_ZERADA = /\b(0|zero|nenhum[a]?|sem)\s+\w*\s*(erro|error|fail|failed|falha|exception)/i;

/** Ferramentas que não existem no Windows puro. O design proíbe depender delas. */
const RE_FERRAMENTA_UNIX = /(^|[|&;(\s])(grep|tail|head|sed|awk|tr|cut|wc)(\s|$)/;

/** Verbos que nomeiam ATIVIDADE. Portão declara resultado observado, não tarefa. */
const RE_TITULO_ATIVIDADE = /^(rodar|executar|testar|criar|gerar|validar|verificar|implementar|escrever|adicionar|ajustar|corrigir)\b/i;

/**
 * `lint` — audita a AUTORIA dos portões. NUNCA executa CHECK nenhum.
 *
 * Por que esta é a peça de maior valor do arquivo: o `rodar` prova que o oráculo
 * declarado rodou e devolveu o prometido, e para nisso. Ele não tem como saber
 * se o oráculo mede alguma coisa. `CHECK: echo ok` / `ESPERA: ok` satisfaz o
 * `rodar` perfeitamente e não prova nada — a autoria do portão é o elo fraco de
 * todo o mecanismo, e é a única parte que nenhuma execução consegue auditar.
 *
 * Erro x aviso. Erro é o que não tem leitura inocente: comando de saída fixa,
 * marcador trivial, título que nomeia atividade. Aviso é o que costuma estar
 * errado mas às vezes não: `ESPERA` com a palavra "erro" pode ser um teste que
 * legitimamente espera uma mensagem de erro. `--strict` promove aviso a erro,
 * e é o que o gate do `plano` deve usar quando o time quiser apertar.
 */
function cmdLint(arquivo, strict) {
  const { portoes, abandonos } = carregar(arquivo);
  const erros = [];
  const avisos = [];

  for (const p of portoes) {
    if (abandonos.has(p.id)) continue;

    if (RE_TITULO_ATIVIDADE.test(p.titulo)) {
      erros.push(
        `${p.id}: o título nomeia ATIVIDADE ("${p.titulo}"), não resultado. `
        + `Portão cumprido tem de ser uma afirmação observável sobre o artefato `
        + `("os testes do módulo X passam"), não uma tarefa executada ("rodar os testes") `
        + `— tarefa executada é sempre verdadeira depois de executada.`
      );
    }

    if (!p.check) continue; // portão manual: nada de oráculo para auditar

    if (RE_SAIDA_FIXA.test(p.check)) {
      erros.push(
        `${p.id}: CHECK é comando de saída fixa ("${p.check}"). Isso passa sempre, `
        + `contra qualquer estado do código — é um oráculo que não observa nada.`
      );
    }

    const espera = (p.espera || '').trim();
    if (!espera) {
      erros.push(`${p.id}: ESPERA vazio. Sem marcador, "cumprido" vira só "exit 0".`);
    } else if (ESPERA_TRIVIAL.has(espera.toLowerCase())) {
      erros.push(
        `${p.id}: ESPERA trivial ("${espera}"). Um marcador que qualquer saída `
        + `contém não distingue sucesso de nada — precisa ser uma frase que SÓ `
        + `aparece quando todas as asserções passaram.`
      );
    } else {
      if (TERMOS_DE_ERRO.test(espera) && !RE_CONTAGEM_ZERADA.test(espera)) {
        avisos.push(
          `${p.id}: ESPERA contém termo de mensagem de erro ("${espera}"). `
          + `Se o marcador aparece também numa falha parcial, o portão fecha em cima do erro.`
        );
      }
      if (/^\d+$/.test(espera)) {
        avisos.push(
          `${p.id}: ESPERA é só o número "${espera}", sem rótulo. Número medido tem `
          + `de vir rotulado pelo script; número solto casa com qualquer linha que o contenha.`
        );
      }
    }

    if (RE_FERRAMENTA_UNIX.test(p.check)) {
      avisos.push(
        `${p.id}: CHECK depende de ferramenta Unix ("${p.check}"). Ela não existe `
        + `no Windows puro, e no Git Bash algumas mentem — o grep normaliza CRLF `
        + `antes de casar, medido em 2026-09-02. Use um script Node.`
      );
    }
  }

  for (const e of erros) console.error(`ERRO  ${e}`);
  for (const a of avisos) console.error(`AVISO ${a}`);

  if (erros.length > 0 || (strict && avisos.length > 0)) {
    console.error(
      `LINT REPROVADO — ${erros.length} erro(s), ${avisos.length} aviso(s)`
      + `${strict ? ' (--strict: aviso conta como erro)' : ''}`
    );
    process.exit(1);
  }
  console.log(`LINT OK — ${portoes.length} portão(ões), ${avisos.length} aviso(s)`);
  process.exit(0);
}

/**
 * Resolve o shell explicitamente, e devolve QUAL foi usado.
 *
 * Gravar o shell na evidência não é telemetria: `sh -c` e `cmd.exe /d /s /c`
 * têm regras de citação diferentes, e o mesmo `CHECK:` pode passar num e falhar
 * no outro. Evidência que não diz por onde passou não é reproduzível.
 */
function shellDaMaquina() {
  if (process.platform === 'win32') {
    return { exe: process.env.ComSpec || 'cmd.exe', args: ['/d', '/s', '/c'], nome: 'cmd.exe' };
  }
  return { exe: '/bin/sh', args: ['-c'], nome: 'sh' };
}

const TIMEOUT_PADRAO_MS = 120000;

/**
 * Executa um CHECK e decide se o portão está cumprido.
 *
 * Cumprido = exit 0 **E** match do ESPERA no output combinado. Os dois, sempre.
 * Só exit 0 aceita script que morre feliz sem ter medido; só match aceita script
 * que imprime a frase certa e depois estoura.
 */
function executarCheck(check, espera, cwd) {
  const { spawnSync } = require('child_process');
  const sh = shellDaMaquina();
  const teto = Number(process.env.PORTOES_TIMEOUT_MS) || TIMEOUT_PADRAO_MS;

  const r = spawnSync(sh.exe, [...sh.args, check], {
    cwd, encoding: 'utf8', timeout: teto, windowsHide: true,
  });

  // Normaliza CRLF ANTES de procurar o marcador: um script que imprime a frase
  // seguida de \r\n não pode deixar de casar por causa do terminador de linha.
  const saida = `${r.stdout || ''}${r.stderr || ''}`.replace(/\r\n/g, '\n');
  const estourou = r.error && r.error.code === 'ETIMEDOUT';
  const match = saida.includes(espera);
  const exit = typeof r.status === 'number' ? r.status : null;

  return {
    cumprido: !estourou && exit === 0 && match,
    exit, match, estourou, saida,
    shell: sh.nome,
    cwd,
    fingerprint: require('crypto').createHash('sha256').update(saida).digest('hex').slice(0, 12),
  };
}

/**
 * Grava o resultado de volta no arquivo, atomicamente.
 *
 * Guarda o FINGERPRINT do output, nunca o output bruto: saída de sucesso pode
 * carregar caminho de máquina, token de ambiente ou nome de cliente, e o arquivo
 * de portões é versionado. O fingerprint responde "é o mesmo output de antes?",
 * que é a única pergunta que a evidência precisa responder depois.
 */
function gravar(arquivo, resultados) {
  const conteudo = lerMarkdown(arquivo);
  const linhas = conteudo.split('\n');
  let idAtual = null;

  for (let i = 0; i < linhas.length; i++) {
    const mPortao = RE_PORTAO.exec(linhas[i]);
    if (mPortao) {
      idAtual = mPortao[2];
      const r = resultados.get(idAtual);
      if (r) {
        linhas[i] = linhas[i].replace(/\[( |x|X)\]/, r.cumprido ? '[x]' : '[ ]');
      }
      continue;
    }
    const mCampo = RE_CAMPO.exec(linhas[i]);
    if (mCampo && mCampo[1] === 'EVIDENCIA' && idAtual) {
      const r = resultados.get(idAtual);
      if (r) {
        const indent = linhas[i].match(/^\s*/)[0];
        const ev = r.cumprido
          ? JSON.stringify({
              shell: r.shell, cwd: r.cwd, exit: r.exit,
              match: r.match, fingerprint: r.fingerprint,
            })
          : 'pendente';
        linhas[i] = `${indent}EVIDENCIA: ${ev}`;
      }
    }
  }

  const tmp = `${arquivo}.tmp-${process.pid}`;
  fs.writeFileSync(tmp, linhas.join('\n'), 'utf8');
  fs.renameSync(tmp, arquivo);
}

/**
 * `rodar` — o único modo que executa. Sequencial, na ordem do arquivo.
 *
 * ABANDONO NUNCA É CONCLUSÃO. Qualquer `ABANDONA:` no arquivo faz o veredito
 * final ser exit 1 com `DEVOLUCAO OBRIGATORIA`, mesmo que todos os outros
 * portões estejam cumpridos. É o ponto inteiro do mecanismo: desistir de um
 * portão é uma decisão que precisa subir para um humano, e um exit 0 a
 * enterraria — o fluxo seguiria como se estivesse completo.
 */
function cmdRodar(arquivo, reverificar) {
  const { portoes, abandonos } = carregar(arquivo);
  const raiz = process.cwd();
  const resultados = new Map();
  let falhas = 0;

  for (const p of portoes) {
    const estado = estadoDe(p, abandonos);

    if (estado === ABANDONADO) {
      console.log(`${p.id}: ABANDONADO — ${abandonos.get(p.id)}`);
      continue;
    }
    if (!p.check) {
      // Portão manual: nada a executar, e ele não pode ser dado como cumprido
      // por omissão. Fica pendente até um humano gravar a evidência.
      if (estado !== CUMPRIDO) {
        console.log(`${p.id}: MANUAL, pendente — só um humano fecha este.`);
        falhas++;
      } else {
        console.log(`${p.id}: manual, já cumprido`);
      }
      continue;
    }
    if (estado === CUMPRIDO && !reverificar) {
      console.log(`${p.id}: cumprido (pulado; use --reverificar para re-executar)`);
      continue;
    }

    const r = executarCheck(p.check, p.espera, raiz);
    resultados.set(p.id, r);
    if (r.cumprido) {
      console.log(`${p.id}: CUMPRIDO — exit 0, marcador presente (${r.fingerprint})`);
    } else {
      falhas++;
      const motivo = r.estourou
        ? `estourou o timeout e foi morto`
        : r.exit !== 0
          ? `exit ${r.exit}`
          : `exit 0, mas o marcador "${p.espera}" não apareceu na saída`;
      console.log(`${p.id}: NAO CUMPRIDO — ${motivo}`);
    }
  }

  if (resultados.size > 0) gravar(arquivo, resultados);

  if (abandonos.size > 0) {
    console.error('');
    console.error('DEVOLUCAO OBRIGATORIA');
    console.error(
      `  ${abandonos.size} portão(ões) abandonado(s). Abandono é terminal, mas nunca`
    );
    console.error(
      '  é conclusão: alguém precisa decidir se o portão sai, muda, ou volta.'
    );
    for (const [id, razao] of abandonos) console.error(`    ${id}: ${razao}`);
    process.exit(1);
  }

  if (falhas > 0) {
    console.error(`\n${falhas} portão(ões) não cumprido(s).`);
    process.exit(1);
  }
  console.log(`\nTODOS OS PORTOES CUMPRIDOS — ${portoes.length} portão(ões).`);
  process.exit(0);
}

function uso() {
  console.error('uso: node scripts/portoes.cjs status <arquivo>');
  console.error('     node scripts/portoes.cjs lint   <arquivo> [--strict]');
  console.error('     node scripts/portoes.cjs rodar  <arquivo> [--reverificar]');
  process.exit(2);
}

function main() {
  const argv = process.argv.slice(2);
  const modo = argv[0];
  const arquivo = argv.find((a, i) => i > 0 && !a.startsWith('--'));

  if (!modo || !arquivo) uso();
  const caminho = path.resolve(arquivo);

  if (modo === 'status') return cmdStatus(caminho);
  if (modo === 'lint') return cmdLint(caminho, argv.includes('--strict'));
  if (modo === 'rodar') return cmdRodar(caminho, argv.includes('--reverificar'));
  uso();
}

if (require.main === module) main();
module.exports = {
  parsear, estadoDe, lerMarkdown, ErroDeParse,
  CUMPRIDO, PENDENTE, ABANDONADO, INCONSISTENTE,
};
