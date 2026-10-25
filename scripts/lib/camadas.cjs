#!/usr/bin/env node
/**
 * Camadas do plano: o DAG que o `executar` despacha por camada.
 *
 * Por que existe: `paralela:` marcado à mão divergia do `depende de:` (D2 do
 * design 2026-10-13-executar-dag-painel). As camadas saem só do `depende de:`,
 * por Kahn, e a recusa de ciclo, de dependência inexistente e de arquivo
 * compartilhado na mesma camada mora aqui, para a `cobertura` e o
 * `conferir-fluxo camadas` lerem a mesma conta.
 *
 * Entrada: [{numero, dependeDe: number[], arquivos: string[], paralelaDeclarada?: boolean (true = `paralela: nao` explícito)}]
 * Saída: {camadas: number[][], conflitos: [{camada, a, b, arquivo}],
 *         recusas: [...], avisos: [...]}
 * `conflitos` lista todo arquivo em comum na mesma camada. `recusas` são os que
 * nenhuma das duas tarefas traz `paralela: nao` explícito; `avisos`, os que alguma traz
 * (emenda D2 de 2026-10-13: plano antigo serializado por `paralela: nao` passa com aviso).
 * Ciclo e dependência inexistente lançam ErroCamadas, nomeando as tarefas.
 */

const fs = require('fs');
const path = require('path');

class ErroCamadas extends Error {
  constructor(mensagem, detalhe = {}) {
    super(mensagem);
    this.name = 'ErroCamadas';
    this.detalhe = detalhe;
  }
}

/**
 * Lê o valor de `depende de:`. `nenhuma` (ou vazio) vira [], mesmo com prosa depois
 * ("nenhuma (roda quando a cota voltar, 17:41)"). Senão, tira os parênteses e lê os
 * itens separados por vírgula, espaço ou "e" (`3`, `#3`, intervalo `1-4`) até o
 * primeiro que não é número: dali em diante é prosa ("2, após 17:41" vale [2]), e
 * data ou hora na prosa não vira tarefa. Sem número nenhum, lança ErroCamadas.
 */
function parseDependencias(texto) {
  const t = (texto || '').trim();
  if (t === '' || /^nenhuma\b/i.test(t)) return [];
  const nums = [];
  for (const item of t.replace(/\([^)]*\)/g, ' ').split(/[\s,;]+/).filter(Boolean)) {
    if (/^e$/i.test(item)) continue;
    const um = item.match(/^#?(\d+)$/);
    if (um) { nums.push(parseInt(um[1], 10)); continue; }
    const faixa = item.match(/^(\d+)-(\d+)$/);
    if (!faixa) break;
    const a = parseInt(faixa[1], 10);
    const b = parseInt(faixa[2], 10);
    for (let n = Math.min(a, b); n <= Math.max(a, b); n++) nums.push(n);
  }
  if (!nums.length) {
    throw new ErroCamadas(`depende de: "${t}" não lista tarefa nenhuma (use "nenhuma" ou números)`);
  }
  return [...new Set(nums)];
}

/** Uma cadeia de dependências que volta a si mesma, nomeada tarefa por tarefa. */
function acharCiclo(pendentes) {
  const inicio = Math.min(...pendentes.keys());
  const caminho = [];
  let atual = inicio;
  while (!caminho.includes(atual)) {
    caminho.push(atual);
    atual = [...pendentes.get(atual)].filter((d) => pendentes.has(d)).sort((a, b) => a - b)[0];
  }
  const ciclo = caminho.slice(caminho.indexOf(atual)).concat(atual);
  return ciclo.map((n) => `tarefa ${n}`).join(' → ');
}

function calcularCamadas(tarefas) {
  const existentes = new Set(tarefas.map((t) => t.numero));
  for (const t of tarefas) {
    for (const d of t.dependeDe) {
      if (!existentes.has(d)) {
        throw new ErroCamadas(
          `tarefa ${t.numero} depende de: ${d}, que não existe no plano`,
          { tipo: 'inexistente', tarefa: t.numero, dependencia: d });
      }
    }
  }

  const pendentes = new Map(tarefas.map((t) => [t.numero, new Set(t.dependeDe)]));
  const arquivosDe = new Map(tarefas.map((t) => [t.numero, t.arquivos]));
  const feitas = new Set();
  const camadas = [];
  // Cada rodada que sai alguma tarefa consome ao menos uma: o limite não corta execução correta.
  for (let rodada = 0; pendentes.size > 0 && rodada < tarefas.length; rodada++) {
    const prontas = [...pendentes.keys()]
      .filter((n) => [...pendentes.get(n)].every((d) => feitas.has(d)))
      .sort((a, b) => a - b);
    if (prontas.length === 0) throw new ErroCamadas(
      `ciclo de dependência: ${acharCiclo(pendentes)} (cada uma depende da seguinte)`,
      { tipo: 'ciclo' });
    camadas.push(prontas);
    for (const n of prontas) {
      feitas.add(n);
      pendentes.delete(n);
    }
  }

  const declaradaDe = new Map(tarefas.map((t) => [t.numero, t.paralelaDeclarada === true]));
  const conflitos = [];
  camadas.forEach((camada, indice) => {
    for (let i = 0; i < camada.length; i++) {
      for (let j = i + 1; j < camada.length; j++) {
        const a = camada[i];
        const b = camada[j];
        for (const arq1 of arquivosDe.get(a)) {
          for (const arq2 of arquivosDe.get(b)) {
            if (arq1 === arq2 || globMatches(arq1, arq2) || globMatches(arq2, arq1)) {
              conflitos.push({ camada: indice + 1, a, b, arquivo: arq1 === arq2 ? arq1 : `${arq1} ~ ${arq2}` });
            }
          }
        }
      }
    }
  });

  const alguemDeclara = (c) => declaradaDe.get(c.a) || declaradaDe.get(c.b);
  const recusas = conflitos.filter((c) => !alguemDeclara(c));
  const avisos = conflitos.filter(alguemDeclara);
  return { camadas, conflitos, recusas, avisos };
}

/**
 * Glob simples: *, **, ?
 * * não cruza /
 * ** cruza /
 * ? é qualquer caractere (não /)
 */
function globMatches(arquivo, glob) {
  // Barra no fim é PASTA: cobre tudo abaixo dela. Sem isto, `arquivos:
  // scripts/fixtures/escada/` no plano lia como cobertura da pasta e não
  // cobria arquivo nenhum — comparação literal contra um caminho de pasta
  // nunca casa com um caminho de arquivo. O `revisar` recusava por creep os
  // dez arquivos que o plano declarava, sem dizer por quê. Achado em
  // 2026-09-08, fechando o fluxo aclopar-ponytail.
  if (glob.endsWith('/')) {
    return arquivo.startsWith(glob);
  }

  // Simples: se não tem *, **, ou ?, é match literal
  if (!glob.includes('*') && !glob.includes('?')) {
    return arquivo === glob;
  }

  // Converte glob para regex. Escapa TODO metacaractere de regex antes de
  // converter os curingas (#518, volta 2): sem isto `app/[id]/**` não casava
  // `app/[id]/page.tsx`, `c++/*` lançava SyntaxError e `(1)` virava grupo.
  // `*` e `?` ficam de fora do escape: são os curingas convertidos abaixo.
  let pattern = glob
    .replace(/[.+^${}()|[\]\\]/g, '\\$&')
    .replace(/\//g, '/');

  // ** em qualquer lugar cruza /
  pattern = pattern.replace(/\*\*/g, '<<<DOUBLESTAR>>>');
  // * em qualquer lugar não cruza /
  pattern = pattern.replace(/\*/g, '[^/]*');
  // ? é qualquer caractere (não /)
  pattern = pattern.replace(/\?/g, '[^/]');
  // Restaura **
  pattern = pattern.replace(/<<<DOUBLESTAR>>>/g, '.*');

  // Âncora sempre (#518, D5): o glob casa o caminho inteiro, nunca um
  // prefixo. Sem isto, `src/*` casava `src/a/b.txt` (* não cruza / só vale
  // se a âncora existir) e `*.md` casava `docs/x.md`.
  pattern = '^' + pattern + '$';

  const regex = new RegExp(pattern);
  return regex.test(arquivo);
}

const EXTENSOES_JS = ['.cjs', '.js', '.mjs', '.ts'];

/**
 * Caminhos absolutos normalizados que um texto de JS importa por caminho relativo,
 * resolvidos contra `dir` (a pasta do arquivo que contém o texto). Reconhece cinco
 * formas: `require('./x')`, `require('../x.cjs')`, `import y from './x'`, `import('./x')`
 * e `require(path.join(__dirname, '<lit>', ..., '<lit>'))` com todos os argumentos
 * literais. `require` com variável e módulo de pacote ficam fora.
 */
function alvosDeRequire(texto, dir) {
  const alvos = new Set();
  const relativos = [
    /\brequire\(\s*(['"])(\.{1,2}\/[^'"]+)\1\s*\)/g,
    /\bimport\(\s*(['"])(\.{1,2}\/[^'"]+)\1\s*\)/g,
    /\bfrom\s+(['"])(\.{1,2}\/[^'"]+)\1/g,
  ];
  for (const re of relativos) {
    for (const m of texto.matchAll(re)) {
      alvos.add(path.resolve(dir, m[2]));
    }
  }
  const juntado = /\brequire\(\s*path\.join\(\s*__dirname((?:\s*,\s*(['"])[^'"]*\2)+)\s*\)\s*\)/g;
  for (const m of texto.matchAll(juntado)) {
    const partes = [...m[1].matchAll(/(['"])([^'"]*)\1/g)].map((p) => p[2]);
    alvos.add(path.resolve(path.join(dir, ...partes)));
  }
  return [...alvos];
}

function ehArquivo(caminho) {
  try {
    return fs.statSync(caminho).isFile();
  } catch {
    return false;
  }
}

/**
 * Acoplamento por require entre tarefas da mesma camada (D6, 2026-10-24). Para cada
 * par de tarefas da mesma camada, lê os arquivos declarados de uma (os que existem na
 * árvore em `raiz`; glob e pasta ficam fora) e devolve `{camada, a, b, arquivo, alvo}`
 * quando um deles importa um arquivo declarado pela outra. `a` é a tarefa dona do
 * alvo, `b` a que faz o require; `arquivo` é o da `b`, `alvo` o da `a` como está no
 * plano. Os dois sentidos do par são lidos. Só informa: não mexe em recusa nem em exit.
 */
function acoplamentos(camadas, arquivosDe, raiz) {
  const declarados = new Map();
  for (const [numero, arquivos] of arquivosDe) {
    const lista = [];
    for (const rel of arquivos) {
      if (rel.includes('*') || rel.includes('?') || rel.endsWith('/')) continue;
      const abs = path.resolve(raiz, rel);
      if (!ehArquivo(abs)) continue;
      lista.push({ rel, abs });
    }
    declarados.set(numero, lista);
  }

  const achados = [];
  const vistos = new Set();
  camadas.forEach((camada, indice) => {
    for (const b of camada) {
      for (const { rel: arquivo_rel, abs: arquivo } of declarados.get(b) || []) {
        let texto;
        try {
          texto = fs.readFileSync(arquivo, 'utf8');
        } catch {
          continue;
        }
        const alvos = alvosDeRequire(texto, path.dirname(arquivo));
        for (const a of camada) {
          if (a === b) continue;
          for (const alvo of alvos) {
            const candidatos = new Set([alvo, ...EXTENSOES_JS.map((e) => alvo + e)]);
            const dono = (declarados.get(a) || []).find((d) => candidatos.has(d.abs));
            if (!dono) continue;
            const chave = `${indice}|${a}|${b}|${arquivo_rel}|${dono.rel}`;
            if (vistos.has(chave)) continue;
            vistos.add(chave);
            achados.push({ camada: indice + 1, a, b, arquivo: arquivo_rel, alvo: dono.rel });
          }
        }
      }
    }
  });
  return achados;
}

module.exports = { calcularCamadas, ErroCamadas, parseDependencias, globMatches, acoplamentos, alvosDeRequire };
