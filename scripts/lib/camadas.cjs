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
 * Entrada: [{numero, dependeDe: number[], arquivos: string[], paralelaDeclarada?: boolean}]
 * Saída: {camadas: number[][], conflitos: [{camada, a, b, arquivo}],
 *         recusas: [...], avisos: [...]}
 * `conflitos` lista todo arquivo em comum na mesma camada. `recusas` são os que
 * nenhuma das duas tarefas declara `paralela:`; `avisos`, os que alguma declara
 * (emenda D2 de 2026-10-13: plano antigo serializado por `paralela: nao` passa com aviso).
 * Ciclo e dependência inexistente lançam ErroCamadas, nomeando as tarefas.
 */

class ErroCamadas extends Error {
  constructor(mensagem, detalhe = {}) {
    super(mensagem);
    this.name = 'ErroCamadas';
    this.detalhe = detalhe;
  }
}

/**
 * Lê o valor de `depende de:`. `nenhuma` (ou vazio) vira []; números separados
 * por vírgula ou espaço viram a lista. Texto sem número lança ErroCamadas.
 */
function parseDependencias(texto) {
  const t = (texto || '').trim();
  if (t === '' || /^nenhuma$/i.test(t)) return [];
  if (!/\d/.test(t)) {
    throw new ErroCamadas(`depende de: "${t}" não lista tarefa nenhuma (use "nenhuma" ou números)`);
  }
  return [...new Set((t.match(/\d+/g) || []).map((n) => parseInt(n, 10)))];
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

  // Converte glob para regex
  let pattern = glob
    .replace(/\./g, '\\.')
    .replace(/\//g, '/');

  // ** em qualquer lugar cruza /
  pattern = pattern.replace(/\*\*/g, '<<<DOUBLESTAR>>>');
  // * em qualquer lugar não cruza /
  pattern = pattern.replace(/\*/g, '[^/]*');
  // ? é qualquer caractere (não /)
  pattern = pattern.replace(/\?/g, '[^/]');
  // Restaura **
  pattern = pattern.replace(/<<<DOUBLESTAR>>>/g, '.*');

  // Âncora: se não começar com *, é desde o início
  if (!glob.startsWith('*')) {
    pattern = '^' + pattern;
  }
  // Se não terminar com *, é até o final
  if (!glob.endsWith('*')) {
    pattern = pattern + '$';
  }

  const regex = new RegExp(pattern);
  return regex.test(arquivo);
}

module.exports = { calcularCamadas, ErroCamadas, parseDependencias, globMatches };
