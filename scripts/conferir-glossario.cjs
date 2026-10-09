#!/usr/bin/env node
// @categoria: sensor
/**
 * Confere o GLOSSARIO.md do repo e RECUSA verbete fora do formato D7: campo
 * faltando, campo sem texto ou com placeholder, rótulo digitado errado ou em
 * negrito, termo duplicado, Evite que repete um termo, linha injetada acima de
 * 900 B, GLOSSARIO.md acima do teto de 262144 B (sai sem parsear), e (com
 * --caminhos) caminho em crase que não existe no repo.
 *
 * POR QUE EXISTE. O glossário entra no pedido do usuário e no briefing de
 * subagente. Um verbete sem Cenário ou com rótulo errado não quebra nada: a
 * injeção o descarta em silêncio, e ninguém percebe que o termo deixou de
 * aparecer. Este conferidor faz a recusa aparecer no commit, com a linha do
 * arquivo e o formato esperado, em vez de na sessão de alguém.
 *
 * UM SÓ PARSER. Lê com hooks/lib/glossario.cjs (lerVerbetes, verbeteValido,
 * placeholder, chaveDe, montarBlocoGlossario). Não tem gramática própria: o
 * que a injeção não lê, este conferidor também não aceita. A única coisa
 * própria é a dica de rótulo digitado errado, que só aparece dentro da mensagem
 * de um campo obrigatório que faltou — nunca recusa sozinha.
 *
 * Uso:
 *   node scripts/conferir-glossario.cjs [--raiz <dir>] [--exigir] [--caminhos]
 *   node scripts/conferir-glossario.cjs --listar [--raiz <dir>]
 *
 *   --raiz <dir>  pasta com o GLOSSARIO.md (padrão: toplevel do git do cwd)
 *   --exigir      sem GLOSSARIO.md é defeito (padrão: nada a conferir)
 *   --caminhos    confere caminho em crase de "Onde mora" e "Cenário"
 *   --listar      imprime os verbetes válidos, um por linha, e sai 0
 *
 * Exit:
 *   0  GLOSSARIO.md conforme, ou ausente sem --exigir, ou --listar
 *   1  defeito, cada um nomeado GLOSSARIO.md:<linha>; ou ausente com --exigir
 *   2  uso incorreto
 */

'use strict';

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const { caminhoExecutavel } = require(path.join(__dirname, '..', 'hooks', 'lib', 'resolver-executavel.cjs'));
const {
  lerVerbetes,
  verbeteValido,
  placeholder,
  normalizar,
  chaveDe,
  montarBlocoGlossario,
  BYTES_MAX_VERBETE,
  GLOSSARIO_MAX_BYTES,
} = require(path.join(__dirname, '..', 'hooks', 'lib', 'glossario.cjs'));

const NOME_ARQUIVO = 'GLOSSARIO.md';

const OBRIGATORIOS = [
  { campo: 'definicao', rotulo: 'Definição', formato: 'Definição: uma a duas frases.' },
  { campo: 'ondeMora', rotulo: 'Onde mora', formato: 'Onde mora: arquivo, rotina, tabela ou campo.' },
  { campo: 'cenario', rotulo: 'Cenário', formato: 'Cenário: um caso real, concreto.' },
];
const FORMATO_EVITE = 'Evite: sinônimo errado; outro sinônimo errado';
const FORMATO_TERMO = '## <termo>, um verbete por termo';

function resolverRaizPadrao() {
  const r = spawnSync(caminhoExecutavel('git'), ['rev-parse', '--show-toplevel'], { encoding: 'utf8' });
  if (r.status === 0 && r.stdout && r.stdout.trim()) return r.stdout.trim();
  return process.cwd();
}

/** Levenshtein, para reconhecer rótulo a uma letra ou duas de um campo obrigatório. */
function distancia(a, b) {
  let anterior = Array.from({ length: b.length + 1 }, (_, j) => j);
  for (let i = 1; i <= a.length; i++) {
    const atual = [i];
    for (let j = 1; j <= b.length; j++) {
      const custo = a[i - 1] === b[j - 1] ? 0 : 1;
      atual[j] = Math.min(anterior[j] + 1, atual[j - 1] + 1, anterior[j - 1] + custo);
    }
    anterior = atual;
  }
  return anterior[b.length];
}

/**
 * Dica para um campo obrigatório que faltou: procura, entre as linhas que o
 * parser NÃO leu como campo, uma com rótulo em negrito ou quase igual ao nome.
 */
function dicaRotulo(v, rotulo) {
  const alvo = normalizar(rotulo);
  for (const d of v.desconhecidos) {
    const limpo = normalizar(d.rotulo.replace(/[*_]/g, ''));
    if (limpo === alvo && /[*_]/.test(d.rotulo)) {
      return `a linha ${d.linha} tem "${d.rotulo.trim()}:" em negrito; o parser não lê rótulo em negrito, escreva "${rotulo}:" sem asteriscos`;
    }
    if (limpo.split(' ').length <= 2 && distancia(limpo, alvo) <= 2) {
      return `a linha ${d.linha} tem "${d.rotulo.trim()}:", que o parser não reconhece; o rótulo é "${rotulo}:"`;
    }
  }
  return null;
}

/** Caminho para conferir em --caminhos: sem espaço, sem <, *, ~ ou URL, com extensão de letras. */
function ehCaminho(s) {
  if (/\s/.test(s) || /[<*]/.test(s) || s.startsWith('~') || s.includes('://')) return false;
  const base = s.split('/').pop();
  return /\.[A-Za-z][A-Za-z0-9]*$/.test(base);
}

function defeitosDoVerbete(v, porChave, raiz, caminhos) {
  const out = [];
  const add = (linha, quem, motivo, formato) =>
    out.push(`${NOME_ARQUIVO}:${linha}: verbete "${v.termo}", ${quem}: ${motivo}. Formato: ${formato}`);

  for (const o of OBRIGATORIOS) {
    const linhaCampo = v.campoLinha[o.campo];
    if (linhaCampo === null) {
      const dica = dicaRotulo(v, o.rotulo);
      add(v.linha, `campo ${o.rotulo}`, `falta a linha "${o.rotulo}:"${dica ? ` (${dica})` : ''}`, o.formato);
    } else if (v[o.campo] === '') {
      const dica = dicaRotulo(v, o.rotulo);
      add(linhaCampo, `campo ${o.rotulo}`, `rótulo sem texto${dica ? ` (${dica})` : ''}`, o.formato);
    } else if (placeholder(v[o.campo])) {
      add(linhaCampo, `campo ${o.rotulo}`, `placeholder "${v[o.campo]}" no lugar do texto`, o.formato);
    }
  }

  for (const item of v.evite) {
    const ck = chaveDe(item);
    const linha = v.campoLinha.evite === null ? v.linha : v.campoLinha.evite;
    if (ck === v.chave) {
      add(linha, 'campo Evite', `"${item}" é o próprio termo do verbete`, FORMATO_EVITE);
    } else if (porChave.has(ck)) {
      const outro = porChave.get(ck);
      add(linha, 'campo Evite', `"${item}" é o termo de outro verbete ("${outro.termo}", linha ${outro.linha})`, FORMATO_EVITE);
    }
  }

  if (verbeteValido(v) && montarBlocoGlossario([v]) === '') {
    add(v.linha, 'linha injetada', `passa de ${BYTES_MAX_VERBETE} B e nunca seria injetada; encurte Definição, Onde mora ou Cenário`, 'uma linha de verbete cabe em até 900 B');
  }

  if (caminhos) {
    for (const campo of ['ondeMora', 'cenario']) {
      const rotulo = campo === 'ondeMora' ? 'Onde mora' : 'Cenário';
      const linha = v.campoLinha[campo] === null ? v.linha : v.campoLinha[campo];
      for (const m of v[campo].matchAll(/`([^`]+)`/g)) {
        const s = m[1].trim();
        if (!ehCaminho(s)) continue;
        if (!fs.existsSync(path.join(raiz, s))) {
          add(linha, `campo ${rotulo}`, `caminho "${s}" não existe sob a raiz do repo`, `${rotulo}: caminho que existe no repo, ou nome sem crase`);
        }
      }
    }
  }

  return out;
}

function defeitosDoArquivo(verbetes, raiz, caminhos) {
  if (verbetes.length === 0) {
    return [`${NOME_ARQUIVO}:1: nenhum verbete lido. Formato: ${FORMATO_TERMO}, em linha própria e fora de cerca de código (três crases)`];
  }
  for (const v of verbetes) v.chave = chaveDe(v.termo);
  const porChave = new Map();
  for (const v of verbetes) {
    if (!porChave.has(v.chave)) porChave.set(v.chave, v);
  }

  const out = [];
  const vistos = new Set();
  for (const v of verbetes) {
    const duplicado = vistos.has(v.chave);
    if (duplicado) {
      const primeiro = porChave.get(v.chave);
      out.push(`${NOME_ARQUIVO}:${v.linha}: verbete "${v.termo}", termo: repete "${primeiro.termo}" (linha ${primeiro.linha}). Formato: ${FORMATO_TERMO}`);
    }
    vistos.add(v.chave);
  }

  for (const v of verbetes) {
    out.push(...defeitosDoVerbete(v, porChave, raiz, caminhos));
  }
  return out;
}

function listarVerbetes(verbetes) {
  let ignorados = 0;
  for (const v of verbetes) {
    if (!verbeteValido(v)) {
      ignorados++;
      continue;
    }
    console.log(v.evite.length > 0 ? `${v.termo} | evite: ${v.evite.join(', ')}` : v.termo);
  }
  if (ignorados > 0) {
    console.error(`${ignorados} verbete(s) inválido(s) ignorado(s); rode sem --listar para ver o motivo`);
  }
  return 0;
}

function main() {
  const args = process.argv.slice(2);
  const iRaiz = args.indexOf('--raiz');
  if (iRaiz >= 0 && (!args[iRaiz + 1] || args[iRaiz + 1].startsWith('--'))) {
    console.error('uso: --raiz <dir>');
    return 2;
  }
  const raiz = iRaiz >= 0 ? path.resolve(args[iRaiz + 1]) : resolverRaizPadrao();
  const exigir = args.includes('--exigir');
  const listar = args.includes('--listar');
  const caminhos = args.includes('--caminhos');

  const arq = path.join(raiz, NOME_ARQUIVO);
  if (!fs.existsSync(arq)) {
    if (exigir) {
      console.log(`${NOME_ARQUIVO} ausente em ${raiz} (--exigir)`);
      return 1;
    }
    console.log(`sem ${NOME_ARQUIVO} em ${raiz}: nada a conferir`);
    return 0;
  }

  const tamanho = fs.statSync(arq).size;
  if (tamanho > GLOSSARIO_MAX_BYTES) {
    console.log(`${NOME_ARQUIVO}: ${tamanho} B, acima do teto de ${GLOSSARIO_MAX_BYTES} B; o hook não lê o arquivo nesse tamanho. Encurte o glossário`);
    return 1;
  }

  const verbetes = lerVerbetes(fs.readFileSync(arq, 'utf8'));
  if (listar) return listarVerbetes(verbetes);

  const defeitos = defeitosDoArquivo(verbetes, raiz, caminhos);
  if (defeitos.length === 0) {
    console.log(`${NOME_ARQUIVO}: ${verbetes.length} verbete(s) conforme(s)`);
    return 0;
  }
  for (const d of defeitos) console.log(`  ${d}`);
  console.log(`${NOME_ARQUIVO}: ${defeitos.length} defeito(s)`);
  return 1;
}

process.exitCode = main();
