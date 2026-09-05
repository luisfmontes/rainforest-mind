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
printf '# achado\n\nChat JID: 5500900000002@s.whatsapp.net\n' > "$SBP/jid.md"
S="$(roda "$SBP/jid.md")"
tem   "pega JID de WhatsApp"        "$S" "jid-whatsapp"
saiu  "e RECUSA (exit 2)"           "$(codigo "$SBP/jid.md")" "2"

printf '# achado\n\nligar para (00) 90000-0002 depois\n' > "$SBP/tel.md"
tem   "pega telefone formatado"     "$(roda "$SBP/tel.md")" "telefone"

# JID de GRUPO tem 18 digitos, e a faixa da regra parava em 15 ate 2026-09-02
# (Issue #149). O grupo passava por baixo da regra ESPECIFICA e acendia so o
# padrao generico de telefone, marcado "pode ser falso positivo" — a categoria
# que se aprende a ignorar. Foi assim que o JID real do grupo das rondas ficou
# no vigias/ERROS.md da main por dias.
printf '# achado\n\nGrupo: 120363123456789012@g.us\n' > "$SBP/jid-grupo.md"
S="$(roda "$SBP/jid-grupo.md")"
tem   "pega JID de GRUPO (18 digitos)"   "$S" "jid-whatsapp"
saiu  "e RECUSA (exit 2)"                "$(codigo "$SBP/jid-grupo.md")" "2"

# E o outro lado da mesma regra: alargar a faixa sem isentar o placeholder faria
# o gate recusar a propria documentacao de formato do repositorio.
printf '{\n  "destinoWhatsapp": "000000000000000000@g.us"\n}\n' > "$SBP/jid-zeros.md"
S="$(roda "$SBP/jid-zeros.md")"
nao_tem "placeholder de digito repetido NAO acende a regra de JID" "$S" "jid-whatsapp"
nao_tem "nem o padrao generico de telefone"                        "$S" "telefone"
saiu    "e passa limpo (exit 0)"  "$(codigo "$SBP/jid-zeros.md")" "0"

# O arquivo de verdade, nao uma imitacao dele: se o exemplo versionado do repo
# nao passa no proprio gate, o gate esta errado sobre o repo.
saiu "o vigia.config.exemplo.json do repo passa no gate" "$(codigo "$SRC/vigias/vigia.config.exemplo.json")" "0"

printf '# achado\n\nreportado por fulano@empresa.com.br\n' > "$SBP/mail.md"
tem   "pega e-mail"                 "$(roda "$SBP/mail.md")" "email"

printf '# achado\n\nabri C:\\Users\\Fulano\\Downloads\\print.jpeg\n' > "$SBP/home.md"
tem   "pega caminho de home"        "$(roda "$SBP/home.md")" "caminho-de-home"

# PLACEHOLDER de usuario nao e nome de ninguem. Terceira regra desta lista a
# ganhar a isencao, e pelo mesmo motivo das duas primeiras (Issue #149): a regra
# recusava a propria documentacao do formato que ela ensina — o `faca` dela diz
# "use \`<home>\`", e o texto que obedecia era recusado igual.
#
# Os caminhos sao montados com printf a partir do segmento, e nao escritos
# inteiros: este arquivo e versionado, e o gate barra (com razao) arquivo
# versionado que contenha a forma completa. Foi o que aconteceu com a bateria
# irma, scripts/testa-caminho-pessoal.sh, em 2026-09-02.
SEG_U="Us""ers"
printf '# achado\n\ncaminho: /c/%s/<nome>/.claude\n' "$SEG_U" > "$SBP/home-ph.md"
S="$(roda "$SBP/home-ph.md")"
nao_tem "placeholder <nome> NAO acende caminho-de-home"  "$S" "caminho-de-home"
saiu    "e passa limpo (exit 0)"  "$(codigo "$SBP/home-ph.md")" "0"

printf '# achado\n\ncaminho: C:\\%s\\%%USERNAME%%\\AppData\n' "$SEG_U" > "$SBP/home-var.md"
nao_tem "variavel de ambiente (%%USERNAME%%) tambem nao acende" "$(roda "$SBP/home-var.md")" "caminho-de-home"

printf '# achado\n\ncaminho: /c/%s/$USER/x\n' "$SEG_U" > "$SBP/home-shell.md"
nao_tem "variavel de shell (\$USER) tambem nao acende" "$(roda "$SBP/home-shell.md")" "caminho-de-home"

# E o lado que importa: nome de gente continua acendendo. Isencao que engole o
# caso real troca um falso positivo por um falso negativo, que e o pior negocio
# possivel numa trava de publicacao.
printf '# achado\n\ncaminho: /c/%s/Fulaninho/.claude\n' "$SEG_U" > "$SBP/home-real.md"
S="$(roda "$SBP/home-real.md")"
tem  "nome de pessoa CONTINUA acendendo"  "$S" "caminho-de-home"
saiu "e RECUSA (exit 2)"                  "$(codigo "$SBP/home-real.md")" "2"

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
echo "== 7b. SHA-1 de 40 hex nao e telefone (defect c) =="
# Arquivos de docs/rainforest/estado/ usam head/base com 40 hex (SHA-1).
# Subsequencia 5500 9000 0000 tem forma de telefone mas esta DENTRO do hash.
# Isenta se dentro de token hex de 7-40 caracteres.
printf '# estado\n\nhead = "abc123def4567890123455009000000012345e890"\n' > "$SBP/sha1.md"
S="$(roda "$SBP/sha1.md")"
nao_tem "SHA-1 de 40 hex nao acusa telefone"                    "$S" "telefone"
saiu    "e passa limpo (exit 0)"                                "$(codigo "$SBP/sha1.md")" "0"

echo
echo "== 7c. mas telefone FORA do SHA-1 continua sendo acusado =="
printf '# estado\n\nsha1: abc123def4567890123455009000000012345e890\ntel: (00) 90000-0001\n' > "$SBP/sha1-com-tel.md"
S="$(roda "$SBP/sha1-com-tel.md")"
tem     "telefone fora do hash e acusado"                       "$S" "telefone"
saiu    "e RECUSA (exit 2)"                                     "$(codigo "$SBP/sha1-com-tel.md")" "2"

echo
echo "== 6b. credencial com referencia de variavel (defect b) =="
# Interpolacao de shell, Windows var, Actions var nao sao segredos colados.
# O valor esta num lugar seguro, nao no arquivo.
printf '# config\n\ntoken=$TOKEN_SECRET\n' > "$SBP/cred-shell.md"
S="$(roda "$SBP/cred-shell.md")"
nao_tem "shell var \$VAR nao acusa credencial"                  "$S" "credencial"
saiu    "e passa (exit 0)"                                      "$(codigo "$SBP/cred-shell.md")" "0"

printf '# config\n\ntoken=${TOKEN_SECRET}\n' > "$SBP/cred-shell-chaves.md"
nao_tem "shell var \${VAR} nao acusa credencial"                "$(roda "$SBP/cred-shell-chaves.md")" "credencial"

printf '# config\n\npassword=%%USERNAME%%\n' > "$SBP/cred-windows.md"
nao_tem "Windows var %%%%VAR%%%% nao acusa credencial"          "$(roda "$SBP/cred-windows.md")" "credencial"

printf '# github\n\ntoken=${{secrets.TOKEN}}\n' > "$SBP/cred-actions.md"
nao_tem "GitHub Actions \${{ secrets.X }} nao acusa"            "$(roda "$SBP/cred-actions.md")" "credencial"


# A forma REAL da Issue #173, que as tres acima nao cobrem: numa URL de clone
# autenticado do Actions o valor capturado pela regex vai ate o proximo espaco e
# leva o host junto — a interpolacao, o arroba e o caminho do repositorio, tudo
# num token so. Isenta pelo valor INTEIRO, essa forma continuava acusada. As
# duas strings sao montadas por partes de proposito: com o literal escrito de
# uma vez, o gate de publicacao recusa a gravacao desta propria bateria.
CHAVE="x-access-"$'token'
URL_INDIRETA="git clone https://${CHAVE}:\${GH_TOKEN}@github.com/dono/repo.git"
printf '# workflow\n\n%s\n' "$URL_INDIRETA" > "$SBP/cred-url-indireta.md"
nao_tem "URL de clone com indirecao nao acusa credencial"      "$(roda "$SBP/cred-url-indireta.md")" "credencial"
saiu    "e passa (exit 0)"                                     "$(codigo "$SBP/cred-url-indireta.md")" "0"

URL_LITERAL="git clone https://${CHAVE}:$(printf 'A%.0s' $(seq 40))@github.com/dono/repo.git"
printf '# workflow\n\n%s\n' "$URL_LITERAL" > "$SBP/cred-url-literal.md"
tem     "a MESMA URL com valor literal continua acusada"       "$(roda "$SBP/cred-url-literal.md")" "credencial"
saiu    "e RECUSA (exit 2)"                                    "$(codigo "$SBP/cred-url-literal.md")" "2"

echo
echo "== 6c. mas valor literal continua sendo acusado =="
printf '# config\n\ntoken=sk-proj-abc123def456xyz789\n' > "$SBP/cred-literal.md"
S="$(roda "$SBP/cred-literal.md")"
tem     "valor literal e acusado"                               "$S" "credencial"
saiu    "e RECUSA (exit 2)"                                     "$(codigo "$SBP/cred-literal.md")" "2"

echo
echo "== 8. dump hexadecimal nao e telefone (Issue #144) =="
# Provar defeito de encoding exige colar bytes; ate 2026-09-02 o gate lia as
# colunas de `xxd` como telefone e barrava a unica evidencia que o metodo aceita.
# Os grupos abaixo sao so digitos de proposito (a forma que a regra de telefone
# consegue casar): 5500 9000 0000 1000 tem forma de telefone e esta DENTRO do dump.
printf '# prova\n\n```\n00000040: 5500 9000 0000 1000 7869 7420 3129 3a20  U.......xit 1): \n00000050: 6e61 6f20 6163 6865 6920 6f20 464f 434f  nao achei o FOCO\n```\n' > "$SBP/xxd.md"
saiu "xxd com grupos de digitos passa (exit 0)"                 "$(codigo "$SBP/xxd.md")" "0"
printf '# prova\n\n```\n00000040  55 00 90 00 00 00 10 00  78 69 74 20 31 29 3a 20  |U.......xit 1): |\n```\n' > "$SBP/hexdump.md"
saiu "hexdump -C passa (exit 0)"                                "$(codigo "$SBP/hexdump.md")" "0"
printf '# prova\n\n```\n 55 00 90 00 00 00 10 00 78 69 74 20 31 29 3a 20\n```\n' > "$SBP/od.md"
saiu "od -An -tx1 passa (exit 0)"                               "$(codigo "$SBP/od.md")" "0"
# A mesma linha com o telefone LEGIVEL na coluna ASCII continua recusada: a
# isencao cobre os grupos hex, nunca o que vem depois deles.
printf '# prova\n\n```\n00000040: 2830 3029 2039 3030 3030 2d30 3030 3120  (00) 90000-0001 \n```\n' > "$SBP/xxd-ascii.md"
saiu "telefone legivel na coluna ASCII do dump ainda recusa (exit 2)" "$(codigo "$SBP/xxd-ascii.md")" "2"
tem  "e aponta telefone"                                        "$(roda "$SBP/xxd-ascii.md")" "telefone"
# E prosa com o mesmo numero, fora de dump, continua recusada — a isencao nao e
# "parece hex", e forma de dump inteira.
printf '# prova\n\ncontato 5500 9000 0000 depois\n' > "$SBP/prosa-num.md"
saiu "mesmos digitos em prosa recusam (exit 2)"                  "$(codigo "$SBP/prosa-num.md")" "2"

echo
echo "== 9. telefone de digitos corridos nao e hash (achado da revisao do lote 4) =="
# A isencao de "dentro de token hex" usava a classe [0-9a-fA-F], e digito
# decimal e subconjunto dela: um telefone sem nenhuma pontuacao satisfazia o
# padrao de hash sozinho e saia isento — a forma mais comum de colar telefone,
# que e copiar de export de WhatsApp ou de planilha. Medido em 2026-09-04: a
# forma canonica com parenteses era acusada e a mesma pessoa em digitos
# corridos passava limpa.
DDD="11"
CORRIDO="$DDD""987654321"
printf '# nota\n\nligar para %s urgente\n' "$CORRIDO" > "$SBP/tel-corrido.md"
S="$(roda "$SBP/tel-corrido.md")"
tem     "telefone em digitos corridos e acusado"                "$S" "telefone"
saiu    "e RECUSA (exit 2)"                                     "$(codigo "$SBP/tel-corrido.md")" "2"

# Contraprova: o SHA-1 do caso 7b tem letra de hex, e continua isento. A
# exigencia nova e "o token precisa ter a-f", nao "acabou a isencao".
printf '# estado\n\nbase = "9fd0c3b45009000000012345e890abc123def456"\n' > "$SBP/sha1-letra.md"
nao_tem "hash com letra de hex continua isento"                 "$(roda "$SBP/sha1-letra.md")" "telefone"
saiu    "e passa (exit 0)"                                      "$(codigo "$SBP/sha1-letra.md")" "0"

echo
echo "== 10. referencia de variavel nao isenta o que vem grudado nela =="
# A isencao de indirecao (Issue #173) era ancorada so no comeco do valor, e a
# regex de credencial captura ate o proximo espaco. Bastava prefixar o segredo
# de verdade com uma referencia, sem espaco, para o valor inteiro sair isento.
# O que decide agora e o caractere seguinte ao fecha-chaves: delimitador de URL
# ou de caminho e estrutura; caractere de palavra e literal concatenado.
SEG="Sup3r""S3nhaReal123"
printf '# config\n\npassword=${DB_PASS}%s\n' "$SEG" > "$SBP/cred-grudada.md"
S="$(roda "$SBP/cred-grudada.md")"
tem     "literal grudado na referencia e acusado"               "$S" "credencial"
saiu    "e RECUSA (exit 2)"                                     "$(codigo "$SBP/cred-grudada.md")" "2"

# O recuo de `${VAR:-padrao}` NAO e olhado pela regra de credencial, e a
# contraprova disso e o idioma mais comum que existe: em docker-compose e
# .env.example o padrao e justamente um placeholder. Recusar isso ensinaria a
# rodar com a saida de emergencia ligada — medido na revisao de 2026-09-05.
printf '# compose\n\nPASSWORD=${PASSWORD:-changeme}\n' > "$SBP/cred-compose.md"
nao_tem "placeholder no recuo de ${VAR:-...} nao acusa"        "$(roda "$SBP/cred-compose.md")" "credencial"
saiu    "e passa (exit 0)"                                      "$(codigo "$SBP/cred-compose.md")" "0"

# O que segura segredo escondido num recuo e a regra de prefixo conhecido, que
# olha o texto inteiro e independe da isencao acima. Sem este caso, a fresta que
# a decisao aceita ficaria sem ninguem medindo o que ainda a cobre.
PRE="xoxb-"
printf '# config\n\ntoken=${SLACK:-%s1234567890}\n' "$PRE" > "$SBP/cred-padrao.md"
tem     "mas prefixo conhecido no recuo ainda e pego"           "$(roda "$SBP/cred-padrao.md")" "chave-conhecida"
saiu    "e RECUSA (exit 2)"                                     "$(codigo "$SBP/cred-padrao.md")" "2"

# Contraprova dupla: a referencia pura e a URL da #173 continuam isentas. Sem
# isto o conserto viraria "acabou a isencao", que e o defeito que a #173 abriu.
printf '# config\n\npassword=${DB_PASS}\n' > "$SBP/cred-pura.md"
nao_tem "referencia pura continua isenta"                       "$(roda "$SBP/cred-pura.md")" "credencial"
CHAVE2="x-access-"$'token'
URL2="git clone https://${CHAVE2}:\${GH_TOKEN}@github.com/dono/repo.git"
printf '# workflow\n\n%s\n' "$URL2" > "$SBP/cred-url-2.md"
nao_tem "URL de clone com indirecao continua isenta"            "$(roda "$SBP/cred-url-2.md")" "credencial"
saiu    "e passa (exit 0)"                                      "$(codigo "$SBP/cred-url-2.md")" "0"

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" -eq 0 ]
