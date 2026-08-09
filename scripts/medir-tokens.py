#!/usr/bin/env python3
r"""Conta tokens de arquivos pelo endpoint oficial count_tokens da Anthropic.

Por que existe: a decisao PT vs EN do SKILL.md precisa de token, nao de
caractere — o ganho do ingles esta na tokenizacao, e caractere nao mede isso.
E a referencia oficial e explicita sobre o atalho errado:

  "Do not use tiktoken. It's OpenAI's tokenizer. It undercounts Claude tokens
   by ~15-20% on typical text, and by much more on code or non-English input."

Nao existe tokenizer local para Claude. A unica contagem correta vem de
POST /v1/messages/count_tokens, entao este script fala com a API e nada mais.

Credencial, em ordem (a primeira que existir):
  1. ANTHROPIC_API_KEY no ambiente        -> header x-api-key
  2. ANTHROPIC_AUTH_TOKEN                 -> Authorization: Bearer + beta oauth
  3. chave "anthropicApiKey" no arquivo de credenciais fora dos repos:
     %USERPROFILE%\.claude\local-credentials.json (ou .claude-personal\...)
Sem nenhuma das tres, ele PARA e diz como resolver — em vez de estimar, que e
o erro que ele existe para impedir.

A fonte 3 e a preferida no dia a dia: a chave nao passa pela linha de comando
(que fica no historico do shell) nem pela conversa (que fica no transcript e
no banco do claude-mem), e o arquivo mora FORA de qualquer repositorio.

Uso:
  python scripts/medir-tokens.py arquivo.md [outro.md ...]
  python scripts/medir-tokens.py --comparar pt.txt en.txt
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

URL = "https://api.anthropic.com/v1/messages/count_tokens"
MODELO_PADRAO = "claude-opus-5"


class Erro(Exception):
    pass


def chave_do_arquivo() -> str | None:
    """Le anthropicApiKey do arquivo de credenciais, se existir. Nunca escreve
    nele, nunca imprime o valor, e nao reclama se o arquivo tiver outra coisa."""
    lar = Path(os.path.expanduser("~"))
    for caminho in (lar / ".claude" / "local-credentials.json",
                    lar / ".claude-personal" / "local-credentials.json"):
        if not caminho.is_file():
            continue
        try:
            dados = json.loads(caminho.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError):
            continue
        if isinstance(dados, dict) and isinstance(dados.get("anthropicApiKey"), str):
            if valor := dados["anthropicApiKey"].strip():
                return valor
    return None


def cabecalhos() -> dict[str, str]:
    base = {"content-type": "application/json", "anthropic-version": "2023-06-01"}
    if chave := os.environ.get("ANTHROPIC_API_KEY"):
        return {**base, "x-api-key": chave}
    if token := os.environ.get("ANTHROPIC_AUTH_TOKEN"):
        # Token OAuth vai em Authorization: Bearer, nunca em x-api-key, e exige
        # o header de beta — trocar de chave para token e mudanca de header.
        return {**base, "authorization": f"Bearer {token}",
                "anthropic-beta": "oauth-2025-04-20"}
    if chave := chave_do_arquivo():
        return {**base, "x-api-key": chave}
    raise Erro(
        "sem credencial.\n"
        "  Opcao A (preferida): acrescente \"anthropicApiKey\": \"sk-ant-...\" ao\n"
        "     %USERPROFILE%\\.claude\\local-credentials.json — a chave nao passa\n"
        "     pela linha de comando nem pela conversa. Gere em\n"
        "     https://platform.claude.com/settings/keys\n"
        "  Opcao B (pontual):   export ANTHROPIC_API_KEY=sk-ant-...\n"
        "  Opcao C (sem chave): ant auth login  &&  "
        "export ANTHROPIC_AUTH_TOKEN=$(ant auth print-credentials --access-token)\n"
        "  Nao ha tokenizer local para Claude, e tiktoken e da OpenAI — "
        "subconta Claude em 15-20%. Estimar aqui invalida a medicao."
    )


def contar(texto: str, modelo: str) -> int:
    corpo = json.dumps(
        {"model": modelo, "messages": [{"role": "user", "content": texto}]}
    ).encode("utf-8")
    req = urllib.request.Request(URL, data=corpo, headers=cabecalhos(), method="POST")
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return json.load(r)["input_tokens"]
    except urllib.error.HTTPError as e:
        detalhe = e.read().decode("utf-8", "replace")[:400]
        raise Erro(f"HTTP {e.code} do count_tokens: {detalhe}")
    except urllib.error.URLError as e:
        raise Erro(f"nao consegui falar com a API: {e.reason}")


def medir(caminho: Path, modelo: str) -> tuple[int, int, float]:
    texto = caminho.read_text(encoding="utf-8")
    tk = contar(texto, modelo)
    return len(texto), tk, len(texto) / tk if tk else 0.0


def main() -> int:
    p = argparse.ArgumentParser(prog="medir-tokens.py")
    p.add_argument("arquivos", nargs="+")
    p.add_argument("--modelo", default=MODELO_PADRAO)
    p.add_argument("--comparar", action="store_true",
                   help="dois arquivos: mostra a economia do segundo sobre o primeiro")
    a = p.parse_args()

    try:
        if a.comparar and len(a.arquivos) != 2:
            raise Erro("--comparar exige exatamente dois arquivos")
        linhas = []
        for nome in a.arquivos:
            caminho = Path(nome)
            if not caminho.is_file():
                raise Erro(f"nao achei {caminho}")
            chars, tk, razao = medir(caminho, a.modelo)
            linhas.append((caminho, chars, tk, razao))
            print(f"{caminho.name:24s} {chars:7d} chars  {tk:6d} tokens  "
                  f"{razao:.2f} chars/token")

        if a.comparar:
            (_, c1, t1, _), (_, c2, t2, _) = linhas
            print(f"\nmodelo: {a.modelo}")
            print(f"  tokens:     {t1} -> {t2}  ({(t1-t2)/t1*100:+.1f}%)")
            print(f"  caracteres: {c1} -> {c2}  ({(c1-c2)/c1*100:+.1f}%)")
            print("\nA diferenca entre as duas linhas acima E a resposta: se a queda "
                  "de token\nfor igual a de caractere, o ingles nao rendeu nada alem "
                  "de texto mais curto.")
    except Erro as e:
        print(f"erro: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
