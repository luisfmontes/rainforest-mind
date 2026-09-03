#!/usr/bin/env node
/**
 * Confere um relatório ANTES de ele sair da máquina — e RECUSA, em vez de avisar.
 *
 * POR QUE EXISTE, com data. O `commands/feedback.md` mandava, desde sempre:
 * "se o achado citar credencial, dado de cliente ou fonte de cliente, anonimize
 * antes de gravar". A regra estava escrita, era clara, e mesmo assim, em
 * 2026-08-10, um relatório foi gravado e commitado contendo:
 *
 *   - o telefone de um terceiro, em JID de WhatsApp (`5547...@s.whatsapp.net`);
 *   - o nome completo dessa pessoa;
 *   - o caminho do repositório do cliente, o parâmetro e a tela do sistema.
 *
 * Ficou no repositório por um dia, e só saiu porque o repo ia ser publicado e
 * alguém foi procurar. É a lição mais repetida deste acervo, aplicada a ele
 * mesmo: **regra escrita não alcança o modo de falha em que quem a leu erra
 * mesmo assim.** O que alcança é código com exit code.
 *
 * E o custo do vazamento MUDOU: enquanto o relatório era markdown num repo
 * privado, um deslize dava para corrigir antes de alguém ver. Agora o
 * `/feedback` abre Issue — que é público no instante em que é criado, e que
 * fica no índice de busca mesmo depois de editado. Não há "corrigir antes".
 *
 * O QUE ELE NÃO FAZ, e é importante dizer: ele não detecta NOME DE PESSOA. Não
 * há padrão para isso. Ele detecta o que tem forma — telefone, e-mail, JID,
 * caminho de home, credencial. O nome do Emerson naquele relatório teria
 * passado por aqui; o telefone dele, não. Por isso a saída limpa não diz "está
 * seguro", diz "não achei o que sei procurar", e lembra do resto.
 *
 * Uso:
 *   node scripts/conferir-publicacao.cjs <arquivo>     # exit 2 se achar algo
 *   cat rascunho.md | node scripts/conferir-publicacao.cjs -
 *   node scripts/conferir-publicacao.cjs <arquivo> --json
 */

const fs = require('fs');

/**
 * Cada padrão diz o que é e por que dói — mensagem de trava que só nomeia o
 * regex manda quem foi barrado adivinhar o conserto.
 *
 * `exemplo` é o que aparece na saída no lugar do trecho real: mostrar o dado
 * vazado na tela de quem está tentando não vazá-lo seria irônico e inútil.
 */
const PADROES = [
  {
    id: 'jid-whatsapp',
    // A faixa foi `\d{10,15}` até 2026-09-02, e parava CURTA: cobria JID de
    // conversa direta (o telefone, 12–13 dígitos) e deixava passar JID de
    // GRUPO, que tem 18. Issue #149, e o custo foi medido — o `vigias/ERROS.md`
    // da `main` carregou o JID real do grupo das rondas por dias.
    //
    // O modo de falha é o da regra 12, e é o pior tipo: o instrumento
    // RESPONDEU. O JID de grupo acendia o padrão genérico `telefone`, marcado
    // `(pode ser falso positivo)` — que é justamente a categoria que se aprende
    // a ignorar —, em vez desta regra, que é a que traz a instrução certa. Saída
    // plausível, medindo outra coisa.
    re: /\b(\d{10,20})@(s\.whatsapp\.net|g\.us)\b/g,
    o_que: 'JID de WhatsApp — contém o telefone completo, com DDI e DDD',
    faca: 'troque por um marcador (`<jid-do-contato>`); o ID da mensagem sozinho já basta para investigar',
    // Dígito repetido não é dado de ninguém: `000000000000000000@g.us` é o
    // placeholder de `vigias/vigia.config.exemplo.json`, arquivo versionado que
    // documenta o FORMATO. Sem esta isenção, alargar a faixa faria o gate
    // recusar a própria documentação — certo na forma, errado no mérito, que é
    // como uma trava vira `--forcar` no dedo de quem usa.
    //
    // A isenção é por dígito repetido, não por lista de placeholders conhecidos:
    // um JID em que todos os dígitos são iguais não carrega telefone nenhum, e
    // isso vale para o placeholder que ainda não foi escrito.
    so_se: (m) => !/^(\d)\1*$/.test(m[1]),
  },
  {
    id: 'telefone',
    re: /(?:\+\d{1,3}[\s-]?)?\(?\d{2}\)?[\s-]?9?\d{4}[\s-]?\d{4}\b/g,
    o_que: 'sequência com forma de telefone',
    faca: 'remova, ou confirme que é ID/timestamp e não telefone',
    // Timestamp de 13 dígitos e hash numérico batem aqui. Falso positivo custa
    // uma olhada; falso negativo custa o telefone de alguém num Issue público.
    pode_ser_falso: true,
    // Mesma isenção da regra de JID, e pelo mesmo motivo: sequência de dígito
    // repetido não é telefone de ninguém. Sem ela, o placeholder de
    // `vigias/vigia.config.exemplo.json` fazia o gate recusar um arquivo
    // versionado do próprio repositório — em toda rodada, desde sempre. Falso
    // positivo permanente em arquivo que nunca vai mudar é como se aprende a
    // ignorar a saída inteira.
    so_se: (m, linha) => {
      // Issue #144: saída de xxd / hexdump -C / od -tx1 tem forma mecânica, e o
      // gate lia bytes como telefone — barrando a única evidência que prova um
      // defeito de encoding. A isenção vale só para match DENTRO dos grupos hex;
      // a coluna ASCII do dump, se mostrar um telefone legível, continua recusada.
      if (dentroDeDumpHex(m, linha)) return false;
      const digitos = m[0].replace(/\D/g, '');
      return !/^(\d)\1*$/.test(digitos);
    },
  },
  {
    id: 'email',
    re: /\b[\w.+-]+@(?!s\.whatsapp\.net|g\.us)[\w-]+\.[\w.]{2,}\b/g,
    o_que: 'endereço de e-mail',
    faca: 'troque por `<email>` — endereço de terceiro em Issue público vira alvo de spam',
  },
  {
    id: 'caminho-de-home',
    // O segmento do usuário sai em grupo de captura para o `so_se` poder olhá-lo.
    re: /[A-Za-z]:\\Users\\([^\\\s"'`]+)|\/(?:home|Users)\/([^/\s"'`]+)/g,
    o_que: 'caminho de pasta pessoal — carrega o nome de usuário da máquina',
    faca: 'use `<home>` ou um caminho relativo; o caminho absoluto raramente é o que prova o defeito',
    // PLACEHOLDER NÃO É NOME DE NINGUÉM — a terceira regra desta lista a ganhar
    // esta isenção, e pelo mesmo motivo das duas primeiras (Issue #149): a regra
    // recusava a própria documentação do formato que ela ensina. O `faca` acima
    // manda "use `<home>`", e o texto que obedecia era recusado igual.
    //
    // Medido em 2026-09-02: a varredura da árvore antes de tornar o repositório
    // público devolveu 32 arquivos recusados, e `caminho-de-home` respondia por
    // 17 deles — a maioria placeholder ou código que MANIPULA caminho de home.
    // Gate que grita em 17 arquivos que nunca vão mudar ensina a ignorar a saída
    // inteira, e é assim que ele deixa de pegar o 18º, que é real.
    //
    // A isenção é por FORMA, não por lista: `<qualquer coisa>`, `%VAR%` e
    // `$VAR` nunca são nome de usuário em disco. Nome novo de placeholder que
    // alguém invente amanhã já entra isento.
    so_se: (m) => {
      const nome = m[1] || m[2] || '';
      const ehPlaceholder = /^<.*>$/.test(nome)
        || /^%.*%$/.test(nome)
        || nome.startsWith('$');
      return !ehPlaceholder;
    },
  },
  {
    id: 'credencial',
    re: /\b(senha|password|api[_-]?key|apikey|secret|token|authorization)\s*[:=]\s*["']?(\S+)/gi,
    o_que: 'credencial atribuída a uma chave',
    faca: 'nunca cole credencial em relatório, nem revogada — troque por `<redigido>`',
    // O `i` vale para a CHAVE, e não é negociável: `API_KEY` e `SENHA` seguidas de dois-pontos são as
    // formas mais comuns em log e config, e padrão case-sensitive fica cego para
    // as duas. Quem separa prosa de segredo é o `so_se`, em código — a distinção
    // não cabe na mesma regex que ignora caixa.
    //
    // 2026-08-17: a palavra `token` seguida de dois-pontos e prosa comum ("Regua
    // de orcamento de token: medir a abertura antes de comprimir...") recusou um
    // relatório legítimo e obrigou a truncar a evidência que ele existia para
    // mostrar. A liberação é estreita de propósito: valor de palavra curta, toda
    // minúscula, E a linha seguindo com mais palavras. Dúvida captura — valor
    // sozinho na linha continua recusado, mesmo minúsculo.
    so_se: (m, linha) => {
      const valor = m[2].replace(/^["']+/, '');
      const prosaCurta = /^[a-zà-ú]{1,12}$/.test(valor);
      const depois = linha.slice(m.index + m[0].length).trim().split(/\s+/).filter(Boolean);
      return !(prosaCurta && depois.length >= 2);
    },
  },
  {
    id: 'chave-conhecida',
    re: /\b(gh[pousr]_[A-Za-z0-9]{16,}|sk-[A-Za-z0-9]{16,}|xox[baprs]-[A-Za-z0-9-]{10,})\b/g,
    o_que: 'chave com prefixo conhecido (GitHub, OpenAI, Slack)',
    faca: 'REVOGUE a chave antes de qualquer outra coisa, e só depois edite o texto',
  },
];

/** O que o script sabe que NÃO sabe. Sai junto com o verde, de propósito. */
const CEGO = [
  'nome de pessoa — não há padrão para isso, e foi exatamente o que passou em 2026-08-10',
  'nome de cliente, de sistema ou de projeto interno',
  'print, log ou stack trace colado com conteúdo de terceiro dentro',
];

// Trecho hex de um dump: offset opcional (7–8 hex, dois-pontos opcional) seguido
// de pelo menos quatro grupos de 2 ou 4 hex separados por espaço. É a forma de
// `xxd`, `hexdump -C` e `od -An -tx1`; prosa com números não a produz.
const RE_TRECHO_HEX = /^\s*(?:[0-9a-f]{7,8}:?\s+)?(?:[0-9a-f]{2}(?:[0-9a-f]{2})?\s+){3,}[0-9a-f]{2}(?:[0-9a-f]{2})?/i;
function dentroDeDumpHex(m, linha) {
  const t = RE_TRECHO_HEX.exec(linha);
  return !!t && m.index + m[0].length <= t[0].length;
}

function conferir(texto) {
  const achados = [];
  for (const p of PADROES) {
    const linhas = texto.split('\n');
    linhas.forEach((linha, i) => {
      p.re.lastIndex = 0;
      let bateu;
      if (p.so_se) {
        // Padrão com `so_se` decide olhando o match inteiro e a linha, então aqui
        // é `exec` e não `test`: um único match liberado não pode liberar a linha,
        // e um único match capturado já a recusa.
        bateu = false;
        let m;
        while ((m = p.re.exec(linha)) !== null) {
          if (p.so_se(m, linha)) { bateu = true; break; }
          if (m.index === p.re.lastIndex) p.re.lastIndex += 1;
        }
      } else {
        bateu = p.re.test(linha);
      }
      if (bateu) {
        achados.push({ id: p.id, linha: i + 1, o_que: p.o_que, faca: p.faca, pode_ser_falso: !!p.pode_ser_falso });
      }
    });
  }
  return achados;
}

function main() {
  const args = process.argv.slice(2);
  const json = args.includes('--json');
  const alvo = args.find((a) => !a.startsWith('--'));
  if (!alvo) {
    console.error('uso: node scripts/conferir-publicacao.cjs <arquivo>|- [--json]');
    process.exit(1);
  }

  let texto;
  try {
    texto = alvo === '-' ? fs.readFileSync(0, 'utf8') : fs.readFileSync(alvo, 'utf8');
  } catch (e) {
    console.error(`erro: nao consegui ler ${alvo}`);
    process.exit(1);
  }

  const achados = conferir(texto);

  if (json) {
    console.log(JSON.stringify({ arquivo: alvo, achados, cego: CEGO }, null, 2));
    process.exit(achados.length ? 2 : 0);
  }

  if (!achados.length) {
    console.log('CONFERIDO — nao achei nada com forma de dado sensivel.');
    console.log('');
    console.log('Isto NAO quer dizer "esta seguro". Quer dizer "nao achei o que sei');
    console.log('procurar". Continua com voce:');
    for (const c of CEGO) console.log(`  - ${c}`);
    process.exit(0);
  }

  console.log(`RECUSADO — ${achados.length} trecho(s) com forma de dado sensivel.\n`);
  for (const a of achados) {
    console.log(`  linha ${a.linha}  [${a.id}]${a.pode_ser_falso ? '  (pode ser falso positivo)' : ''}`);
    console.log(`    ${a.o_que}`);
    console.log(`    -> ${a.faca}`);
  }
  console.log('');
  console.log('Corrija e rode de novo. E lembre do que este script NAO ve:');
  for (const c of CEGO) console.log(`  - ${c}`);
  process.exit(2);
}

if (require.main === module) main();
module.exports = { conferir, PADROES, CEGO };
