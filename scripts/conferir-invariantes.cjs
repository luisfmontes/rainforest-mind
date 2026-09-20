#!/usr/bin/env node
// @categoria: sensor
/**
 * conferir-invariantes.cjs — valida que frases críticas não foram perdidas na extração.
 *
 * Procura todos os `skills/<nome>/invariantes.json` e valida frases de cada skill
 * contra seu correspondente `skills/<nome>/SKILL.md`.
 *
 * O arquivo tem de ser um array com PELO MENOS uma invariante. Array vazio,
 * ou qualquer coisa que não seja array, é erro de configuração e sai 1: um
 * `invariantes.json` que não declara invariante nenhuma faria o sensor imprimir
 * "ok: conferidas 0 invariantes" sem ter medido nada — defeito achado pela
 * revisão em 2026-09-20, que é exatamente o que este sensor existe para impedir.
 *
 * Formato de invariante:
 *   - `frase`: string não vazia a validar (obrigatório)
 *   - `tipo`: opcional. Ausente vale "deve"; presente só aceita "deve" ou
 *     "nao_deve", e qualquer outro valor sai 1
 *   - `onde`: opcional, array NÃO VAZIO em que CADA elemento é "skill",
 *     "referencia" ou "nucleo"
 *     - Ausente: testa presença da frase no corpo do SKILL.md
 *     - Presente: testa presença conforme configurado (skill, referencia, nucleo)
 *     - Presente sem nenhum degrau reconhecido (`[]`, `null`, `["outro"]`): sai 1.
 *       Antes de 2026-09-20 isso desligava a checagem em silêncio e saía 0
 *     - Presente com UM degrau estranho AO LADO de um válido
 *       (`["skill","nucelo"]`): sai 1. Até a quinta revisão, em 2026-09-20, a
 *       guarda era `onde.some(d => DEGRAUS.includes(d))` — exigia UM degrau
 *       reconhecido e ignorava todos os outros em silêncio. Medido com a
 *       mutação canônica do projeto dentro da caixa: `["skill","nucleo"]` saía
 *       2 e `["skill","nucelo"]` saía 0. A rodada 4 tinha fechado o nome da
 *       CHAVE e deixado aberto o nome do DEGRAU dentro dela — a mesma classe,
 *       um nível abaixo
 *   - `regra`, `descricao`: metadados
 *
 * Chave fora dessa lista é ERRO (exit 1), nunca campo ignorado. Até 2026-09-20 a
 * desestruturação descartava em silêncio toda chave não listada: grafar `onde`
 * como `ondes` nas cinco entradas da `rainforest-mind` derrubava a checagem para
 * presença-no-corpo, e a mutação canônica do projeto (mover `3.000+ tokens` para
 * depois de `<!-- detalhe -->`) passava com exit 0 — o defeito exato que este
 * sensor existe para pegar. `onde` em invariante `tipo: "nao_deve"` também é erro:
 * o `nao_deve` varre o corpo inteiro, e o campo era aceito e ignorado, dando
 * aparência de checagem por degrau que nunca existiu.
 *
 * VARREDURA DA CLASSE, 2026-09-20. Quatro revisões seguidas acharam, cada uma,
 * uma forma diferente do MESMO defeito — entrada malformada que o sensor aceita e
 * silenciosamente deixa de medir — e cada conserto fechou a forma medida deixando
 * a forma irmã aberta. Na quinta, em vez de consertar só a instância, os valores
 * de todos os campos foram varridos com uma frase que não existe em lugar nenhum,
 * procurando exit 0. O que a varredura estabeleceu:
 *
 *   - `tipo`: lista fechada por `!==`, então `"Deve"`, `" deve"` e `null` saem 1.
 *   - chave: lista fechada por `CHAVES_ACEITAS.includes`, então `"Onde"` sai 1.
 *   - `onde` como um todo: `[]`, `null`, `"skill"`, `["outro"]`, `[{}]` saem 1.
 *   - `onde` ELEMENTO a elemento: era o buraco, e é o que esta rodada fechou.
 *
 * DUAS FORMAS FICARAM, de propósito, e o motivo é o mesmo nas duas: elas FALHAM
 * FECHADO — o sensor não para de medir, ele mede e reprova, alto. Não são da
 * classe, e trancá-las custaria recusa nova sem defeito correspondente:
 *
 *   - `regra` ausente ou de tipo estranho com `onde: ["referencia"]`: o sensor
 *     procura `references/regra-undefined.md` ou `references/regra-abc.md`, não
 *     acha, e sai 2. A mensagem nomeia o arquivo que procurou, então o defeito
 *     é legível. Fica como ruído de mensagem, não como checagem desligada.
 *   - `descricao` de tipo estranho (`42`): só entra na mensagem de falha, nunca
 *     numa decisão. Não há o que deixar de medir.
 *
 * Regra do `tipo: "nao_deve"`:
 * - Frase proibida só vale se for vocabulário que o texto correto nunca usa
 * - Exemplo: `--confirmo` é proibido no `fechar` e obrigatório no `limpar`, então
 *   um `nao_deve: --confirmo` dispararia no texto certo — proibido
 * - `CONFIRMO fechar issue` é seguro: não existe em nenhuma skill correta
 * - A comparação do `nao_deve` é INSENSÍVEL A CAIXA, como o `/i` do
 *   `assert.doesNotMatch(skill, /secure encrypted provisioning/i)` que originou o
 *   enxerto (D5). O `deve` continua exato — lá a comparação é de presença de uma
 *   frase aprovada, e ignorar caixa mudaria o que a frase significa
 */

const fs = require('fs');
const path = require('path');

const SKILLS_DIR = path.join(__dirname, '../skills');
const DEGRAUS = ['skill', 'referencia', 'nucleo'];
const CHAVES_ACEITAS = ['regra', 'frase', 'onde', 'descricao', 'tipo'];

// Mostra o valor recebido na mensagem de recusa, com teto, para a recusa dizer
// QUAL valor chegou sem despejar um arquivo inteiro no stderr.
function resumir(valor) {
  const texto = JSON.stringify(valor);
  if (texto === undefined) return String(valor);
  return texto.length > 120 ? `${texto.slice(0, 120)}…` : texto;
}
const CONTEXTO_LIB = path.join(__dirname, '../hooks/lib/contexto-sessao.cjs');

// Importar as funções do motor real
let filtrarRegras, extrairNucleo;
try {
  const lib = require(CONTEXTO_LIB);
  filtrarRegras = lib.filtrarRegras;
  extrairNucleo = lib.extrairNucleo;
} catch (e) {
  console.error(`Erro ao carregar contexto-sessao.cjs: ${e.message}`);
  process.exit(1);
}

// Descobrir todas as skills com invariantes.json
let skillsComInvariantes = [];
try {
  const entries = fs.readdirSync(SKILLS_DIR);
  for (const entry of entries) {
    const skillDir = path.join(SKILLS_DIR, entry);
    const stats = fs.statSync(skillDir);
    if (stats.isDirectory()) {
      const invariantesPath = path.join(skillDir, 'invariantes.json');
      if (fs.existsSync(invariantesPath)) {
        skillsComInvariantes.push(entry);
      }
    }
  }
  skillsComInvariantes.sort();
} catch (e) {
  console.error(`Erro ao descobrir skills: ${e.message}`);
  process.exit(1);
}

// Zero arquivos encontrados é erro
if (skillsComInvariantes.length === 0) {
  console.error('Erro: nenhum arquivo skills/*/invariantes.json encontrado');
  process.exit(1);
}

let totalInvariantes = 0;
let falhas = 0;

// Processar cada skill com invariantes
for (const nomeSkill of skillsComInvariantes) {
  const skillDir = path.join(SKILLS_DIR, nomeSkill);
  const invariantesPath = path.join(skillDir, 'invariantes.json');
  const skillMdPath = path.join(skillDir, 'SKILL.md');
  const referencesDir = path.join(skillDir, 'references');

  // Carregar invariantes
  let invariantes;
  try {
    const content = fs.readFileSync(invariantesPath, 'utf-8');
    invariantes = JSON.parse(content);
  } catch (e) {
    console.error(`Erro ao carregar [${nomeSkill}] invariantes.json: ${e.message}`);
    process.exit(1);
  }

  // Array vazio, ou o que não é array, é erro de configuração — nunca sucesso.
  // Sem esta guarda o sensor imprimia "ok: conferidas 0 invariantes" e saía 0.
  if (!Array.isArray(invariantes) || invariantes.length === 0) {
    const motivo = Array.isArray(invariantes)
      ? 'array vazio — um invariantes.json que não declara nenhuma invariante não confere nada'
      : `esperava um array de invariantes, veio ${resumir(invariantes)}`;
    console.error(`Erro: [${nomeSkill}] invariantes.json inválido: ${motivo}`);
    process.exit(1);
  }

  // Validação de FORMA de TODA entrada, antes de qualquer leitura de campo e de
  // qualquer medição. É aqui, num passe só, que o valor de cada campo é decidido
  // contra a sua lista fechada — foi a forma de validação partida em dois laços
  // que deixou o elemento de `onde` sem checagem por quatro rodadas.
  //
  // Tem de vir antes do laço de checagem porque o `invariantes.some(inv =>
  // inv.onde !== undefined)` mais abaixo estoura `TypeError` num elemento `null`
  // — stack cru do Node no lugar de recusa legível (achado da revisão,
  // 2026-09-20). Só o `null` estoura: desestruturar `"x"` ou `42` é legal em
  // JavaScript, e sem esta guarda as duas formas cairiam em "campo frase ausente
  // ou vazio", exit 1 com mensagem que mente sobre o defeito. Das três formas de
  // elemento na bateria, portanto, só `[null]` distingue esta guarda presente de
  // ausente; `["x"]` e `[42]` saem 1 nos dois mundos (medido em 2026-09-20 com a
  // guarda neutralizada).
  for (let i = 0; i < invariantes.length; i++) {
    const inv = invariantes[i];
    const rotulo = `[${nomeSkill}] invariante #${i + 1}`;

    if (inv === null || typeof inv !== 'object' || Array.isArray(inv)) {
      console.error(`Erro: ${rotulo}: esperava um objeto, veio ${resumir(inv)}`);
      process.exit(1);
    }

    const sufixoRegra = inv.regra !== undefined ? ` regra-${inv.regra}` : '';

    // Chave desconhecida é recusa, não campo ignorado: `ondes` no lugar de `onde`
    // desligava a checagem de núcleo em silêncio e o sensor saía 0.
    const desconhecidas = Object.keys(inv).filter(chave => !CHAVES_ACEITAS.includes(chave));
    if (desconhecidas.length > 0) {
      const lista = desconhecidas.map(chave => `"${chave}"`).join(', ');
      console.error(`Erro: chave desconhecida ${lista} em ${rotulo}${sufixoRegra}`);
      console.error(`  chaves aceitas: ${CHAVES_ACEITAS.join(', ')}`);
      console.error('  chave fora da lista era descartada em silêncio até 2026-09-20 — `ondes` por `onde` desligava a checagem de núcleo e o sensor saía 0');
      process.exit(1);
    }

    // `onde` em `nao_deve` também é recusa. Ele era ACEITO E IGNORADO: o
    // `nao_deve` procura a frase no corpo inteiro do SKILL.md, então o campo
    // dava aparência de checagem por degrau que nunca existiu.
    if (inv.tipo === 'nao_deve' && inv.onde !== undefined) {
      console.error(`Erro: campo "onde" não se aplica a tipo "nao_deve" em ${rotulo}${sufixoRegra}`);
      console.error('  o `nao_deve` procura a frase no corpo inteiro do SKILL.md; até 2026-09-20 o campo era aceito e ignorado');
      console.error('  remova o campo "onde" desta invariante');
      process.exit(1);
    }

    // FORMA do `onde`: array não vazio, e CADA elemento um degrau conhecido.
    if (inv.onde !== undefined) {
      if (!Array.isArray(inv.onde) || inv.onde.length === 0) {
        console.error(`Erro: campo "onde" sem degrau reconhecido na invariante ${rotulo}${sufixoRegra}`);
        console.error(`  onde recebido: ${resumir(inv.onde)}`);
        console.error(`  degraus aceitos: ${DEGRAUS.join(', ')} (ou omita o campo para testar presença no corpo)`);
        process.exit(1);
      }

      // Recusa ELEMENTO a elemento. A guarda anterior era
      // `onde.some(d => DEGRAUS.includes(d))`: exigia UM degrau reconhecido e
      // ignorava todos os outros em silêncio, então `["skill","nucelo"]` media
      // só o degrau `skill` e o degrau de núcleo sumia sem uma linha de aviso.
      const degrausEstranhos = inv.onde.filter(degrau => !DEGRAUS.includes(degrau));
      if (degrausEstranhos.length > 0) {
        const lista = degrausEstranhos.map(degrau => resumir(degrau)).join(', ');
        console.error(`Erro: degrau desconhecido ${lista} no campo "onde" em ${rotulo}${sufixoRegra}`);
        console.error(`  onde recebido: ${resumir(inv.onde)}`);
        console.error(`  degraus aceitos: ${DEGRAUS.join(', ')} (ou omita o campo para testar presença no corpo)`);
        console.error('  degrau fora da lista era ignorado em silêncio até 2026-09-20 — `nucelo` por `nucleo` desligava a checagem de núcleo e o sensor saía 0 com a mutação canônica dentro');
        process.exit(1);
      }
    }
  }

  // Ler o SKILL.md
  let skillContent;
  try {
    skillContent = fs.readFileSync(skillMdPath, 'utf-8');
  } catch (e) {
    console.error(`Erro ao ler [${nomeSkill}] SKILL.md: ${e.message}`);
    process.exit(1);
  }

  // Cache de referencias lidas para esta skill
  const referenciaCache = {};

  function lerReferencia(regra) {
    if (referenciaCache[regra] !== undefined) {
      return referenciaCache[regra];
    }

    const caminhoReferencia = path.join(referencesDir, `regra-${regra}.md`);
    try {
      if (fs.existsSync(caminhoReferencia)) {
        referenciaCache[regra] = fs.readFileSync(caminhoReferencia, 'utf-8');
        return referenciaCache[regra];
      }
    } catch (e) {
      // arquivo não existe ou não conseguiu ler
    }
    referenciaCache[regra] = null;
    return null;
  }

  // Aplicar o parser real para extrair o núcleo injetado apenas se necessário
  let regrasTexto, nucleoContent;
  const temOnde = invariantes.some(inv => inv.onde !== undefined);
  if (temOnde) {
    regrasTexto = filtrarRegras(skillContent);
    nucleoContent = extrairNucleo(regrasTexto);
  }

  // Checar cada invariante
  for (const inv of invariantes) {
    const { regra, frase, onde = undefined, descricao, tipo = 'deve' } = inv;
    totalInvariantes++;

    // Validar tipo conhecido
    if (tipo !== 'deve' && tipo !== 'nao_deve') {
      console.error(`Erro: tipo desconhecido "${tipo}" na invariante [${nomeSkill}]${regra !== undefined ? ' regra-'+regra : ''}`);
      process.exit(1);
    }

    if (typeof frase !== 'string' || frase.length === 0) {
      console.error(`Erro: campo "frase" ausente ou vazio na invariante [${nomeSkill}]${regra !== undefined ? ' regra-'+regra : ''}`);
      process.exit(1);
    }

    // A FORMA do `onde` — array não vazio, cada elemento um degrau conhecido —
    // já foi decidida no passe de validação acima, antes de qualquer medição.
    // `onde` AUSENTE continua válido e significa presença no corpo (D4).

    // Determinação do "corpo" a testar conforme o tipo e onde
    const corpo = skillContent;

    // Checagem de tipo nao_deve — insensível a caixa, como o `/i` do enxerto (D5)
    const proibidaPresente = tipo === 'nao_deve' && corpo.toLowerCase().includes(frase.toLowerCase());
    if (proibidaPresente) {
      console.error(`FALHA invariante [${nomeSkill}]${regra !== undefined ? ' regra-'+regra : ''}: frase proibida encontrada no corpo`);
      console.error(`  frase: "${frase}"`);
      console.error(`  descricao: ${descricao}`);
      falhas++;
      continue;
    }

    // Se for deve, executar checagens normais
    if (tipo === 'deve') {
      // Se onde não foi especificado, apenas testa presença no corpo
      if (onde === undefined) {
        if (!corpo.includes(frase)) {
          console.error(`FALHA invariante [${nomeSkill}]${regra !== undefined ? ' regra-'+regra : ''}: frase não encontrada no SKILL.md`);
          console.error(`  frase: "${frase}"`);
          console.error(`  descricao: ${descricao}`);
          falhas++;
        } else {
          // Checar ocorrência única
          const n = corpo.split(frase).length - 1;
          if (n >= 2) {
            console.error(`FALHA invariante [${nomeSkill}]${regra !== undefined ? ' regra-'+regra : ''}: frase aparece ${n} vezes (deve aparecer exatamente 1)`);
            console.error(`  frase: "${frase}"`);
            falhas++;
          }
        }
      } else {
        // onde foi especificado — executar checagens conforme a semântica original

        // Checagem 1: a frase está nas REGRAS FILTRADAS do SKILL.md?
        // O que se mede aqui é `filtrarRegras(skillContent)`, não o arquivo: o
        // filtro descarta o que está fora do bloco de regras, então frase que
        // ESTÁ no SKILL.md e mora fora desse bloco dá `emSkill` falso. Medido em
        // 2026-09-20: `onde: ["skill"]` com `O destino da branch é sempre PR`,
        // que está em `skills/fechar/SKILL.md`, sai 2. As mensagens abaixo dizem
        // "regras filtradas do SKILL.md" por isso — até esta data diziam
        // "SKILL.md" e mentiam sobre o que tinha sido medido.
        const emSkill = regrasTexto.includes(frase);

        // Checagem 2: a frase está na referência (references/regra-<n>.md)?
        let emReferencia = false;
        if (onde.includes('referencia')) {
          const conteudoReferencia = lerReferencia(regra);
          emReferencia = conteudoReferencia !== null && conteudoReferencia.includes(frase);
        }

        // Checagem 3: a frase está no núcleo extraído (o que será injetado)?
        const emNucleo = nucleoContent.includes(frase);

        // Validar congruência baseada em 'onde'

        // Se deve estar em skill, checar se está
        if (onde.includes('skill') && !emSkill) {
          console.error(`FALHA invariante [${nomeSkill}]${regra !== undefined ? ' regra-'+regra : ''}: frase não encontrada nas regras filtradas do SKILL.md`);
          console.error(`  frase: "${frase}"`);
          console.error(`  descricao: ${descricao}`);
          falhas++;
        }

        // Se deve estar em referencia, checar se está
        if (onde.includes('referencia') && !emReferencia) {
          console.error(`FALHA invariante [${nomeSkill}]${regra !== undefined ? ' regra-'+regra : ''}: frase não encontrada na references/regra-${regra}.md`);
          console.error(`  frase: "${frase}"`);
          console.error(`  descricao: ${descricao}`);
          falhas++;
        }

        // Se deve estar no núcleo injetado, checar se está
        // Se estiver em SKILL mas não em NUCLEO, foi perdida na extração
        if (onde.includes('nucleo')) {
          if (emSkill && !emNucleo) {
            // Frase está no arquivo original mas não no núcleo extraído
            // Significa que foi movida para depois da marca <!-- detalhe -->
            console.error(`FALHA invariante [${nomeSkill}]${regra !== undefined ? ' regra-'+regra : ''}: frase existe nas regras filtradas do SKILL.md mas não chega ao núcleo extraído`);
            console.error(`  frase: "${frase}"`);
            console.error(`  descricao: ${descricao}`);
            falhas++;
          } else if (!emSkill && !emNucleo) {
            // Frase não está em nenhum lugar — erro de configuração
            console.error(`FALHA invariante [${nomeSkill}]${regra !== undefined ? ' regra-'+regra : ''}: frase não encontrada nem nas regras filtradas do SKILL.md nem no núcleo extraído`);
            console.error(`  frase: "${frase}"`);
            falhas++;
          }
        }

        // Checar ocorrência única
        const n = corpo.split(frase).length - 1;
        if (n >= 2) {
          console.error(`FALHA invariante [${nomeSkill}]${regra !== undefined ? ' regra-'+regra : ''}: frase aparece ${n} vezes (deve aparecer exatamente 1)`);
          console.error(`  frase: "${frase}"`);
          falhas++;
        }
      }
    }
  }
}

if (falhas === 0) {
  console.log(`ok: conferidas ${totalInvariantes} invariantes`);
  process.exit(0);
} else {
  console.error(`FALHA: ${falhas} invariante(s) falharam`);
  process.exit(2);
}
