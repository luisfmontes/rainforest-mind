#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

const FILE_TYPE_ENUM = ['code', 'document', 'paper', 'image', 'rationale', 'concept'];
const CONFIDENCE_ENUM = ['EXTRACTED', 'INFERRED', 'AMBIGUOUS'];

function validarNo(no, index, caminhoBase) {
  if (!no || typeof no !== 'object') {
    return { valido: false, campo: 'nos[' + index + ']' };
  }

  if (typeof no.id !== 'string' || no.id === '') {
    return { valido: false, campo: 'id' };
  }

  // Valida que id não permite path traversal
  if (no.id.includes('..') || no.id.includes('/') || no.id.includes('\\')) {
    return { valido: false, campo: 'id' };
  }

  if (typeof no.caminho !== 'string' || no.caminho === '') {
    return { valido: false, campo: 'caminho' };
  }

  if (typeof no.titulo !== 'string' || no.titulo === '') {
    return { valido: false, campo: 'titulo' };
  }

  if (typeof no.resumo !== 'string' || no.resumo === '') {
    return { valido: false, campo: 'resumo' };
  }

  if (!FILE_TYPE_ENUM.includes(no.file_type)) {
    return { valido: false, campo: 'file_type' };
  }

  if (!CONFIDENCE_ENUM.includes(no.confidence)) {
    return { valido: false, campo: 'confidence' };
  }

  return { valido: true };
}

function validarAresta(aresta, index) {
  if (!aresta || typeof aresta !== 'object') {
    return { valido: false, campo: 'arestas[' + index + ']' };
  }

  if (typeof aresta.de !== 'string' || aresta.de === '') {
    return { valido: false, campo: 'de' };
  }

  if (typeof aresta.para !== 'string' || aresta.para === '') {
    return { valido: false, campo: 'para' };
  }

  if (typeof aresta.tipo !== 'string' || aresta.tipo === '') {
    return { valido: false, campo: 'tipo' };
  }

  if (typeof aresta.via !== 'string' || aresta.via === '') {
    return { valido: false, campo: 'via' };
  }

  return { valido: true };
}

function validarGrafo(grafo) {
  if (!grafo || typeof grafo !== 'object') {
    return { valido: false, campo: 'grafo' };
  }

  if (!Array.isArray(grafo.nos)) {
    return { valido: false, campo: 'nos' };
  }

  if (!Array.isArray(grafo.arestas)) {
    return { valido: false, campo: 'arestas' };
  }

  // Validar cada nó
  for (let i = 0; i < grafo.nos.length; i++) {
    const resultado = validarNo(grafo.nos[i], i, null);
    if (!resultado.valido) {
      return resultado;
    }
  }

  // Validar cada aresta
  for (let i = 0; i < grafo.arestas.length; i++) {
    const resultado = validarAresta(grafo.arestas[i], i);
    if (!resultado.valido) {
      return resultado;
    }
  }

  return { valido: true };
}

function main() {
  if (process.argv.length < 3) {
    console.error('Uso: validar-grafo.cjs <arquivo-json>');
    process.exit(1);
  }

  const caminhoArquivo = process.argv[2];

  try {
    const conteudo = fs.readFileSync(caminhoArquivo, 'utf8');
    const grafo = JSON.parse(conteudo);

    const resultado = validarGrafo(grafo);

    if (resultado.valido) {
      console.log('valido');
      process.exit(0);
    } else {
      console.log('invalido: ' + resultado.campo);
      process.exit(1);
    }
  } catch (erro) {
    console.error('Erro ao processar arquivo:', erro.message);
    process.exit(1);
  }
}

main();
