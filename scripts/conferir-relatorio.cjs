#!/usr/bin/env node
/**
 * Confere um relatório ANTES de ele sair da máquina — e RECUSA, em vez de avisar.
 *
 * POR QUE EXISTE, com data. O `commands/relatorio.md` mandava, desde sempre:
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
 * `/relatorio` abre Issue — que é público no instante em que é criado, e que
 * fica no índice de busca mesmo depois de editado. Não há "corrigir antes".
 *
 * O QUE ELE NÃO FAZ, e é importante dizer: ele não detecta NOME DE PESSOA. Não
 * há padrão para isso. Ele detecta o que tem forma — telefone, e-mail, JID,
 * caminho de home, credencial. O nome do Emerson naquele relatório teria
 * passado por aqui; o telefone dele, não. Por isso a saída limpa não diz "está
 * seguro", diz "não achei o que sei procurar", e lembra do resto.
 *
 * Uso:
 *   node scripts/conferir-relatorio.cjs <arquivo>     # exit 2 se achar algo
 *   cat rascunho.md | node scripts/conferir-relatorio.cjs -
 *   node scripts/conferir-relatorio.cjs <arquivo> --json
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
    re: /\b\d{10,15}@(s\.whatsapp\.net|g\.us)\b/g,
    o_que: 'JID de WhatsApp — contém o telefone completo, com DDI e DDD',
    faca: 'troque por um marcador (`<jid-do-contato>`); o ID da mensagem sozinho já basta para investigar',
  },
  {
    id: 'telefone',
    re: /(?:\+\d{1,3}[\s-]?)?\(?\d{2}\)?[\s-]?9?\d{4}[\s-]?\d{4}\b/g,
    o_que: 'sequência com forma de telefone',
    faca: 'remova, ou confirme que é ID/timestamp e não telefone',
    // Timestamp de 13 dígitos e hash numérico batem aqui. Falso positivo custa
    // uma olhada; falso negativo custa o telefone de alguém num Issue público.
    pode_ser_falso: true,
  },
  {
    id: 'email',
    re: /\b[\w.+-]+@(?!s\.whatsapp\.net|g\.us)[\w-]+\.[\w.]{2,}\b/g,
    o_que: 'endereço de e-mail',
    faca: 'troque por `<email>` — endereço de terceiro em Issue público vira alvo de spam',
  },
  {
    id: 'caminho-de-home',
    re: /[A-Za-z]:\\Users\\[^\\\s"'`]+|\/(?:home|Users)\/[^/\s"'`]+/g,
    o_que: 'caminho de pasta pessoal — carrega o nome de usuário da máquina',
    faca: 'use `<home>` ou um caminho relativo; o caminho absoluto raramente é o que prova o defeito',
  },
  {
    id: 'credencial',
    re: /\b(senha|password|api[_-]?key|apikey|secret|token|authorization)\s*[:=]\s*["']?[^\s"']{4,}/gi,
    o_que: 'credencial atribuída a uma chave',
    faca: 'nunca cole credencial em relatório, nem revogada — troque por `<redigido>`',
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

function conferir(texto) {
  const achados = [];
  for (const p of PADROES) {
    const linhas = texto.split('\n');
    linhas.forEach((linha, i) => {
      p.re.lastIndex = 0;
      if (p.re.test(linha)) {
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
    console.error('uso: node scripts/conferir-relatorio.cjs <arquivo>|- [--json]');
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
