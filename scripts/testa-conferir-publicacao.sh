#!/bin/bash
# rainforest-gate: dados-de-exemplo
# Bateria do scripts/conferir-publicacao.cjs — a trava que confere o relatorio antes
# de ele sair da maquina.
#
# Ela existe porque a versao ESCRITA da mesma regra falhou. O `commands/feedback.md`
# mandava anonimizar dado de cliente desde sempre, e em 2026-08-10 um relatorio foi
# gravado e commitado com telefone e nome completo de terceiro. A bateria tem que
# provar que a versao em codigo pega o que a versao em texto deixou passar.
#
# O que precisa provar:
#   1. RECUSA com exit 2 — nao "avisa". Trava que sai 0 nao trava nada, e este e o
#      mesmo defeito que os gates deste repo ja documentaram;
#   2. pega as cinco formas: JID de WhatsApp, telefone, e-mail, caminho de home e
#      credencial. Cada uma foi vista num incidente ou e obvia o bastante;
#   3. passa limpo com exit 0 quando nao ha nada;
#   4. e — o item que mais importa para nao dar falsa seguranca — que o texto limpo
#      DIGA o que o script nao sabe ver. Nome de pessoa nao tem padrao, foi o que
#      passou em 2026-08-10, e uma saida verde silenciosa ensinaria que passou tudo.
#
# A ultima secao e MUTACAO: tira o `process.exit(2)` e exige que o item 1 quebre.

set -u
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SBP="$(mktemp -d)"
trap 'rm -rf "$SBP"' EXIT

ok=0; falhou=0
tem()     { if echo "$2" | grep -qF "$3"; then ok=$((ok+1)); echo "  ok   $1"; else falhou=$((falhou+1)); echo "  FALHA $1 (esperava '$3')"; fi; }
nao_tem() { if echo "$2" | grep -qF "$3"; then falhou=$((falhou+1)); echo "  FALHA $1 (achou '$3')"; else ok=$((ok+1)); echo "  ok   $1"; fi; }
saiu()    { if [ "$2" = "$3" ]; then ok=$((ok+1)); echo "  ok   $1"; else falhou=$((falhou+1)); echo "  FALHA $1 (exit $2, esperava $3)"; fi; }

roda() { node "$SRC/scripts/conferir-publicacao.cjs" "$1" 2>&1; }
codigo() { node "$SRC/scripts/conferir-publicacao.cjs" "$1" >/dev/null 2>&1; echo $?; }

echo "== 1. cada forma de dado sensivel =="

# O JID e o caso REAL: e assim que o telefone do terceiro entrou no relatorio de
# 2026-08-10, colado de uma saida de ferramenta sem ninguem reparar.
printf '# achado\n\nChat JID: <jid-do-contato-3>\n' > "$SBP/jid.md"
S="$(roda "$SBP/jid.md")"
tem   "pega JID de WhatsApp"        "$S" "jid-whatsapp"
saiu  "e RECUSA (exit 2)"           "$(codigo "$SBP/jid.md")" "2"

printf '# achado\n\nligar para (00) 90000-0001 depois\n' > "$SBP/tel.md"
tem   "pega telefone formatado"     "$(roda "$SBP/tel.md")" "telefone"

printf '# achado\n\nreportado por fulano@empresa.com.br\n' > "$SBP/mail.md"
tem   "pega e-mail"                 "$(roda "$SBP/mail.md")" "email"

printf '# achado\n\nabri C:\\Users\\Fulano\\Downloads\\print.jpeg\n' > "$SBP/home.md"
tem   "pega caminho de home"        "$(roda "$SBP/home.md")" "caminho-de-home"

printf '# achado\n\nrodei com api_key=abc123def456\n' > "$SBP/cred.md"
tem   "pega credencial"             "$(roda "$SBP/cred.md")" "credencial"

printf '# achado\n\ntoken ghp_abcdefghij0123456789klmnop\n' > "$SBP/chave.md"
S="$(roda "$SBP/chave.md")"
tem   "pega chave com prefixo conhecido" "$S" "chave-conhecida"
tem   "e manda REVOGAR antes de editar"  "$S" "REVOGUE"

# A CHAVE em caixa alta e a forma mais comum em log e config, e um padrao
# case-sensitive fica cego justamente para ela. Estes tres casos existem porque uma
# tentativa de calar o falso positivo da prosa (abaixo) tirou o `i` da regex em
# 2026-08-17: `senha:` minusculo continuava pego, e `SENHA:`, `Token:` e `API_KEY:`
# passavam limpos. O detector fica cego para a forma mais comum e a bateria nao
# acusava, porque nenhum caso usava caixa alta.
printf '# achado\n\nSENHA: aBcD1234XyZw5678\n' > "$SBP/cred-alta.md"
tem   "pega credencial com a chave em caixa alta"  "$(roda "$SBP/cred-alta.md")" "credencial"
printf '# achado\n\nToken: aBcD1234XyZw5678\n' > "$SBP/cred-mista.md"
tem   "pega credencial com a chave em caixa mista" "$(roda "$SBP/cred-mista.md")" "credencial"
printf '# achado\n\nAPI_KEY: aBcD1234XyZw5678\n' > "$SBP/cred-apikey.md"
tem   "pega API_KEY em caixa alta"                 "$(roda "$SBP/cred-apikey.md")" "credencial"

# Segredo todo minusculo, sem digito: nao tem forma de segredo nenhuma, e mesmo
# assim e recusado — o valor esta SOZINHO na linha, e prosa nao termina assim.
printf '# achado\n\npassword: correcthorsebatterystaple\n' > "$SBP/cred-frase.md"
tem   "pega senha em minusculas sozinha na linha"  "$(roda "$SBP/cred-frase.md")" "credencial"

echo
echo "== 1b. e a PROSA com a palavra-chave nao e credencial =="
# 2026-08-17: este relatorio foi recusado por conter o assunto de um commit da main,
# em que `token` vem seguido de dois-pontos e de prosa comum. O checador degradou a
# evidencia de um relatorio — a citacao teve de ser truncada para publicar. A
# liberacao e estreita: palavra curta, minuscula, e a linha SEGUE com mais palavras.
printf '# achado\n\n41d73b7 Regua de orcamento de token: medir a abertura antes de comprimir qualquer coisa (#10)\n' > "$SBP/prosa.md"
S="$(roda "$SBP/prosa.md")"
saiu    "prosa com 'token:' passa (exit 0)"        "$(codigo "$SBP/prosa.md")" "0"
nao_tem "e nao inventa achado de credencial"       "$S" "credencial"

# O contrapeso, na MESMA forma de prosa: basta o valor ter digito para voltar a ser
# segredo. Sem este par, a liberacao acima seria indistinguivel de desligar o teste.
printf '# achado\n\nRegua de orcamento de token: aBcD1234XyZw5678 e o que usei\n' > "$SBP/prosa-cred.md"
tem   "mas com valor em forma de segredo recusa"   "$(roda "$SBP/prosa-cred.md")" "credencial"
saiu  "e o exit volta a 2"                         "$(codigo "$SBP/prosa-cred.md")" "2"

echo
echo "== 2. texto limpo passa =="
printf '# a trava nao travou\n\nO gate saiu com codigo 0 quando devia sair 2.\nMedido: 38 testes, 1 falha.\n' > "$SBP/limpo.md"
S="$(roda "$SBP/limpo.md")"
saiu    "exit 0"                    "$(codigo "$SBP/limpo.md")" "0"
tem     "diz que conferiu"          "$S" "CONFERIDO"
nao_tem "e nao inventa achado"      "$S" "RECUSADO"

echo
echo "== 3. o verde NAO pode dar falsa seguranca =="
# Este bloco e o que separa esta trava de um teatro de seguranca. O script nao ve
# nome de pessoa — e nome de pessoa foi exatamente o que vazou. Se a saida limpa
# nao disser isso, ela ensina que passou tudo.
tem "o texto limpo avisa que nao ve nome de pessoa" "$S" "nome de pessoa"
tem "e diz que nao ve nome de cliente"              "$S" "nome de cliente"
tem "e nao afirma que esta seguro"                  "$S" "nao achei o que sei"

# O nome sozinho realmente passa — a bateria PROVA a limitacao, em vez de deixar
# a documentacao afirmando sem evidencia.
printf '# achado\n\nO Emerson Coelho mandou o print e o agente errou.\n' > "$SBP/nome.md"
saiu "nome de pessoa sozinho passa mesmo (limitacao provada)" "$(codigo "$SBP/nome.md")" "0"

echo
echo "== 4. MUTACAO: transformar a recusa em aviso =="
# Se o exit 2 sumir, o script vira relatorio bonito que nao para nada — e o
# `commands/feedback.md` seguiria em frente publicando o Issue.
cp "$SRC/scripts/conferir-publicacao.cjs" "$SBP/original.cjs"
node -e "
  const fs=require('fs'), p=process.argv[1];
  const s=fs.readFileSync(p,'utf8'), a='  process.exit(2);';
  if(!s.includes(a)) { console.error('MUTACAO NAO APLICADA'); process.exit(1); }
  fs.writeFileSync(p, s.replace(a, '  process.exit(0);'));
" "$SRC/scripts/conferir-publicacao.cjs"
if [ $? -ne 0 ]; then falhou=$((falhou+1)); echo "  FALHA nao consegui aplicar a mutacao"; else
  saiu "com a recusa sabotada, o JID passa (prova que o exit 2 era a trava)" "$(codigo "$SBP/jid.md")" "0"
fi
cp "$SBP/original.cjs" "$SRC/scripts/conferir-publicacao.cjs"
saiu "e restaurado, volta a recusar" "$(codigo "$SBP/jid.md")" "2"

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" -eq 0 ]
