// Logica pura do "deixado para depois" do mod: frases de adiamento em portugues e
// ingles, marcadores em arquivo escrito e o prompt do checker. ES module sem Node e sem
// o objeto do engine: tudo entra por argumento.
// Contrato: docs/rainforest/planos/2026-10-07-desk-no-mod.md, tarefa 2.
// Frases e marcadores partem das regex do terminal-desk 0.2.1 (licenca MIT, titular
// ClariSortAi); texto da licenca e origem em NOTICE, na raiz do plugin.

// Um turno com menos ferramentas que isso trabalhou pouco para valer um checker.
export const CHECAR_MIN_FERRAMENTAS = 5;

// Como uma resposta diz que adiou trabalho. Roda sobre texto normalizado por
// `semCitacao` (sem acento, minusculo, sem o que esta entre aspas ou crases).
const DITO = /\b(?:por enquanto|fica(?:m|ra|ram)? para depois|deixei para depois|proxima (?:fase|etapa|rodada|passada)|nao (?:rodei|testei|verifiquei|implementei|executei|conferi|consegui)|sem (?:rodar|testar|verificar)|fora do escopo|em outra (?:rodada|passada|etapa)|placeholder|for now|follow[- ]up|out of scope|not yet|i (?:didn't|did not|haven't|have not|skipped|left)\b|(?:do|handle|add|fix|revisit|address|tackle) (?:that|this|it|them|those) later|in a later (?:pass|step|turn|change|pr)|still needs?|remains? to be|stubbed|untested|not (?:verified|tested|implemented|wired up))/i;

// Como trabalho adiado aparece quando ja foi escrito num arquivo. `TODO` em maiusculas
// e palavra portuguesa neste repo ("corpo de TODO heredoc"), por isso o marcador so conta
// seguido de `:` ou `(`.
const MARCA = /\b(?:TODO|FIXME|XXX)\s*[:(]|not implemented|NotImplemented|\.skip\(|\bx(?:it|describe)\(|@pytest\.mark\.skip/;

// O que Claude cita entre aspas ou mostra como codigo nao e Claude adiando trabalho.
const semCitacao = (parte) =>
  parte
    .replace(/"[^"]*"|“[^”]*”|`[^`]*`/g, ' ')
    .replace(/’/g, "'")
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase();

// As frases de uma resposta que adiam trabalho, blocos de codigo fora; ate 3, 200 cars.
export const deferimentos = (resposta) =>
  String(resposta ?? '')
    .replace(/```[\s\S]*?```/g, ' ')
    .split(/(?<=[.!?])\s+|\n+/)
    .map(parte => parte.replace(/^[\s>*#-]+/, '').replace(/\*\*/g, '').trim())
    .filter(parte => parte.length > 12 && DITO.test(semCitacao(parte)))
    .map(parte => parte.slice(0, 200))
    .slice(0, 3);

// As linhas de um arquivo escrito que carregam marcador de trabalho adiado.
export const marcadoresEmArquivo = (conteudo) =>
  String(conteudo ?? '')
    .split(/\r?\n/)
    .filter(linha => MARCA.test(linha))
    .map(linha => linha.trim().slice(0, 200))
    .slice(0, 3);

const plural = (n, um, varios) => n + ' ' + (n === 1 ? um : varios);

// `Bash x12 (2 erros), Edit x3, Write x1 (1 negada)`: cada ferramenta do turno, na ordem
// em que apareceu, com as falhas. Entrada: [{ tool, deny, isError }].
export const resumirFerramentas = (ferramentas) => {
  const porNome = new Map();
  for (const f of ferramentas ?? []) {
    const nome = String((f && f.tool) || '?');
    const c = porNome.get(nome) ?? { n: 0, erros: 0, negadas: 0 };
    c.n += 1;
    if (f && f.deny) c.negadas += 1;
    else if (f && f.isError) c.erros += 1;
    porNome.set(nome, c);
  }
  return [...porNome]
    .map(([nome, c]) => {
      const falhas = [];
      if (c.erros > 0) falhas.push(plural(c.erros, 'erro', 'erros'));
      if (c.negadas > 0) falhas.push(plural(c.negadas, 'negada', 'negadas'));
      return nome + ' x' + c.n + (falhas.length > 0 ? ' (' + falhas.join(', ') + ')' : '');
    })
    .join(', ');
};

// O que o segundo modelo (checker) le: o pedido, as ferramentas do turno com as falhas e
// o fim do relato. Em portugues; resposta de ate 3 linhas, ou a palavra NENHUM.
export const montarPromptChecker = ({ pedido, relato, ferramentas }) =>
  [
    'Voce compara o que a pessoa pediu a um assistente de codigo com o relato final dele e com as ferramentas que ele usou.',
    'Liste cada coisa que o pedido claramente exigia e que o relato mostra que nao foi feita, foi adiada ou foi feita so em parte.',
    'No maximo 3 linhas, cada uma com menos de 20 palavras e comecando por um verbo. Sem numeracao e sem comentario.',
    'Se nada ficou por fazer, responda apenas com a palavra NENHUM.',
    '',
    'PEDIDO:',
    String(pedido ?? '').slice(0, 4000),
    '',
    'FERRAMENTAS DO TURNO:',
    resumirFerramentas(ferramentas) || '(nenhuma)',
    '',
    'RELATO FINAL:',
    String(relato ?? '').slice(-6000),
  ].join('\n');

// A resposta do checker em itens: ate 3, sem numeracao, sem a palavra NENHUM.
export const lerRespostaChecker = (texto) =>
  String(texto ?? '')
    .split('\n')
    .map(linha => linha.replace(/^[\s\d.)*-]+/, '').trim().slice(0, 200))
    .filter(linha => linha !== '' && !['nenhum', 'none'].includes(linha.replace(/[.\s]+/g, '').toLowerCase()))
    .slice(0, 3);

// Rascunho do prompt do botao "Faz agora". Nunca e enviado sozinho: so preenche.
export const rascunhoFazAgora = (frase) =>
  'Voce deixou isto para depois: "' + String(frase ?? '').slice(0, 200) + '". Faca agora e me diga o que rodou para provar.';
