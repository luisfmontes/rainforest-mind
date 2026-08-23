#!/usr/bin/env node
/**
 * Confere, contra o RASTRO REAL de uma execução, que o `divergir-frames.js`
 * respeitou o isolamento que é o motivo dele existir.
 *
 * O `divergir-frames.js` dispara SEIS agentes em paralelo com o MESMO
 * enunciado — cada um só muda a pergunta do frame — e nenhum vê a saída do
 * outro, mais um crítico que lê os seis ao final. O isolamento entre os seis
 * É o mecanismo: se dois frames se virem, a divergência vira eco e a rodada
 * inteira deixa de valer o custo de seis agentes. Ninguém prova isolamento
 * relatando "rodei e pareceu isolado" — prova-se contra o rastro.
 *
 * ONDE ESTÁ O RASTRO: cada execução deixa `<projeto>/subagents/workflows/wf_<id>/`
 * com, por agente, um `agent-<id>.jsonl` (histórico da conversa; a PRIMEIRA
 * linha é `{type:"user", message:{role:"user", content:<prompt>}}`) e um
 * `agent-<id>.meta.json` (agentType/worktreePath/spawnDepth). O
 * `journal.jsonl` NÃO tem o prompt — só `started`/`result` por agentId — e
 * por isso este script nunca o lê.
 *
 * O QUE ELE AFIRMA (nessa ordem, e para no primeiro que não bater):
 *   1. Existem exatamente 7 agentes no diretório (6 frames + 1 crítico).
 *   2. Os seis prompts de frame são idênticos entre si LINHA A LINHA, exceto
 *      em no máximo UMA linha — a da pergunta do frame.
 *   3. O sétimo prompt (o crítico) é distinto do molde dos seis.
 *   4. Nenhum dos seis prompts contém, em lugar nenhum do próprio texto, a
 *      pergunta de outro frame — é isto que pega o vazamento de isolamento.
 *
 * POR QUE LINHA A LINHA E NÃO BYTE A BYTE TOTAL, nem "parecido o bastante".
 * Exigir os seis prompts IDÊNTICOS reprovaria a entrega correta — a pergunta
 * do frame por design muda de um frame para o outro. Comparar por
 * similaridade frouxa (ex.: distância de edição abaixo de um limiar) deixaria
 * passar um vazamento pequeno. O meio-termo que discrimina sem reprovar o
 * desenho correto: quebrar cada prompt em linhas (normalizando CRLF/CR — o
 * mesmo cuidado que já mordeu outro conferidor deste acervo) e exigir que, das
 * N linhas, NO MÁXIMO UMA divirja entre os seis. Cada linha que sobra além
 * dessa é comparada byte a byte, sem tolerância nenhuma — só a linha da
 * pergunta tem licença para variar.
 *
 * COMO O CRÍTICO É ACHADO: não se assume qual dos 7 arquivos é o crítico (a
 * ordem de gravação em disco não é contrato). O script testa as 7 formas de
 * excluir um agente e ver se os 6 restantes batem no critério acima; a
 * exclusão que funciona aponta o crítico. Zero ou mais de uma exclusão válida
 * é, em si, uma reprovação (isolamento não fica provado por acidente).
 *
 * Uso:
 *   node scripts/conferir-divergencia.cjs <diretorio-wf_...>
 *
 * Exit:
 *   0  isolamento intacto — os 4 itens acima se confirmaram
 *   1  erro de uso ou de leitura (diretório/arquivo ausente, JSON quebrado)
 *   2  isolamento violado — a saída nomeia o(s) agente(s) responsável(is)
 */

const fs = require('fs');
const path = require('path');

const USO = `uso: node scripts/conferir-divergencia.cjs <diretorio-do-workflow>

  <diretorio-do-workflow>   pasta wf_<id> com agent-<id>.jsonl + .meta.json

exit: 0 isolamento intacto | 1 erro de uso/leitura | 2 isolamento violado`;

function erroUso(msg) {
  console.error(`erro: ${msg}`);
  console.error('');
  console.error(USO);
  process.exit(1);
}

/** Quebra em linhas normalizando CRLF/CR — sem isso um agente cujo prompt
 * saiu com terminação diferente pareceria "divergente" por acidente de
 * codificação, não por conteúdo. */
function emLinhas(texto) {
  return String(texto).split(/\r\n|\r|\n/);
}

function listarAgentes(dir) {
  let arquivos;
  try {
    arquivos = fs.readdirSync(dir);
  } catch (e) {
    erroUso(`nao consegui ler o diretorio: ${dir} (${e.message})`);
  }
  const re = /^agent-(.+)\.jsonl$/;
  const agentes = [];
  for (const f of arquivos) {
    const m = f.match(re);
    if (!m) continue;
    const id = m[1];
    const jsonlPath = path.join(dir, f);
    const metaPath = path.join(dir, `agent-${id}.meta.json`);
    agentes.push({ id, jsonlPath, metaPath, temMeta: fs.existsSync(metaPath) });
  }
  agentes.sort((a, b) => a.id.localeCompare(b.id));
  return agentes;
}

/** Lê só a primeira linha do jsonl (o resto pode ser megabytes de transcript
 * que não interessam aqui) e devolve o objeto já parseado, ou null. */
function primeiroRegistro(caminho) {
  let conteudo;
  try {
    conteudo = fs.readFileSync(caminho, 'utf8');
  } catch (e) {
    return { erro: `nao consegui ler: ${e.message}` };
  }
  const nl = conteudo.indexOf('\n');
  const primeira = (nl === -1 ? conteudo : conteudo.slice(0, nl)).trim();
  if (!primeira) return { erro: 'arquivo vazio' };
  try {
    return { obj: JSON.parse(primeira) };
  } catch (e) {
    return { erro: `primeira linha nao e JSON valido: ${e.message}` };
  }
}

function extrairPrompt(obj) {
  if (!obj || obj.type !== 'user' || !obj.message || obj.message.role !== 'user') {
    return null;
  }
  const c = obj.message.content;
  if (typeof c === 'string') return c;
  if (Array.isArray(c)) {
    const texto = c.filter((b) => b && typeof b.text === 'string').map((b) => b.text).join('\n');
    return texto || null;
  }
  return null;
}

/**
 * Compara um grupo de N prompts (já quebrados em linhas) contra o critério do
 * item 2. `ok:true` inclui o índice da linha que pôde variar (ou null se as
 * linhas eram idênticas em tudo — caso degenerado, mas ainda válido: "no
 * máximo uma diverge" aceita zero). `ok:false` traz o suficiente para
 * diagnosticar: se a própria CONTAGEM de linhas já difere entre os membros
 * (sinal de estrutura diferente, não de uma linha trocada) ou, quando a
 * contagem bate, quais índices divergem além do permitido.
 */
function conferirGrupo(linhasPorAgente) {
  const n = linhasPorAgente[0].linhas.length;
  const tamanhoDiferente = linhasPorAgente.filter((a) => a.linhas.length !== n);
  if (tamanhoDiferente.length > 0) {
    return { ok: false, motivo: 'contagem-de-linhas-diferente', suspeitos: tamanhoDiferente.map((a) => a.id) };
  }
  const divergentes = [];
  for (let i = 0; i < n; i += 1) {
    const valores = new Set(linhasPorAgente.map((a) => a.linhas[i]));
    if (valores.size > 1) divergentes.push(i);
  }
  if (divergentes.length <= 1) {
    return { ok: true, linhaPergunta: divergentes.length === 1 ? divergentes[0] : null };
  }
  return { ok: false, motivo: 'linhas-extras-divergentes', indices: divergentes };
}

/** Para o diagnóstico de falha: dado um índice de linha que divergiu, aponta
 * quais agentes ficaram fora da maioria — é isso que "nomeia quem divergiu". */
function suspeitosNoIndice(linhasPorAgente, indice) {
  const contagem = new Map();
  for (const a of linhasPorAgente) {
    const v = a.linhas[indice];
    contagem.set(v, (contagem.get(v) || 0) + 1);
  }
  const [majoritario] = [...contagem.entries()].sort((a, b) => b[1] - a[1])[0];
  return linhasPorAgente.filter((a) => a.linhas[indice] !== majoritario).map((a) => a.id);
}

function diagnosticarFalhaDeGrupo(dados) {
  // Tenta as 7 formas de excluir um agente e pontua qual exclusão chega mais
  // perto de formar um grupo válido de 6 — é o melhor candidato a reportar.
  let melhor = null;
  for (let excluido = 0; excluido < dados.length; excluido += 1) {
    const seis = dados.filter((_, i) => i !== excluido);
    const r = conferirGrupo(seis);
    const penalidade = r.ok
      ? 0
      : r.motivo === 'contagem-de-linhas-diferente'
        ? Infinity
        : r.indices.length - 1;
    if (!melhor || penalidade < melhor.penalidade) {
      melhor = { excluidoId: dados[excluido].id, seis, r, penalidade };
    }
  }

  console.error('RECUSADO: nao encontrei um agrupamento valido de 6 prompts de frame');
  console.error('(molde identico linha a linha, a menos de no maximo 1 linha).');
  console.error('');
  if (melhor.r.motivo === 'contagem-de-linhas-diferente') {
    console.error(`  candidato mais proximo (tratando ${melhor.excluidoId} como critico):`);
    console.error(`  contagem de linhas diferente em: ${melhor.r.suspeitos.join(', ')}`);
    process.exit(2);
  }

  const { seis, r } = melhor;
  // A linha da pergunta é a que tem MAIS valores distintos entre os 6 — é a
  // única linha que o desenho espera ver diferente em todo mundo.
  const porValoresDistintos = r.indices
    .map((i) => ({ i, distintos: new Set(seis.map((a) => a.linhas[i])).size }))
    .sort((a, b) => b.distintos - a.distintos);
  const [linhaPergunta, ...extras] = porValoresDistintos;
  console.error(`  candidato mais proximo (tratando ${melhor.excluidoId} como critico):`);
  console.error(`  provavel linha da pergunta do frame: linha ${linhaPergunta.i + 1} (${linhaPergunta.distintos} valores distintos — esperado).`);
  for (const extra of extras) {
    const suspeitos = suspeitosNoIndice(seis, extra.i);
    console.error(`  linha ${extra.i + 1} diverge tambem, e nao deveria: agente(s) ${suspeitos.join(', ')} diferem da maioria.`);
    for (const sid of suspeitos) {
      const agente = seis.find((a) => a.id === sid);
      const linhaSuspeita = agente.linhas[extra.i] || '';
      for (const outro of seis) {
        if (outro.id === sid) continue;
        const perguntaOutro = (outro.linhas[linhaPergunta.i] || '').trim();
        if (perguntaOutro.length >= 8 && linhaSuspeita.includes(perguntaOutro)) {
          console.error(`    -> parece CONTAMINACAO: o agente ${sid} contem a pergunta do agente ${outro.id}.`);
        }
      }
    }
  }
  process.exit(2);
}

function main() {
  const dir = process.argv[2];
  if (!dir) erroUso('falta o diretorio do workflow');
  if (!fs.existsSync(dir) || !fs.statSync(dir).isDirectory()) {
    erroUso(`nao e um diretorio: ${dir}`);
  }

  console.log(`diretorio: ${dir}`);

  // ---------------------------------------------------------- item 1: contagem
  const agentes = listarAgentes(dir);
  console.log(`agentes encontrados: ${agentes.length}${agentes.length ? ' (' + agentes.map((a) => a.id).join(', ') + ')' : ''}`);
  const semMeta = agentes.filter((a) => !a.temMeta);
  if (semMeta.length) {
    console.log(`aviso: sem .meta.json: ${semMeta.map((a) => a.id).join(', ')} (nao bloqueia a conferencia — o item 1 conta pelo .jsonl)`);
  }

  if (agentes.length !== 7) {
    console.error('');
    console.error(`RECUSADO: esperava exatamente 7 agentes, encontrei ${agentes.length}.`);
    process.exit(2);
  }
  console.log('ok: 7 agentes (item 1).');

  // ------------------------------------------------------- ler os 7 prompts
  const dados = agentes.map((a) => {
    const { obj, erro } = primeiroRegistro(a.jsonlPath);
    if (erro) return { ...a, erroLeitura: erro };
    const prompt = extrairPrompt(obj);
    if (prompt === null) return { ...a, erroLeitura: 'primeira linha nao e um registro type:"user"/message.role:"user" com content legivel' };
    return { ...a, prompt, linhas: emLinhas(prompt) };
  });
  const comErro = dados.filter((d) => d.erroLeitura);
  if (comErro.length) {
    console.error('');
    console.error(`RECUSADO: nao consegui extrair o prompt de ${comErro.length} agente(s):`);
    for (const d of comErro) console.error(`  ${d.id}: ${d.erroLeitura}`);
    process.exit(1);
  }

  // ------------------------------------------------ itens 2 e 3: achar o split
  const combosValidos = [];
  for (let excluido = 0; excluido < 7; excluido += 1) {
    const seis = dados.filter((_, i) => i !== excluido);
    const r = conferirGrupo(seis);
    if (r.ok) combosValidos.push({ excluidoIdx: excluido, seis, r });
  }

  if (combosValidos.length === 0) {
    diagnosticarFalhaDeGrupo(dados);
    return; // diagnosticarFalhaDeGrupo sempre sai do processo
  }
  if (combosValidos.length > 1) {
    console.error('');
    console.error('RECUSADO: mais de um agrupamento de 6 prompts bate no criterio do item 2 —');
    console.error('nao da pra apontar o critico com seguranca. Candidatos (agente tratado como critico):');
    for (const c of combosValidos) console.error(`  ${dados[c.excluidoIdx].id}`);
    process.exit(2);
  }

  const { excluidoIdx, seis, r: resultadoGrupo } = combosValidos[0];
  const critico = dados[excluidoIdx];
  if (resultadoGrupo.linhaPergunta !== null) {
    console.log(`ok: os 6 frames batem linha a linha, exceto a linha ${resultadoGrupo.linhaPergunta + 1} (a pergunta do frame) (item 2).`);
  } else {
    console.log('ok: os 6 frames sao identicos linha a linha (a "pergunta" calhou igual nos seis) (item 2).');
  }
  console.log(`   frames: ${seis.map((d) => d.id).join(', ')}`);
  console.log(`   critico candidato: ${critico.id}`);

  // item 3: o critico precisa mesmo divergir do molde dos seis, nao só ter
  // sido o resto da divisão. Confere explicitamente contra o primeiro frame.
  const moldeFrame = seis[0];
  let diferencasComCritico = 0;
  const maiorLen = Math.max(critico.linhas.length, moldeFrame.linhas.length);
  for (let i = 0; i < maiorLen; i += 1) {
    if (i === resultadoGrupo.linhaPergunta) continue;
    if ((critico.linhas[i] ?? null) !== (moldeFrame.linhas[i] ?? null)) diferencasComCritico += 1;
  }
  if (diferencasComCritico === 0) {
    console.error('');
    console.error(`RECUSADO: o setimo prompt (${critico.id}) NAO e distinto do molde dos seis frames (item 3).`);
    process.exit(2);
  }
  console.log(`ok: o setimo prompt (${critico.id}) diverge do molde dos frames em ${diferencasComCritico} linha(s) (item 3).`);

  // -------------------------------------------------------- item 4: vazamento
  if (resultadoGrupo.linhaPergunta !== null) {
    const LIMIAR = 8; // caracteres minimos p/ nao acusar coincidencia de linha curta/generica
    const perguntas = seis.map((d) => ({ id: d.id, texto: (d.linhas[resultadoGrupo.linhaPergunta] || '').trim() }));
    const achados = [];
    for (const alvo of seis) {
      for (const outra of perguntas) {
        if (outra.id === alvo.id) continue;
        if (outra.texto.length < LIMIAR) continue;
        if (alvo.prompt.includes(outra.texto)) {
          achados.push({ agente: alvo.id, deQuem: outra.id, trecho: outra.texto });
        }
      }
    }
    if (achados.length) {
      console.error('');
      console.error(`RECUSADO: isolamento quebrado — ${achados.length} vazamento(s) entre frames (item 4).`);
      for (const a of achados) {
        console.error(`  agente ${a.agente}: o prompt contem a pergunta do agente ${a.deQuem}: "${a.trecho.slice(0, 160)}"`);
      }
      process.exit(2);
    }
  }
  console.log('ok: nenhum dos 6 prompts contem a pergunta de outro frame (item 4).');

  console.log('');
  console.log(`PASSOU: 7 agentes, 6 frames com molde identico (a menos da pergunta), 1 critico distinto, isolamento intacto.`);
  process.exit(0);
}

main();

module.exports = { conferirGrupo, extrairPrompt, listarAgentes, emLinhas };
