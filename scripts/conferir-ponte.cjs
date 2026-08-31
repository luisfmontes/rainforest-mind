#!/usr/bin/env node
/**
 * Confere se o bloco gerado de `CLAUDE.md`, `AGENTS.md` ou `GEMINI.md` ainda
 * bate com o que `scripts/ponte.cjs` produziria agora, ou se foi editado à mão
 * ou ficou para trás.
 *
 * POR QUE EXISTE, com data. `scripts/ponte.cjs` gera `CLAUDE.md`, `AGENTS.md` ou
 * `GEMINI.md` a partir de `skills/rainforest-mind/SKILL.md` como fonte única. O
 * desenho está certo — mas arquivo derivado sem catraca não permanece derivado. Em
 * 2026-08-23, em `C:\Microsiga\protheus-totvs-agro`, a mesma classe de falha já
 * aconteceu: `CLAUDE.md`, `AGENTS.md` e `GEMINI.md` coexistiam, com 9 linhas
 * divergentes. O que existia só em `CLAUDE.md` era a regra de encoding CP-1252 —
 * que acento em comentário morre irrecuperável num round-trip para UTF-8, e que
 * **compilar não é prova de encoding correto**. `AGENTS.md` estava replicado em 86
 * lugares: quem usava Codex ou Gemini naquele repo **não recebia** o aviso que impede
 * corromper fonte AdvPL em silêncio.
 *
 * A solução é embutir, no bloco gerado, um **hash do SKILL.md no momento da
 * geração**. Isso distingue **"editaram o gerado à mão"** de **"o SKILL.md andou e
 * ninguém regerou"** — os dois produzem o mesmo sintoma, mas requerem ações diferentes.
 *
 * TRÊ VEREDITOS, não dois:
 *
 *   1. bloco bate com o que o SKILL.md produziria agora
 *      -> VERDE, exit 0
 *
 *   2. bloco tem hash, e o hash bate com o SKILL.md atual, mas o conteúdo não
 *      -> VERMELHO: editado à mão, nomeando a(s) linha(s) divergente(s)
 *
 *   3. bloco tem hash, e o hash NÃO bate com o SKILL.md atual
 *      -> VERMELHO: o derivado ficou para trás, dizendo o que mudou na fonte
 *
 *   4. bloco **sem** hash (gerado antes desta catraca) e conteúdo diverge
 *      -> VERMELHO honesto: "desatualizado ou editado — não dá para distinguir;
 *         regere para a catraca passar a valer"
 *
 * A última linha preserva compatibilidade: arquivos que já existem lá fora continuam
 * sendo conferidos, só não ganham o diagnóstico fino até serem regerados.
 *
 * Uso:
 *   node scripts/conferir-ponte.cjs <arquivo>      # confere CLAUDE.md, AGENTS.md ou GEMINI.md
 *   node scripts/conferir-ponte.cjs <arquivo> --json
 *
 * Exit:
 *   0  bloco está em sincronia com o SKILL.md atual
 *   1  erro de uso ou arquivo não encontrado
 *   2  RECUSADO — bloco editado à mão ou ficou para trás
 */

'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

// Importar funções compartilhadas de ponte
const { corpo, raizDeDados: raizDeDadosShared, AGENTES: AGENTES_SHARED, lerProjetoMd, hashDoArquivo } =
  require('../hooks/lib/ponte-corpo.cjs');

const CODIGO_ROOT = path.resolve(__dirname, '..');

// O SKILL.md pode estar em dois lugares:
// 1. Se o arquivo sendo conferido é um repo com SKILL.md (repo de teste) → usa aquele
// 2. Senão → usa o SKILL.md do plugin
/**
 * Onde mora a VERDADE contra a qual o derivado e conferido.
 *
 * E sempre o SKILL.md do plugin, e nunca um SKILL.md que por acaso esteja ao lado do
 * arquivo conferido. A primeira versao procurava no mesmo diretorio primeiro, e isso
 * e um caminho de resposta ERRADA em silencio: o arquivo derivado nasce para viver no
 * repositorio de OUTRA pessoa, onde nao ha SKILL.md nenhum — mas se houvesse um, por
 * qualquer motivo, a conferencia passaria a medir contra a fonte errada sem dizer
 * nada, e um "CONFERIDO" e' justamente o que ninguem vai investigar.
 *
 * O override existe so' para a bateria, que precisa mexer na fonte sem tocar no
 * SKILL.md real do plugin — e ele e' EXPLICITO (--skill), nunca inferido.
 */
function resolverSkillMd(_arquivoConferido, skillExplicito) {
  if (skillExplicito) return path.resolve(skillExplicito);
  const pluginRoot = path.resolve(__dirname, '..');
  return path.join(pluginRoot, 'skills', 'rainforest-mind', 'SKILL.md');
}

const FIM = '<!-- rainforest-mind:fim -->';
const FIM_PROJETO = '<!-- rainforest-mind:projeto:fim -->';


/**
 * Extrai hash do marcador de início, se existir.
 * Formato: "<!-- rainforest-mind:inicio — ... — hash:XXXXXXXX... -->"
 */
function extrairHashDoMarcador(linha) {
  const m = linha.match(/hash:([0-9a-f]{16})/);
  return m ? m[1] : null;
}

/**
 * Extrai o bloco gerado entre INICIO e FIM.
 * Devolve: { linhas: [...], hashNoMarcador: "..." | null, temBloco: true/false }
 */
function extrairBlocoGerado(texto) {
  const inicioMatch = texto.match(/<!-- rainforest-mind:inicio[^>]*-->/);
  if (!inicioMatch || !texto.includes(FIM)) {
    return { linhas: [], hashNoMarcador: null, temBloco: false };
  }

  const hashNoMarcador = extrairHashDoMarcador(inicioMatch[0]);
  const inicioIdx = inicioMatch.index;
  const fimIdx = texto.indexOf(FIM);
  const blocoCompleto = texto.slice(inicioIdx, fimIdx + FIM.length);

  // Extrai as linhas do conteúdo, sem os marcadores
  const linhas = blocoCompleto
    .split(/\r?\n/)
    .slice(1, -1) // Remove linha do INICIO e linha do FIM
    .map(l => l.trim());

  return { linhas, hashNoMarcador, temBloco: true };
}

/**
 * Extrai o bloco de projeto entre rainforest-mind:projeto:inicio e rainforest-mind:projeto:fim.
 * Devolve: { linhas: [...], hashNoMarcador: "..." | null, temBloco: true/false }
 */
function extrairBlocoProjetoGerado(texto) {
  // O gerador escreve cada marcador ocupando a LINHA INTEIRA — a âncora multiline
  // espelha isso na leitura. Menção em prosa (marcador no meio de uma frase) nunca
  // casa, e o fim considerado é o primeiro APÓS o início (tarefa 21).
  const inicioMatch = texto.match(/^<!-- rainforest-mind:projeto:inicio[^>]*-->\r?$/m);
  if (!inicioMatch) {
    return { linhas: [], hashNoMarcador: null, temBloco: false };
  }
  const reFim = /^<!-- rainforest-mind:projeto:fim -->\r?$/gm;
  reFim.lastIndex = inicioMatch.index;
  const fimMatch = reFim.exec(texto);
  if (!fimMatch) {
    return { linhas: [], hashNoMarcador: null, temBloco: false };
  }

  const hashNoMarcador = extrairHashDoMarcador(inicioMatch[0]);
  const blocoCompleto = texto.slice(inicioMatch.index, fimMatch.index + fimMatch[0].length);

  // Extrai as linhas do conteúdo, sem os marcadores
  const linhas = blocoCompleto
    .split(/\r?\n/)
    .slice(1, -1) // Remove linha do INICIO e linha do FIM
    .map(l => l.trim());

  return { linhas, hashNoMarcador, temBloco: true };
}

/**
 * O núcleo das regras, da mesma fonte e pelo mesmo caminho do hook de abertura.
 */
function nucleoDasRegras(caminhoSkill) {
  let lib;
  try {
    const pluginRoot = path.resolve(__dirname, '..');
    lib = require(path.join(pluginRoot, 'hooks', 'lib', 'contexto-sessao.cjs'));
  } catch (e) {
    throw new Error(`não consegui carregar hooks/lib/contexto-sessao.cjs: ${e.message}`);
  }
  let skill;
  try {
    skill = fs.readFileSync(caminhoSkill, 'utf8');
  } catch (e) {
    throw new Error(`não consegui ler ${caminhoSkill}: ${e.message}`);
  }
  const nucleo = lib.extrairNucleo(lib.filtrarRegras(skill)).trim();
  return nucleo;
}

// raizDeDados() foi movida para o módulo compartilhado, chamar de lá
function raizDeDados() {
  return raizDeDadosShared(CODIGO_ROOT);
}

// Usar AGENTES do módulo compartilhado
const AGENTES = AGENTES_SHARED;

/**
 * Compara dois textos e retorna se são iguais (removendo espaços em branco extras).
 * Retorna true se forem iguais, false se diferentes.
 */
function textoIgual(atual, esperado) {
  // Normaliza espaçamento: remove espaços extras e compara
  const normalizarTexto = (t) => t
    .split(/\r?\n/)
    .map(linha => linha.trim())
    .filter(linha => linha.length > 0)
    .join('\n');

  return normalizarTexto(atual) === normalizarTexto(esperado);
}

/**
 * Encontra as primeiras linhas que divergem (com normalização).
 */
function linhasDivergentes(atual, esperado) {
  const atualllinhas = atual.split(/\r?\n/);
  const esperadoLinhas = esperado.split(/\r?\n/);
  const indices = [];
  const linhas = Math.max(atualllinhas.length, esperadoLinhas.length);
  for (let i = 0; i < linhas && indices.length < 5; i++) {
    const aLine = (atualllinhas[i] || '').trim();
    const eLine = (esperadoLinhas[i] || '').trim();
    if (aLine !== eLine) {
      indices.push({ numero: i + 1, atual: aLine.slice(0, 80), esperado: eLine.slice(0, 80) });
    }
  }
  return indices;
}

/**
 * Confere o bloco de projeto (se existir).
 * Retorna { veredito: 'conferido' | 'editado-a-mao' | 'ficou-para-tras' | 'sem-bloco' | 'sem-entrevista', msg, linhasDivergentes?: [...] }
 */
function conferirBlocoProjetoGerado(texto, caminhoProjetoMd, raizAlvo) {
  // Extrai o bloco de projeto do arquivo gerado
  const { linhas: linhasAtuais, hashNoMarcador, temBloco } = extrairBlocoProjetoGerado(texto);

  // Se não tem bloco, é porque não há projeto.md no alvo — isso não é erro
  if (!temBloco) {
    return {
      veredito: 'sem-bloco',
      msg: 'Arquivo não contém bloco de projeto (nenhuma entrevista foi rodada)'
    };
  }

  // Usa lerProjetoMd do módulo compartilhado para extrair o bloco de projeto.md
  const blocoProjetoMdCompleto = lerProjetoMd(raizAlvo);

  if (!blocoProjetoMdCompleto) {
    // projeto.md não existe, não pode ser lido, ou não tem marcadores válidos
    // mas o bloco existe no arquivo — o arquivo foi regenerado e o projeto.md sumiu
    return {
      veredito: 'ficou-para-tras',
      temBloco: true,
      msg: 'O arquivo tem bloco de projeto, mas docs/rainforest/projeto.md não existe, não pode ser lido, ou tem marcadores inválidos'
    };
  }
  const linhasEsperadas = blocoProjetoMdCompleto
    .split(/\r?\n/)
    .slice(1, -1) // Remove linha do INICIO e linha do FIM
    .map(l => l.trim());

  // Normaliza conteúdo para comparação
  const conteudoAtual = linhasAtuais.join('\n');
  const conteudoEsperado = linhasEsperadas.join('\n');

  // CASO 1: Bloco bate -> VERDE
  if (textoIgual(conteudoAtual, conteudoEsperado)) {
    return {
      veredito: 'conferido',
      temBloco: true,
      msg: 'Bloco de projeto está em sincronia com docs/rainforest/projeto.md'
    };
  }

  // CASO 2/3: Há divergência
  if (hashNoMarcador) {
    const hashAtualProjetoMd = hashDoArquivo(caminhoProjetoMd);
    if (hashNoMarcador === hashAtualProjetoMd) {
      // CASO 2: Hash bate, conteúdo não -> editado à mão
      const divergentes = linhasDivergentes(conteudoAtual, conteudoEsperado);
      return {
        veredito: 'editado-a-mao',
        temBloco: true,
        msg: 'Bloco de projeto foi editado à mão — conteúdo diverge do docs/rainforest/projeto.md, mas o hash bate',
        linhasDivergentes: divergentes
      };
    } else {
      // CASO 3: Hash não bate -> projeto.md andou, arquivo ficou para trás
      return {
        veredito: 'ficou-para-tras',
      temBloco: true,
        msg: 'Bloco de projeto ficou para trás — o docs/rainforest/projeto.md mudou desde a última geração'
      };
    }
  } else {
    // CASO 4: Sem hash e com divergência -> ambíguo
    return {
      veredito: 'ficou-para-tras',
      temBloco: true,
      msg: 'Bloco de projeto foi gerado antes da catraca de hash — não dá para saber se foi editado ou se o docs/rainforest/projeto.md mudou'
    };
  }
}

function main() {
  const args = process.argv.slice(2);
  const json = args.includes('--json');
  // Override explicito da fonte, so para a bateria — ver resolverSkillMd.
  const iSkill = args.indexOf('--skill');
  const skillExplicito = iSkill !== -1 && args[iSkill + 1] ? args[iSkill + 1] : null;
  // O valor de --skill NAO pode ser confundido com o arquivo alvo: sem esta exclusao,
  // `conferir-ponte.cjs --skill x.md CLAUDE.md` conferiria `x.md`.
  const alvo = args.find((a, i) => !a.startsWith('--') && !(i > 0 && args[i - 1] === '--skill'));

  if (!alvo) {
    console.error('uso: node scripts/conferir-ponte.cjs <arquivo>|- [--json] [--skill <caminho>]');
    process.exit(1);
  }

  let texto;
  try {
    texto = alvo === '-' ? fs.readFileSync(0, 'utf8') : fs.readFileSync(alvo, 'utf8');
  } catch (e) {
    if (!json) console.error(`erro: não consegui ler ${alvo}`);
    process.exit(1);
  }

  // Extrai o bloco gerado do arquivo
  const { linhas: linhasAtuais, hashNoMarcador, temBloco } = extrairBlocoGerado(texto);

  if (!temBloco) {
    const resultado = { arquivo: alvo, situacao: 'sem-bloco', msg: 'Arquivo não contém marcador de bloco gerado' };
    if (json) {
      console.log(JSON.stringify(resultado, null, 2));
    } else {
      console.log(`RECUSADO — ${resultado.msg}`);
    }
    process.exit(2);
  }

  // Resolve o caminho do SKILL.md
  const caminhoSkill = resolverSkillMd(alvo, skillExplicito);

  // Gera o que seria produzido agora
  let nucleoEsperado;
  try {
    nucleoEsperado = nucleoDasRegras(caminhoSkill);
  } catch (e) {
    const resultado = { arquivo: alvo, situacao: 'erro-skill', msg: e.message };
    if (json) {
      console.log(JSON.stringify(resultado, null, 2));
    } else {
      console.log(`RECUSADO — ${resultado.msg}`);
    }
    process.exit(1);
  }

  const hashAtual = hashDoArquivo(caminhoSkill);
  const dados = raizDeDados();

  // Descobre qual agente baseado no nome do arquivo
  const nomeArquivo = path.basename(alvo).toLowerCase();
  let agente = null;
  for (const key of Object.keys(AGENTES)) {
    if (AGENTES[key].arquivo.toLowerCase() === nomeArquivo) {
      agente = AGENTES[key];
      break;
    }
  }

  if (!agente) {
    const resultado = { arquivo: alvo, situacao: 'arquivo-desconhecido', msg: `Arquivo ${nomeArquivo} não é CLAUDE.md, AGENTS.md ou GEMINI.md` };
    if (json) {
      console.log(JSON.stringify(resultado, null, 2));
    } else {
      console.log(`RECUSADO — ${resultado.msg}`);
    }
    process.exit(1);
  }

  // Gera o conteúdo esperado
  const conteudoEsperadoFull = corpo(agente, nucleoEsperado, dados).trim();
  const linhasEsperadas = conteudoEsperadoFull.split(/\r?\n/).map(l => l.trim());

  // Três casos de veredito
  // Compara o conteúdo normalizado (sem espaços extras)
  const conteudoAtual = linhasAtuais.join('\n');
  const conteudoEsperado = linhasEsperadas.join('\n');

  // CASO 1: Bloco atual bate com o esperado -> VERDE
  if (textoIgual(conteudoAtual, conteudoEsperado)) {
    // Se o bloco de regras passou, confira também o bloco de projeto
    // Resolver o caminho do alvo para suportar caminhos relativos e POSIX
    let raizAlvo = null;
    if (alvo !== '-') {
      const caminhoResolvido = path.resolve(alvo);
      raizAlvo = path.dirname(caminhoResolvido);
    }
    const diretorioAlvo = raizAlvo;
    const caminhoProjetoMd = raizAlvo ? path.join(raizAlvo, 'docs', 'rainforest', 'projeto.md') : null;

    const resultadoProjeto = conferirBlocoProjetoGerado(texto, caminhoProjetoMd, raizAlvo);

    // Se há divergência no bloco de projeto, reporta como RECUSADO
    if (resultadoProjeto.veredito === 'editado-a-mao' || resultadoProjeto.veredito === 'ficou-para-tras') {
      if (json) {
        console.log(JSON.stringify({
          arquivo: alvo,
          situacao: 'bloco-projeto-divergente',
          projetoVeredito: resultadoProjeto.veredito,
          msg: resultadoProjeto.msg,
          linhasDivergentes: resultadoProjeto.linhasDivergentes
        }, null, 2));
      } else {
        console.log(`RECUSADO — ${resultadoProjeto.msg}\n`);
        if (resultadoProjeto.linhasDivergentes && resultadoProjeto.linhasDivergentes.length > 0) {
          console.log('Primeiras linhas divergentes no bloco de projeto:');
          for (const div of resultadoProjeto.linhasDivergentes.slice(0, 3)) {
            console.log(`  linha ${div.numero}: ${div.atual}`);
          }
        }
      }
      process.exit(2);
    }

    // Caso contrário, bloco de projeto está OK (ou não existe)
    if (json) {
      console.log(JSON.stringify({
        arquivo: alvo,
        situacao: 'verde',
        hashNoMarcador,
        hashAtual,
        msg: 'Bloco está em sincronia com o SKILL.md atual',
        projetoVeredito: resultadoProjeto.veredito
      }, null, 2));
    } else {
      console.log('CONFERIDO — bloco gerado bate com o SKILL.md atual.');
      if (resultadoProjeto.temBloco) {
        console.log(`Bloco de projeto: ${resultadoProjeto.veredito}`);
      }
    }
    process.exit(0);
  }

  // CASO 2/3: Há divergência
  // Se tem hash, verifica se é edição à mão ou ficou para trás
  // Se não tem hash, é ambíguo

  if (hashNoMarcador) {
    if (hashNoMarcador === hashAtual) {
      // CASO 2: Hash bate, conteúdo não -> editado à mão
      const divergentes = linhasDivergentes(conteudoAtual, conteudoEsperado);
      const resultado = {
        arquivo: alvo,
        situacao: 'editado-a-mao',
        hashNoMarcador,
        linhasDivergentes: divergentes,
        msg: `Bloco foi editado à mão — conteúdo diverge do SKILL.md, mas o hash bate`
      };
      if (json) {
        console.log(JSON.stringify(resultado, null, 2));
      } else {
        console.log('RECUSADO — bloco foi editado à mão.\n');
        console.log(`O conteúdo diverge do SKILL.md, mas o hash ${hashNoMarcador} ainda bate, o que significa`);
        console.log('que você editou manualmente o arquivo gerado. Mude o SKILL.md e regere com:');
        console.log(`\n  node scripts/ponte.cjs --alvo . --agente ${path.basename(alvo, '.md').toLowerCase()} --aplicar\n`);
        if (divergentes.length > 0) {
          console.log('Primeiras linhas divergentes:');
          for (const div of divergentes.slice(0, 3)) {
            console.log(`  linha ${div.numero}: ${div.atual}`);
          }
        }
      }
      process.exit(2);
    } else {
      // CASO 3: Hash não bate -> SKILL.md andou, arquivo ficou para trás
      const resultado = {
        arquivo: alvo,
        situacao: 'ficou-para-tras',
        hashNoMarcador,
        hashAtual,
        msg: 'O SKILL.md mudou desde a última geração — bloco está desatualizado'
      };
      if (json) {
        console.log(JSON.stringify(resultado, null, 2));
      } else {
        console.log('RECUSADO — o SKILL.md mudou.\n');
        console.log(`O bloco foi gerado com hash ${hashNoMarcador}, mas o SKILL.md atual tem hash ${hashAtual}.`);
        console.log('Regere o arquivo com:\n');
        console.log(`  node scripts/ponte.cjs --alvo . --agente ${path.basename(alvo, '.md').toLowerCase()} --aplicar`);
      }
      process.exit(2);
    }
  } else {
    // CASO 4: Sem hash e com divergência -> ambíguo, compatibilidade para trás
    const resultado = {
      arquivo: alvo,
      situacao: 'desatualizado-ou-editado',
      hashNoMarcador: null,
      hashAtual,
      msg: 'Bloco foi gerado antes da catraca de hash — não dá para distinguir edição manual de SKILL.md que mudou'
    };
    if (json) {
      console.log(JSON.stringify(resultado, null, 2));
    } else {
      console.log('RECUSADO — bloco está desatualizado ou foi editado.\n');
      console.log('O bloco foi gerado ANTES de a catraca de hash ser implementada, e diverge do SKILL.md atual.');
      console.log('Não dá para saber se o arquivo foi editado à mão ou se o SKILL.md mudou.\n');
      console.log('Para que a catraca passe a valer e ganhar diagnóstico fino, regere o arquivo com:\n');
      console.log(`  node scripts/ponte.cjs --alvo . --agente ${path.basename(alvo, '.md').toLowerCase()} --aplicar`);
    }
    process.exit(2);
  }
}

if (require.main === module) main();
module.exports = { extrairBlocoGerado, extrairBlocoProjetoGerado, linhasDivergentes };
