#!/usr/bin/env node
// @categoria: sensor
/**
 * Confere as âncoras de um mapa da arqueologia contra o fonte: cada citação
 * tem que apontar para um arquivo que existe, para linhas que existem e, quando
 * carrega símbolo, para um lugar onde o símbolo aparece.
 *
 * POR QUE EXISTE. A releitura dos `CONFIRMADO` era feita por agente, que relia
 * cada `arquivo:linha` à mão (skills/arqueologia/SKILL.md, passo de conferência).
 * A parte mecânica (o arquivo existe, a linha cabe nele, o nome da função ainda
 * está lá) não precisa de agente: sai por script. Mecanismo de referência:
 * BMAD-METHOD `recon_kit.py anchors` (recon_kit.py:389-481, `symbol_found`).
 *
 * FORMAS ACEITAS (o que o mapa escreve, o que este script lê):
 *   `arquivo.ext:N`          linha N
 *   `arquivo.ext:N-M`        intervalo; as DUAS pontas têm que caber no arquivo
 *                            e N tem que ser menor ou igual a M (N > M sai linha-fora)
 *   `arquivo.ext#Simbolo`    símbolo em qualquer lugar do arquivo
 *   `arquivo.ext:N` + símbolo entre crases logo após a citação, com ou sem
 *     parênteses: `` `zfiscal01.prw:120` (`MontaNFe`) `` ou
 *     `` zfiscal01.prw:120 `MontaNFe` ``. O símbolo tem que aparecer entre a
 *     linha N-80 e a N (no intervalo, entre N-80 e M).
 *   O caminho pode começar com `.` (diretório oculto: `.github/ci.yml`) ou com
 *     `./` (normalizado para o caminho relativo à raiz, sem o `./` no rótulo).
 *   A extensão é obrigatória (ao menos uma letra depois do ponto), então
 *   horário (`10:30`) e número decimal não viram citação. URLs `http(s)://`
 *   são ignoradas. `host.com:8080` (TLD comum, com porta) também não vira
 *   citação, quando nenhum arquivo `host.com` existe sob a raiz.
 *
 * CITAÇÃO SÓ PELO NOME. Se o caminho citado não existe sob a raiz, o script
 * procura o nome do arquivo (sem diferenciar caixa) em toda a raiz, ignorando
 * `.git` e `node_modules` e sem seguir links simbólicos. Um único acerto vale:
 * a linha de saída mostra o caminho achado. Mais de um sai `ambiguo`, listando
 * até 3 candidatos e a contagem do resto. Nenhum sai `arquivo-ausente`.
 *
 * FORA DO ESCOPO (sai `arquivo-ausente`, conservador):
 *   - caminho com drive (`C:\...`): o trecho que começa no separador não é
 *     reconstruído; a citação sai como ausente, sem busca por nome
 *   - caminho com espaço (`Ponto de Entrada\...`): o script só enxerga o trecho
 *     sem espaço; ele pode não existir (`arquivo-ausente`) ou casar por nome,
 *     e nesse caso a saída mostra o caminho achado, não o do mapa
 *
 * STATUS, por âncora:
 *   ok                arquivo existe, linhas existem, símbolo (se houver) acha-se
 *   arquivo-ausente   o arquivo não existe sob a raiz, nem por nome (--repo, padrão: cwd)
 *   ambiguo           o nome aparece em mais de um lugar da raiz (lista os candidatos)
 *   fora-da-raiz      o caminho resolvido cai fora da raiz; o arquivo não é lido
 *   linha-fora        alguma ponta da linha/intervalo cai fora do arquivo, ou N > M
 *   simbolo-ausente   o símbolo não aparece na janela (ou no arquivo, na forma #)
 *
 * SÍMBOLO. Em `.prw`, `.prx`, `.tlpp` e `.ch` (ADVPL/TLPP) a busca do símbolo não
 * diferencia caixa (o compilador também não); nos demais, diferencia.
 *
 * CODIFICAÇÃO. O fonte é lido como bytes. Se for UTF-8 válido, decodifica como
 * UTF-8; se não for, decodifica como latin1 (ADVPL é CP-1252). Nunca lança por
 * codificação: uma linha com `\xe7` em CP-1252 não vira falha falsa.
 *
 * SAÍDA. Uma linha por âncora (`<status> <citação>`) e o resumo
 * `N âncoras: X ok, Y falhas`. Mapa sem âncora sai `0 âncoras: 0 ok, 0 falhas`.
 * Exit: 0 tudo ok (ou zero âncoras) · 1 alguma falha ou regra sem-campos · 2 uso ou mapa/raiz inexistente.
 *
 * REGRAS IMPLÍCITAS (D5 do lote 3 de apoio-ao-dev). A seção `## Regras implícitas`
 * vai do cabeçalho até o próximo `## `. Regra nova abre com `**R<n> — <título>**`
 * (hífen ou travessão) e traz `Verificada em: <sha>` e `Teste: <bateria ou caso> |
 * nenhum` nas linhas seguintes. Estado por regra: `testada` (os dois campos, teste
 * real), `sem-teste` (`Teste: nenhum`, aviso), `sem-campos` (falta um dos dois campos,
 * falha, exit 1). Parágrafo da seção sem regra aberta que não abre com o marcador é
 * formato antigo: sai `regra sem-id` como aviso, sem mudar o exit. Com regra aberta,
 * parágrafo novo é corpo dela. Sem a seção, a saída é a de sempre.
 *
 * Uso: node scripts/conferir-ancoras.cjs <mapa.md> [--repo <raiz>]
 */
const fs = require('fs');
const path = require('path');

const JANELA = 80;
const EXT_ADVPL = new Set(['.prw', '.prx', '.tlpp', '.ch']);
// extensões que são, na prática, TLD de domínio: `host.com:8080` não é âncora sem arquivo
const EXT_TLD = new Set(['com', 'net', 'org', 'io', 'br', 'gov', 'edu', 'info', 'dev', 'app']);
const IGNORADAS = new Set(['.git', 'node_modules']);

const USO = `uso: node scripts/conferir-ancoras.cjs <mapa.md> [--repo <raiz>]
  <mapa.md>   mapa da arqueologia cujas âncoras serão conferidas
  --repo      raiz do código onde os arquivos citados moram (padrão: diretório atual)`;

function erroUso(msg) {
  console.error(`erro: ${msg}\n${USO}`);
  process.exit(2);
}

const args = process.argv.slice(2);
let mapa = null;
let raiz = process.cwd();
for (let i = 0; i < args.length; i++) {
  const a = args[i];
  if (a === '--repo') {
    if (i + 1 >= args.length) erroUso('--repo veio sem valor');
    raiz = args[++i];
  } else if (a.startsWith('--')) {
    erroUso(`opção desconhecida: ${a}`);
  } else if (mapa === null) {
    mapa = a;
  } else {
    erroUso(`argumento extra: ${a}`);
  }
}
if (mapa === null) erroUso('falta o mapa');
if (!fs.existsSync(mapa) || !fs.statSync(mapa).isFile()) erroUso(`mapa inexistente: ${mapa}`);
if (!fs.existsSync(raiz) || !fs.statSync(raiz).isDirectory()) erroUso(`--repo não é uma pasta: ${raiz}`);
const raizAbs = path.resolve(raiz);

// caminho(.ext) seguido de :N, :N-M ou #Simbolo. A extensão exige letra.
const RE_CIT = /([A-Za-z0-9_.][A-Za-z0-9_./\\-]*\.[A-Za-z][A-Za-z0-9]{0,9})(?::(\d+)(?:-(\d+))?(?!\d)|#([A-Za-z_][A-Za-z0-9_]*))/g;
// símbolo entre crases logo após uma citação de linha (com ou sem crase de fechamento e parênteses)
const RE_SIMBOLO_DEPOIS = /^`?\s*\(?\s*`([A-Za-z_][A-Za-z0-9_]*)`/;
const RE_URL = /https?:\/\/\S+/g;
// caractere colado antes da citação: ela é só um pedaço de um caminho maior (drive, pasta, acento)
const RE_PARCIAL_ANTES = /[A-Za-z0-9_\\/:.\-\u00C0-\u024F]$/;

function extrairCitacoes(texto) {
  const cits = [];
  texto.split(/\r?\n/).forEach((bruta) => {
    // URL vira espaço de mesmo tamanho: não gera citação, e o resto da linha mantém posição
    const linha = bruta.replace(RE_URL, (m) => ' '.repeat(m.length));
    for (const m of linha.matchAll(RE_CIT)) {
      const arquivo = m[1];
      const parcial = RE_PARCIAL_ANTES.test(linha.slice(0, m.index));
      if (m[4] !== undefined) {
        cits.push({ forma: 'nome', arquivo, ini: null, fim: null, simbolo: m[4], parcial });
        continue;
      }
      const ini = Number(m[2]);
      const fim = m[3] !== undefined ? Number(m[3]) : ini;
      const depois = RE_SIMBOLO_DEPOIS.exec(linha.slice(m.index + m[0].length));
      cits.push({ forma: 'linha', arquivo, ini, fim, simbolo: depois ? depois[1] : null, parcial });
    }
  });
  return cits;
}

function lerFonte(arquivo) {
  const buf = fs.readFileSync(arquivo);
  try {
    return new TextDecoder('utf-8', { fatal: true }).decode(buf);
  } catch (_e) {
    return buf.toString('latin1');
  }
}

function regexSimbolo(sym, flags) {
  return new RegExp(`(?<![A-Za-z0-9_])${sym}(?![A-Za-z0-9_])`, flags);
}

function linhaDentro(linhas, linha) {
  const dentro = linha >= 1 && linha <= linhas.length;
  return dentro;
}

// índice nome (minúsculo) -> caminhos relativos à raiz; montado só quando alguma citação falha no caminho direto
let indice = null;
function indexar() {
  if (indice) return indice;
  indice = new Map();
  const pilha = [raizAbs];
  while (pilha.length) {
    const dir = pilha.pop();
    for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
      if (e.isSymbolicLink()) continue;
      const abs = path.join(dir, e.name);
      if (e.isDirectory()) {
        if (!IGNORADAS.has(e.name)) pilha.push(abs);
        continue;
      }
      if (!e.isFile()) continue;
      const chave = e.name.toLowerCase();
      if (!indice.has(chave)) indice.set(chave, []);
      indice.get(chave).push(path.relative(raizAbs, abs).split(path.sep).join('/'));
    }
  }
  return indice;
}

// acha o arquivo da citação: caminho direto sob a raiz, senão nome único; não lê o conteúdo
function localizar(cit) {
  if (cit.parcial) return { status: 'arquivo-ausente' };
  // `./x` é o mesmo que `x`: o caminho é relativo à raiz, então o prefixo sai do rótulo também
  const sem = cit.arquivo.replace(/^(?:\.[\\/])+/, '');
  const rel = sem.replace(/\\/g, '/');
  const abs = path.resolve(raizAbs, rel);
  const dentro = path.relative(raizAbs, abs);
  if (dentro === '' || path.isAbsolute(dentro) || dentro.split(path.sep)[0] === '..') {
    return { status: 'fora-da-raiz' };
  }
  if (fs.existsSync(abs) && fs.statSync(abs).isFile()) return { abs, exibido: sem };
  const candidatos = indexar().get(path.posix.basename(rel).toLowerCase()) || [];
  if (candidatos.length === 1) return { abs: path.join(raizAbs, candidatos[0]), exibido: candidatos[0] };
  if (candidatos.length > 1) return { status: 'ambiguo', candidatos };
  return { status: 'arquivo-ausente' };
}

function listaCandidatos(c) {
  const resto = c.length > 3 ? ` (+${c.length - 3})` : '';
  return `candidatos: ${c.slice(0, 3).join(', ')}${resto}`;
}

function avaliar(cit, loc) {
  if (loc.status) {
    return { status: loc.status, detalhe: loc.candidatos ? listaCandidatos(loc.candidatos) : '' };
  }
  const linhas = lerFonte(loc.abs).split(/\r?\n/);
  if (linhas.length && linhas[linhas.length - 1] === '') linhas.pop();
  const flags = EXT_ADVPL.has(path.extname(loc.abs).toLowerCase()) ? 'i' : '';
  const re = cit.simbolo ? regexSimbolo(cit.simbolo, flags) : null;

  if (cit.forma === 'nome') {
    return { status: linhas.some((l) => re.test(l)) ? 'ok' : 'simbolo-ausente', detalhe: '' };
  }
  if (cit.ini > cit.fim) return { status: 'linha-fora', detalhe: '' };
  if (!linhaDentro(linhas, cit.ini) || !linhaDentro(linhas, cit.fim)) return { status: 'linha-fora', detalhe: '' };
  if (re) {
    const de = Math.max(1, cit.ini - JANELA);
    for (let n = de; n <= cit.fim; n++) {
      if (re.test(linhas[n - 1])) return { status: 'ok', detalhe: '' };
    }
    return { status: 'simbolo-ausente', detalhe: '' };
  }
  return { status: 'ok', detalhe: '' };
}

function rotulo(cit, exibido) {
  const arq = exibido || cit.arquivo;
  if (cit.forma === 'nome') return `${arq}#${cit.simbolo}`;
  const faixa = cit.fim !== cit.ini ? `${cit.ini}-${cit.fim}` : `${cit.ini}`;
  return `${arq}:${faixa}${cit.simbolo ? ` \`${cit.simbolo}\`` : ''}`;
}

// regra de `## Regras implícitas`: marcador `**R<n> — título**` (hífen ou travessão)
const RE_REGRA = /^(?:[-*]\s+)?\*\*R(\d+)\s+[-—–]\s+.+?\*\*/;
const RE_VERIFICADA = /^(?:[-*]\s+)?Verificada em:\s*(.*)$/;
const RE_TESTE = /^(?:[-*]\s+)?Teste:\s*(.*)$/;

// linhas da seção `## Regras implícitas`, do cabeçalho ao próximo `## `; sem a seção, lista vazia
function secaoRegras(conteudo) {
  const linhas = conteudo.split(/\r?\n/);
  const ini = linhas.findIndex((l) => l.trim() === '## Regras implícitas');
  if (ini === -1) return [];
  const fim = linhas.findIndex((l, i) => i > ini && l.startsWith('## '));
  return linhas.slice(ini + 1, fim === -1 ? undefined : fim);
}

// regra: marcador + campos. Com regra aberta, parágrafo novo (mesmo depois de linha em branco)
// é corpo dela; `sem-id` só sai sem regra aberta. A regra fecha no próximo marcador, no
// próximo título `#` ou no fim da seção. Campos `Verificada em:`/`Teste:` anexam à regra aberta.
function lerRegras(linhas) {
  const itens = [];
  let atual = null;
  let novoParagrafo = true;
  for (const bruta of linhas) {
    const l = bruta.trim();
    if (l.startsWith('#')) { atual = null; novoParagrafo = true; continue; }
    if (l === '') { novoParagrafo = true; continue; }
    const marca = RE_REGRA.exec(l);
    if (marca) {
      atual = { tipo: 'regra', n: marca[1], verificada: null, teste: null, estado: null };
      itens.push(atual);
    } else if (atual && RE_VERIFICADA.test(l)) {
      atual.verificada = RE_VERIFICADA.exec(l)[1].trim();
    } else if (atual && RE_TESTE.test(l)) {
      atual.teste = RE_TESTE.exec(l)[1].trim();
    } else if (novoParagrafo && atual === null) {
      itens.push({ tipo: 'sem-id', estado: 'sem-id', texto: l.slice(0, 60) });
    }
    novoParagrafo = false;
  }
  return itens;
}

const conteudo = fs.readFileSync(mapa, 'utf8');
const cits = extrairCitacoes(conteudo);
let oks = 0;
let contadas = 0;
for (const cit of cits) {
  const loc = localizar(cit);
  // host:porta (`example.com:8080`) não é âncora: TLD sem arquivo sob a raiz
  const ext = cit.arquivo.slice(cit.arquivo.lastIndexOf('.') + 1).toLowerCase();
  if (loc.status === 'arquivo-ausente' && cit.forma === 'linha' && !cit.simbolo && EXT_TLD.has(ext)) continue;
  const r = avaliar(cit, loc);
  if (r.status === 'ok') oks++;
  contadas++;
  console.log(`${r.status} ${rotulo(cit, loc.exibido)}${r.detalhe ? ` ${r.detalhe}` : ''}`);
}
const falhas = contadas - oks;

const regras = lerRegras(secaoRegras(conteudo));
for (const regra of regras) {
  if (regra.tipo === 'sem-id') {
    console.log(`regra sem-id: ${regra.texto}`);
    continue;
  }
  regra.estado = 'testada';
  if (regra.teste !== null && regra.teste.toLowerCase() === 'nenhum') regra.estado = 'sem-teste';
  if (!regra.verificada || !regra.teste) regra.estado = 'sem-campos';
  console.log(`regra R${regra.n} ${regra.estado}`);
}
const contaEstado = (estado) => regras.filter((r) => r.estado === estado).length;
const sufixoRegras = regras.length
  ? ` · regras: ${contaEstado('testada')} testada, ${contaEstado('sem-teste')} sem-teste, ${contaEstado('sem-campos')} sem-campos, ${contaEstado('sem-id')} sem-id`
  : '';
console.log(`${contadas} âncoras: ${oks} ok, ${falhas} falhas${sufixoRegras}`);
process.exitCode = falhas > 0 || contaEstado('sem-campos') > 0 ? 1 : 0;
