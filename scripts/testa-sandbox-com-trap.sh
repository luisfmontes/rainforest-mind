#!/bin/bash
# Guarda estatica da Tarefa 10 (docs/rainforest/planos/zerar-issues.md):
# bateria `testa-*.sh` que cria sandbox com `mktemp -d` e nao tem rede de
# seguranca no EXIT deixa a caixa orfa quando morre no meio — `set -e`,
# asserção que estoura, Ctrl+C. Foi assim que C:\tmp acumulou dezenas de
# sobras, 40 diretorios varridos numa unica limpeza.
#
# A regra, em ordem de gravidade:
#   - mais de um `mktemp -d` no arquivo exige o idioma SANDBOXES: um array
#     SANDBOXES=(), uma funcao que registra cada sandbox nele, e um unico
#     `trap ... EXIT` que varre o array inteiro — assim uma caixa criada e
#     esquecida no meio do arquivo ainda e' varrida quando o processo morre;
#   - um unico `mktemp -d` basta com um `trap ... EXIT` simples.
#
# Uso:
#   bash scripts/testa-sandbox-com-trap.sh              # varre o repositorio de verdade
#   bash scripts/testa-sandbox-com-trap.sh --autoteste   # prova a propria guarda com fixtures sinteticos
#
# Por que a guarda fica de fora da propria varredura em modo real: os
# fixtures do autoteste (mais abaixo) contem, como TEXTO literal dentro de
# heredocs, as mesmas strings "mktemp -d" que a guarda procura — contá-las
# aqui inflaria a propria contagem e a guarda se acusaria por conta do
# proprio material de teste. `scripts/testa-dependencias-de-bateria.sh` (que
# varre por jq/rg/python) tem a mesma isencao, pelo mesmo motivo.

set -u
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# sem_comentario <arquivo> — imprime as linhas do arquivo sem comentários
# (linhas que começam com espaço/tab/nada seguido de #)
sem_comentario() {
  grep -v '^[[:space:]]*#' "$1"
}

# checar_arquivo <arquivo> — imprime o motivo e devolve 1 se o arquivo
# reprova; nao imprime nada e devolve 0 se esta ok (inclusive quando nao usa
# `mktemp -d` nenhum).
checar_arquivo() {
  local f="$1"
  local n_mktemp
  local n_mktemp_em_funcoes

  # Linha de comentario pura (so espaco + #) nao conta: este proprio
  # repositorio documenta o idioma citando "mktemp -d" no comentario de
  # varias baterias, e contar o texto inflaria o numero real de chamadas.
  n_mktemp=$(sem_comentario "$f" | grep -c 'mktemp -d')
  if [ "$n_mktemp" -eq 0 ]; then
    return 0
  fi

  # Verificar mktemp -d dentro de funcoes: exige SANDBOXES+=
  n_mktemp_em_funcoes=$(sem_comentario "$f" | awk '
    /^[a-zA-Z_][a-zA-Z0-9_]*\s*\(\)/ { in_func=1; next }
    in_func && /^}/ { in_func=0; next }
    in_func && /mktemp -d/ { print "1"; exit }
  ')

  if [ "$n_mktemp" -gt 1 ] && ! sem_comentario "$f" | grep -q 'SANDBOXES'; then
    echo "  FALHA $f: $n_mktemp \`mktemp -d\` sem o idioma SANDBOXES"
    return 1
  fi

  if [ "$n_mktemp" -eq 1 ]; then
    # Regra: 1 mktemp -d exige trap com rm -rf, ou trap funcao() onde funcao tem rm -rf
    local trap_decl
    trap_decl=$(sem_comentario "$f" | grep 'trap.*EXIT' | head -1)

    if [ -z "$trap_decl" ]; then
      echo "  FALHA $f: 1 \`mktemp -d\` sem \`trap ... EXIT\`"
      return 1
    fi

    # Verificar se trap contém rm -rf direto
    if printf '%s' "$trap_decl" | grep -q 'rm -rf'; then
      return 0
    fi

    # Senão, procurar nome da função no trap e se usa SANDBOXES + cleanup
    local cleanup_func
    cleanup_func=$(printf '%s' "$trap_decl" | sed "s/.*trap[[:space:]]*'\?\([a-zA-Z_][a-zA-Z0-9_]*\).*/\1/")
    if [ -n "$cleanup_func" ] && [ "$cleanup_func" != "EXIT" ]; then
      # Procurar definição da função e se há rm -rf em algum lugar no arquivo
      if sem_comentario "$f" | grep -q "$cleanup_func\s*()"; then
        # Função existe, verificar se arquivo tem rm -rf
        if sem_comentario "$f" | grep -q 'rm -rf'; then
          return 0
        fi
      fi
    fi

    echo "  FALHA $f: 1 \`mktemp -d\` com \`trap ... EXIT\` mas sem \`rm -rf\`"
    return 1
  fi

  # Regra: mktemp -d dentro de funcao exige SANDBOXES+= (verificado diferentemente)
  if [ -n "$n_mktemp_em_funcoes" ] && ! grep -q 'SANDBOXES+=' "$f"; then
    echo "  FALHA $f: \`mktemp -d\` dentro de funcao sem \`SANDBOXES+=\`"
    return 1
  fi

  return 0
}

# --autoteste: prova a propria guarda contra 7 fixtures sinteticos, numa
# sandbox propria — que por sua vez segue a regra que ela mesma cobra (1
# mktemp -d aqui, com trap EXIT logo abaixo).
autoteste() {
  # Nao-local de proposito: o `trap ... EXIT` so dispara depois que esta
  # funcao ja retornou, e uma variavel `local` some de escopo nesse ponto —
  # sob `set -u` isso e' "unbound variable" bem na saida da propria guarda.
  sb="$(mktemp -d)"
  trap 'rm -rf "$sb"' EXIT

  # (a) dois `mktemp -d`, sem SANDBOXES -> tem que reprovar NOMEANDO o arquivo.
  cat > "$sb/testa-fixture-dois-sem-sandboxes.sh" <<'EOF'
#!/bin/bash
A="$(mktemp -d)"
B="$(mktemp -d)"
rm -rf "$A" "$B"
EOF

  # (b) um `mktemp -d`, sem `trap ... EXIT` -> tem que reprovar.
  cat > "$sb/testa-fixture-um-sem-trap.sh" <<'EOF'
#!/bin/bash
A="$(mktemp -d)"
rm -rf "$A"
EOF

  # (c) um `mktemp -d`, com `trap ... EXIT` -> tem que passar.
  cat > "$sb/testa-fixture-um-com-trap.sh" <<'EOF'
#!/bin/bash
A="$(mktemp -d)"
trap 'rm -rf "$A"' EXIT
EOF

  # (d) dois `mktemp -d` e `SANDBOXES` só em comentário -> reprova
  cat > "$sb/testa-fixture-dois-comentario.sh" <<'EOF'
#!/bin/bash
# SANDBOXES array - nao vai funcionar aqui
A="$(mktemp -d)"
B="$(mktemp -d)"
rm -rf "$A" "$B"
EOF

  # (e) um `mktemp -d` com `trap 'echo tchau' EXIT` -> reprova (sem rm -rf)
  cat > "$sb/testa-fixture-trap-sem-rm.sh" <<'EOF'
#!/bin/bash
A="$(mktemp -d)"
trap 'echo tchau' EXIT
rm -rf "$A"
EOF

  # (f) `mktemp -d` dentro de função sem `SANDBOXES+=` -> reprova
  cat > "$sb/testa-fixture-funcao-sem-sandboxes.sh" <<'EOF'
#!/bin/bash
helper() {
  local sb="$(mktemp -d)"
  rm -rf "$sb"
}
helper
EOF

  # (g) `mktemp -d` dentro de função com `SANDBOXES+=` no corpo, `trap cleanup EXIT` e `cleanup()` com `rm -rf` -> passa
  cat > "$sb/testa-fixture-funcao-com-sandboxes.sh" <<'EOF'
#!/bin/bash
SANDBOXES=()
nova_sandbox() {
  local sandbox="$(mktemp -d)"
  SANDBOXES+=("$sandbox")
  echo "$sandbox"
}
cleanup() {
  for s in "${SANDBOXES[@]}"; do
    rm -rf "$s"
  done
}
trap cleanup EXIT
sb=$(nova_sandbox)
EOF

  local ok=0 falhou=0 saida

  echo "== 1. dois mktemp -d sem SANDBOXES: reprova nomeando o arquivo =="
  if saida="$(checar_arquivo "$sb/testa-fixture-dois-sem-sandboxes.sh")"; then
    falhou=$((falhou+1)); echo "  FALHA deveria ter reprovado a fixture 'dois sem SANDBOXES'"
  else
    if printf '%s' "$saida" | grep -q "testa-fixture-dois-sem-sandboxes.sh"; then
      ok=$((ok+1)); echo "  ok   reprovada, e a saida nomeia o arquivo:"
      echo "$saida" | sed 's/^/       /'
    else
      falhou=$((falhou+1)); echo "  FALHA reprovou mas nao nomeou o arquivo: $saida"
    fi
  fi

  echo
  echo "== 2. um mktemp -d sem trap ... EXIT: reprova =="
  if checar_arquivo "$sb/testa-fixture-um-sem-trap.sh" >/dev/null; then
    falhou=$((falhou+1)); echo "  FALHA deveria ter reprovado a fixture 'um sem trap'"
  else
    ok=$((ok+1)); echo "  ok   reprovada"
  fi

  echo
  echo "== 3. um mktemp -d com trap ... EXIT: passa =="
  if checar_arquivo "$sb/testa-fixture-um-com-trap.sh" >/dev/null; then
    ok=$((ok+1)); echo "  ok   passou"
  else
    falhou=$((falhou+1)); echo "  FALHA deveria ter passado a fixture 'um com trap'"
  fi

  echo
  echo "== 4. dois mktemp -d e SANDBOXES só em comentário: reprova =="
  if checar_arquivo "$sb/testa-fixture-dois-comentario.sh" >/dev/null; then
    falhou=$((falhou+1)); echo "  FALHA deveria ter reprovado a fixture 'dois em comentário'"
  else
    ok=$((ok+1)); echo "  ok   reprovada"
  fi

  echo
  echo "== 5. um mktemp -d com trap 'echo tchau' EXIT: reprova =="
  if checar_arquivo "$sb/testa-fixture-trap-sem-rm.sh" >/dev/null; then
    falhou=$((falhou+1)); echo "  FALHA deveria ter reprovado a fixture 'trap sem rm'"
  else
    ok=$((ok+1)); echo "  ok   reprovada"
  fi

  echo
  echo "== 6. mktemp -d dentro de função sem SANDBOXES+=: reprova =="
  if checar_arquivo "$sb/testa-fixture-funcao-sem-sandboxes.sh" >/dev/null; then
    falhou=$((falhou+1)); echo "  FALHA deveria ter reprovado a fixture 'função sem SANDBOXES'"
  else
    ok=$((ok+1)); echo "  ok   reprovada"
  fi

  echo
  echo "== 7. mktemp -d em função com SANDBOXES+=, cleanup, rm -rf: passa =="
  if checar_arquivo "$sb/testa-fixture-funcao-com-sandboxes.sh" >/dev/null; then
    ok=$((ok+1)); echo "  ok   passou"
  else
    falhou=$((falhou+1)); echo "  FALHA deveria ter passado a fixture 'função com SANDBOXES'"
  fi

  echo
  echo "== resultado: $ok ok, $falhou falha(s) =="
  [ "$falhou" -eq 0 ]
}

# modo real: varre os testa-*.sh do repositorio (menos esta propria guarda,
# pelo motivo explicado no cabecalho) e reprova quem nao segue o idioma.
main_scan() {
  local arquivos total ok=0 falhou=0 f saida
  arquivos=$(ls "$RAIZ"/scripts/testa-*.sh "$RAIZ"/hooks/testa-*.sh 2>/dev/null | grep -v '/testa-sandbox-com-trap\.sh$')
  total=$(printf '%s\n' "$arquivos" | grep -c .)
  if [ "$total" -lt 10 ]; then
    falhou=$((falhou+1)); echo "  FALHA achei $total baterias — glob quebrado"
  fi

  echo "== cada testa-*.sh com mktemp -d tem rede de seguranca no EXIT =="
  for f in $arquivos; do
    if saida="$(checar_arquivo "$f")"; then
      ok=$((ok+1))
    else
      falhou=$((falhou+1))
      echo "$saida"
    fi
  done

  echo
  echo "== resultado: $ok ok, $falhou falha(s) de $total arquivo(s) verificado(s) =="
  [ "$falhou" -eq 0 ]
}

if [ "${1:-}" = "--autoteste" ]; then
  autoteste
else
  main_scan
fi
