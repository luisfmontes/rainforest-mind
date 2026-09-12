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

# modo --commit (D10): roda dentro de um repo de caixa de areia (cwd = $1), com o
# resto dos argumentos repassado apos "--commit". Mesma separacao roda/codigo do
# modo de arquivo acima, so que precisando do cwd certo para o git achar o repo.
roda_commit()   { local dir="$1"; shift; (cd "$dir" && node "$SRC/scripts/conferir-publicacao.cjs" --commit "$@") 2>&1; }
codigo_commit() { local dir="$1"; shift; (cd "$dir" && node "$SRC/scripts/conferir-publicacao.cjs" --commit "$@") >/dev/null 2>&1; echo $?; }

echo "== 1. cada forma de dado sensivel =="

# O JID e o caso REAL: e assim que o telefone do terceiro entrou no relatorio de
# 2026-08-10, colado de uma saida de ferramenta sem ninguem reparar.
# O literal completo do JID nunca aparece inteiro nesta fonte: pedacos de 2
# caracteres unidos por aspas adjacentes (mesma tecnica de CHAVE/URL_INDIRETA
# abaixo), senao este PROPRIO arquivo, lido pelo modo --commit (D10, tarefa 13),
# acenderia a regra que ele existe para provar.
printf '# ''ac''ha''do''\n''\n''Ch''at'' J''ID'': ''55''00''90''00''00''00''2@''s.''wh''at''sa''pp''.n''et''\n' > "$SBP/jid.md"
S="$(roda "$SBP/jid.md")"
tem   "pega JID de WhatsApp"        "$S" "jid-whatsapp"
saiu  "e RECUSA (exit 2)"           "$(codigo "$SBP/jid.md")" "2"

printf '# ''ac''ha''do''\n''\n''li''ga''r ''pa''ra'' (''00'') ''90''00''0-''00''02'' d''ep''oi''s\''n' > "$SBP/tel.md"
tem   "pega telefone formatado"     "$(roda "$SBP/tel.md")" "telefone"

# JID de GRUPO tem 18 digitos, e a faixa da regra parava em 15 ate 2026-09-02
# (Issue #149). O grupo passava por baixo da regra ESPECIFICA e acendia so o
# padrao generico de telefone, marcado "pode ser falso positivo" — a categoria
# que se aprende a ignorar. Foi assim que o JID real do grupo das rondas ficou
# no vigias/ERROS.md da main por dias.
printf '# ''ac''ha''do''\n''\n''Gr''up''o:'' 1''20''36''31''23''45''67''89''01''2@''g.''us''\n' > "$SBP/jid-grupo.md"
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

printf '# ''ac''ha''do''\n''\n''re''po''rt''ad''o ''po''r ''fu''la''no''@e''mp''re''sa''.c''om''.b''r\''n' > "$SBP/mail.md"
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

printf '# ''ac''ha''do''\n''\n''ro''de''i ''co''m ''ap''i_''ke''y=''ab''c1''23''de''f4''56''\n' > "$SBP/cred.md"
tem   "pega credencial"             "$(roda "$SBP/cred.md")" "credencial"

printf '# ''ac''ha''do''\n''\n''to''ke''n ''gh''p_''ab''cd''ef''gh''ij''01''23''45''67''89''kl''mn''op''\n' > "$SBP/chave.md"
S="$(roda "$SBP/chave.md")"
tem   "pega chave com prefixo conhecido" "$S" "chave-conhecida"
tem   "e manda REVOGAR antes de editar"  "$S" "REVOGUE"

# A CHAVE em caixa alta e a forma mais comum em log e config, e um padrao
# case-sensitive fica cego justamente para ela. Estes tres casos existem porque uma
# tentativa de calar o falso positivo da prosa (abaixo) tirou o `i` da regex em
# 2026-08-17: a chave `senha` minuscula seguida de dois-pontos continuava pega,
# e as chaves `SENHA`, `Token` e `API_KEY` (maiusculas ou mistas) seguidas do
# mesmo delimitador passavam limpas. O detector ficava cego para a forma mais
# comum e a bateria nao acusava, porque nenhum caso usava caixa alta.
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
saiu    "prosa com a palavra token seguida de dois-pontos passa (exit 0)" "$(codigo "$SBP/prosa.md")" "0"
nao_tem "e nao inventa achado de credencial"       "$S" "credencial"

# O contrapeso, na MESMA forma de prosa: basta o valor ter digito para voltar a ser
# segredo. Sem este par, a liberacao acima seria indistinguivel de desligar o teste.
printf '# ''ac''ha''do''\n''\n''Re''gu''a ''de'' o''rc''am''en''to'' d''e ''to''ke''n:'' a''Bc''D1''23''4X''yZ''w5''67''8 ''e ''o ''qu''e ''us''ei''\n' > "$SBP/prosa-cred.md"
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
# A sequencia numerica do fixture abaixo tem forma de telefone mas esta DENTRO
# do hash — nao repetimos os digitos aqui no comentario de proposito (a prosa
# tambem e texto deste arquivo, e o modo --commit, D10, le o arquivo inteiro).
# Isenta se dentro de token hex de 7-40 caracteres.
printf '# estado\n\nhead = "abc123def4567890123455009000000012345e890"\n' > "$SBP/sha1.md"
S="$(roda "$SBP/sha1.md")"
nao_tem "SHA-1 de 40 hex nao acusa telefone"                    "$S" "telefone"
saiu    "e passa limpo (exit 0)"                                "$(codigo "$SBP/sha1.md")" "0"

echo
echo "== 7c. mas telefone FORA do SHA-1 continua sendo acusado =="
printf '# estado\n\n''sh''a1'': ''ab''c1''23''de''f4''56''78''90''12''34''55''00''90''00''00''00''12''34''5e''89''0\''nt''el'': ''(0''0)'' 9''00''00''-0''00''1\''n' > "$SBP/sha1-com-tel.md"
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
# consegue casar): os grupos de digitos do dump abaixo tem forma de telefone e
# estao DENTRO do bloco de hex — a isencao cobre exatamente esse caso.
# O dump inteiro tambem vai em pedacos de 2 caracteres (mesma tecnica do JID
# acima): sem isso, os grupos de 4 hex que sao so digitos (ex.: "5500", "9000")
# acendem a regra de telefone quando o modo --commit le este PROPRIO arquivo.
printf '# ''pr''ov''a\''n\''n`''``''\n''00''00''00''40'': ''55''00'' 9''00''0 ''00''00'' 1''00''0 ''78''69'' 7''42''0 ''31''29'' 3''a2''0 '' U''..''..''..''.x''it'' 1''):'' \''n0''00''00''05''0:'' 6''e6''1 ''6f''20'' 6''16''3 ''68''65'' 6''92''0 ''6f''20'' 4''64''f ''43''4f''  ''na''o ''ac''he''i ''o ''FO''CO''\n''``''`\''n' > "$SBP/xxd.md"
saiu "xxd com grupos de digitos passa (exit 0)"                 "$(codigo "$SBP/xxd.md")" "0"
printf '# prova\n\n```\n00000040  55 00 90 00 00 00 10 00  78 69 74 20 31 29 3a 20  |U.......xit 1): |\n```\n' > "$SBP/hexdump.md"
saiu "hexdump -C passa (exit 0)"                                "$(codigo "$SBP/hexdump.md")" "0"
printf '# prova\n\n```\n 55 00 90 00 00 00 10 00 78 69 74 20 31 29 3a 20\n```\n' > "$SBP/od.md"
saiu "od -An -tx1 passa (exit 0)"                               "$(codigo "$SBP/od.md")" "0"
# A mesma linha com o telefone LEGIVEL na coluna ASCII continua recusada: a
# isencao cobre os grupos hex, nunca o que vem depois deles.
printf '# ''pr''ov''a\''n\''n`''``''\n''00''00''00''40'': ''28''30'' 3''02''9 ''20''39'' 3''03''0 ''30''30'' 2''d3''0 ''30''30'' 3''12''0 '' (''00'') ''90''00''0-''00''01'' \''n`''``''\n' > "$SBP/xxd-ascii.md"
saiu "telefone legivel na coluna ASCII do dump ainda recusa (exit 2)" "$(codigo "$SBP/xxd-ascii.md")" "2"
tem  "e aponta telefone"                                        "$(roda "$SBP/xxd-ascii.md")" "telefone"
# E prosa com o mesmo numero, fora de dump, continua recusada — a isencao nao e
# "parece hex", e forma de dump inteira.
printf '# ''pr''ov''a\''n\''nc''on''ta''to'' 5''50''0 ''90''00'' 0''00''0 ''de''po''is''\n' > "$SBP/prosa-num.md"
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
printf '# ''co''mp''os''e\''n\''nP''AS''SW''OR''D=''${''PA''SS''WO''RD'':-''ch''an''ge''me''}\''n' > "$SBP/cred-compose.md"
nao_tem "placeholder no recuo de ${VAR:-...} nao acusa"        "$(roda "$SBP/cred-compose.md")" "credencial"
saiu    "e passa (exit 0)"                                      "$(codigo "$SBP/cred-compose.md")" "0"

# O que segura segredo escondido num recuo e a regra de prefixo conhecido, que
# olha o texto inteiro e independe da isencao acima. Sem este caso, a fresta que
# a decisao aceita ficaria sem ninguem medindo o que ainda a cobre.
PRE="xoxb-"
printf '# config\n\n''to''ke''n=''${''SL''AC''K:''-%s''12''34''56''78''90''}\''n' "$PRE" > "$SBP/cred-padrao.md"
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
echo "== 9. termos privados — o que nao tem FORMA e so uma lista reconhece =="
# Nome de empregador, de cliente e de projeto interno nao tem regex. A lista mora
# FORA da arvore (~/.rainforest/termos-proibidos.txt) de proposito: escreve-la num
# arquivo versionado deste repo seria o proprio vazamento que a trava impede.
# Aqui o HOME e trocado por um sandbox, entao a bateria nunca le a lista real do
# usuario nem depende de ela existir.
LAR="$SBP/lar"
mkdir -p "$LAR/.rainforest"
# O comentario da lista e' uma frase que TAMBEM aparece como titulo markdown no
# arquivo limpo do caso 9b. Nao e coincidencia: e o que torna a mutacao capaz de
# falhar. Sem o filtro de `#`, a linha inteira `# titulo que tambem e comentario`
# vira termo, e o titulo identico do arquivo limpo passa a ser recusado.
printf '# titulo que tambem e comentario\n\nACME_INTERNO\nprojeto-secreto\n' > "$LAR/.rainforest/termos-proibidos.txt"

roda_com_lar()   { HOME="$LAR" USERPROFILE="$LAR" node "$SRC/scripts/conferir-publicacao.cjs" "$1" 2>&1; }
codigo_com_lar() { HOME="$LAR" USERPROFILE="$LAR" node "$SRC/scripts/conferir-publicacao.cjs" "$1" >/dev/null 2>&1; echo $?; }
VAZIO="$SBP/lar-vazio"
mkdir -p "$VAZIO"
roda_sem_lista()   { HOME="$VAZIO" USERPROFILE="$VAZIO" node "$SRC/scripts/conferir-publicacao.cjs" "$1" 2>&1; }
codigo_sem_lista() { HOME="$VAZIO" USERPROFILE="$VAZIO" node "$SRC/scripts/conferir-publicacao.cjs" "$1" >/dev/null 2>&1; echo $?; }

printf '# relatorio\n\nrodei no repo do ACME_INTERNO e deu certo\n' > "$SBP/termo.md"
tem  "termo da lista privada e pego"            "$(roda_com_lar "$SBP/termo.md")" "termo-privado"
saiu "e RECUSA (exit 2)"                        "$(codigo_com_lar "$SBP/termo.md")" "2"

# O termo NAO pode aparecer na saida: log de CI e publico, e imprimir o termo
# para avisar que ele nao pode ser publicado seria o mesmo erro com outra roupa.
nao_tem "a saida NAO ecoa o termo que bateu"    "$(roda_com_lar "$SBP/termo.md")" "ACME_INTERNO"

# Composto com hifen precisa casar: e a forma da maioria dos nomes de repo, e
# exigir fronteira de palavra nas pontas deixaria justamente eles passarem.
printf '# relatorio\n\nclonei o projeto-secreto ontem\n' > "$SBP/termo-hifen.md"
tem  "termo composto com hifen tambem e pego"   "$(roda_com_lar "$SBP/termo-hifen.md")" "termo-privado"

# Sem a lista o script nao inventa: passa limpo. Mas passar CALADO seria a falha
# de 2026-08-10 de novo — o instrumento dizendo "nao achei" sem ter procurado.
# Por isso a ausencia sai no bloco do que ele NAO ve, junto com o verde.
saiu "sem lista, o mesmo texto passa (exit 0)"  "$(codigo_sem_lista "$SBP/termo.md")" "0"
tem  "e o verde AVISA que a lista nao carregou" "$(roda_sem_lista "$SBP/termo.md")" "lista privada NAO foi carregada"

# Com a lista, o bloco do que ele nao ve muda de tom e diz quantos termos entraram.
printf '# relatorio\n\nnada demais aqui\n' > "$SBP/limpo-lar.md"
tem  "com lista, o verde diz quantos termos"    "$(roda_com_lar "$SBP/limpo-lar.md")" "2 termo(s) carregado(s)"

# Comentario e linha vazia NAO viram termo. Sem o filtro, a linha de comentario
# inteira entra na alternativa — e comentario de lista e prosa, entao ela colide
# com titulo de markdown e a trava passa a recusar arquivo limpo, que e como uma
# trava vira `--forcar` no dedo de quem usa.
printf '# titulo que tambem e comentario\n\ntexto qualquer\n' > "$SBP/so-comentario.md"
saiu "comentario da lista nao vira termo (exit 0)" "$(codigo_com_lar "$SBP/so-comentario.md")" "0"

echo
echo "== 9b. MUTACAO — sem o filtro de comentario, o caso acima para de pegar =="
# A prova de que o filtro e load-bearing: tira-se ele da COPIA e o texto limpo,
# que passava, passa a ser recusado por causa do `#` do cabecalho da lista.
MUT="$SBP/conferir-mutado.cjs"
# A aspa simples do fonte (`startsWith('#')`) e montada com fromCharCode(39):
# escreve-la literal aqui fecharia a aspa do proprio `node -e` e o teste passaria
# a medir outro comando. Mesma armadilha ja registrada neste acervo.
node -e '
  const fs = require("fs");
  const src = process.argv[1], dst = process.argv[2];
  const A = String.fromCharCode(39);
  const t = fs.readFileSync(src, "utf8");
  const de = ".filter((l) => l && !l.startsWith(" + A + "#" + A + "))";
  const para = ".filter((l) => l)";
  if (!t.includes(de)) { console.error("MUTACAO: ancora do filtro nao encontrada"); process.exit(1); }
  fs.writeFileSync(dst, t.split(de).join(para));
' "$SRC/scripts/conferir-publicacao.cjs" "$MUT"
COD_MUT="$(HOME="$LAR" USERPROFILE="$LAR" node "$MUT" "$SBP/so-comentario.md" >/dev/null 2>&1; echo $?)"
saiu "sem o filtro, texto limpo passa a ser RECUSADO (o filtro e load-bearing)" "$COD_MUT" "2"

echo
echo "== 11. --commit le o COMMIT, nao o disco (D10, tarefa 13) =="
# Repo de caixa de areia de VERDADE, caminho NATIVO (cygpath -m): o mesmo cuidado
# do hooks/testa-gate-staging-total.sh — Node no Windows nao resolve caminho MSYS
# e o git falharia em silencio, passando a bateria sem medir nada.
CPUB_POSIX="$(mktemp -d)"
CPUB="$(cygpath -m "$CPUB_POSIX" 2>/dev/null || printf '%s' "$CPUB_POSIX")"
git init -q "$CPUB"
git -C "$CPUB" config user.email t@t
git -C "$CPUB" config user.name t
git -C "$CPUB" config commit.gpgsign false

printf 'co''nt''at''o:'' f''ul''an''o@''em''pr''es''a.''co''m.''br''\n' > "$CPUB/relatorio.md"
git -C "$CPUB" add relatorio.md >/dev/null
git -C "$CPUB" commit -qm "relatorio com email" >/dev/null
# O segredo FICOU no commit. No disco, foi limpo SEM commitar — e' exatamente o
# defeito que D10 existe para pegar: disco limpo nao quer dizer commit limpo.
printf 'contato: <email>\n' > "$CPUB/relatorio.md"

S="$(roda_commit "$CPUB" HEAD)"
tem  "segredo so no commit, disco limpo -> --commit acha"  "$S" "email"
tem  "e aponta o ARQUIVO do commit"                         "$S" "relatorio.md"
saiu "e RECUSA (exit 2)"                                    "$(codigo_commit "$CPUB" HEAD)" "2"
tem  "e tambem acusa a divergencia disco/commit"             "$S" "diverge-do-commit"

# O modo ANTIGO (disco) nao muda: o arquivo, ja limpo em disco, passa liso. Os
# dois modos coexistem e um nao herda o resultado do outro.
saiu "modo disco (arquivo ja limpo) sai 0 -- os dois modos coexistem" \
     "$(codigo "$CPUB/relatorio.md")" "0"

echo
echo "== 12. --commit num RANGE de dois commits =="
RANGE_POSIX="$(mktemp -d)"
RANGE="$(cygpath -m "$RANGE_POSIX" 2>/dev/null || printf '%s' "$RANGE_POSIX")"
git init -q "$RANGE"
git -C "$RANGE" config user.email t@t
git -C "$RANGE" config user.name t
git -C "$RANGE" config commit.gpgsign false

printf 'base\n' > "$RANGE/x.md"
printf 'base\n' > "$RANGE/y.md"
git -C "$RANGE" add x.md y.md >/dev/null
git -C "$RANGE" commit -qm base >/dev/null
BASE_RANGE="$(git -C "$RANGE" rev-parse HEAD)"

# x.md: o segredo entra logo no comeco do range e continua ate o HEAD.
printf 'ba''se''\n''co''nt''at''o:'' f''ul''an''o@''em''pr''es''a.''co''m.''br''\n' > "$RANGE/x.md"
git -C "$RANGE" add x.md >/dev/null
git -C "$RANGE" commit -qm "x com email" >/dev/null

# y.md: o segredo entra e e' removido AINDA dentro do range — o conteudo final
# continua diferente do da base (para nao sair da lista de arquivos tocados),
# mas o HEAD:y.md esta limpo.
printf 'co''nt''at''o:'' f''ul''an''o@''em''pr''es''a.''co''m.''br''\n' > "$RANGE/y.md"
git -C "$RANGE" add y.md >/dev/null
git -C "$RANGE" commit -qm "y com email" >/dev/null
printf 'sem segredo agora\n' > "$RANGE/y.md"
git -C "$RANGE" add y.md >/dev/null
git -C "$RANGE" commit -qm "y limpo de novo" >/dev/null
HEAD_RANGE="$(git -C "$RANGE" rev-parse HEAD)"

S="$(roda_commit "$RANGE" "$BASE_RANGE..$HEAD_RANGE")"
tem     "range: segredo que fica ate o HEAD e' achado (x.md)"        "$S" "x.md"
tem     "                e' achado de email"                          "$S" "email"
nao_tem "range: segredo removido antes do HEAD nao aparece (y.md)"    "$S" "y.md"
saiu    "e RECUSA (exit 2, por causa so de x.md)"                     "$(codigo_commit "$RANGE" "$BASE_RANGE..$HEAD_RANGE")" "2"

echo
echo "== 13. duplicata via --commit (D10) =="
DUPC_POSIX="$(mktemp -d)"
DUPC="$(cygpath -m "$DUPC_POSIX" 2>/dev/null || printf '%s' "$DUPC_POSIX")"
git init -q "$DUPC"
git -C "$DUPC" config user.email t@t
git -C "$DUPC" config user.name t
git -C "$DUPC" config commit.gpgsign false
printf 'conteudo repetido sem segredo\n' > "$DUPC/um.md"
printf 'conteudo repetido sem segredo\n' > "$DUPC/dois.md"
git -C "$DUPC" add um.md dois.md >/dev/null
git -C "$DUPC" commit -qm "dois arquivos identicos" >/dev/null

S="$(roda_commit "$DUPC" HEAD)"
tem  "duplicata: acha o grupo"            "$S" "duplicata"
tem  "duplicata: nomeia os dois arquivos" "$S" "dois.md == um.md"
saiu "duplicata: RECUSA (exit 2)"         "$(codigo_commit "$DUPC" HEAD)" "2"

NAODUP_POSIX="$(mktemp -d)"
NAODUP="$(cygpath -m "$NAODUP_POSIX" 2>/dev/null || printf '%s' "$NAODUP_POSIX")"
git init -q "$NAODUP"
git -C "$NAODUP" config user.email t@t
git -C "$NAODUP" config user.name t
git -C "$NAODUP" config commit.gpgsign false
printf 'conteudo A sem segredo\n' > "$NAODUP/um.md"
printf 'conteudo B sem segredo\n' > "$NAODUP/dois.md"
git -C "$NAODUP" add um.md dois.md >/dev/null
git -C "$NAODUP" commit -qm "dois arquivos diferentes" >/dev/null
nao_tem "sem duplicata, nenhum achado desse tipo" "$(roda_commit "$NAODUP" HEAD)" "duplicata"
saiu    "e passa limpo (exit 0)"                  "$(codigo_commit "$NAODUP" HEAD)" "0"

echo
echo "== 14. ambiente: rev inexistente -> exit 69 (D5) =="
saiu "rev inexistente sai 69 (EX_UNAVAILABLE)" "$(codigo_commit "$CPUB" deadbeef)" "69"
tem  "stderr comeca com 'nao-verificavel:'"    "$(roda_commit "$CPUB" deadbeef)" "nao-verificavel:"

rm -rf "$CPUB_POSIX" "$RANGE_POSIX" "$DUPC_POSIX" "$NAODUP_POSIX"

echo
echo "== resultado: $ok ok, $falhou falha(s) =="
[ "$falhou" -eq 0 ]
