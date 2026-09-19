# Régua 3 — Técnicas de ataque como lentes de detecção (defensivo, report-only)

Referência lida pelo agente `auditor-de-seguranca`. Cada classe de técnica de
ataque vira uma **lente de revisão**: o que caçar no código, o que faz o achado
ser seguro, como decidir, e como reportar. O auditor **aponta e nunca conserta**,
e **nunca gera requisição, payload ou exploit funcional** — descreve a *forma*
insegura do código, não a munição.

## Como o auditor usa esta régua
- A Régua 1 (OWASP Top 10 2025) e a Régua 2 (API 2023) rodam as **categorias**.
  Esta Régua 3 **afia no nível-de-técnica**: cada lente marca a categoria OWASP
  que refina, para compor sem duplicar.
- **Os números A01–A10 seguem a edição 2025** (a mesma da Régua 1), que
  renumerou as categorias em relação à 2021: Injeção é **A05** (não A03),
  Cryptographic Failures é **A04** (não A02), Security Misconfiguration é **A02**,
  Insecure Design é **A06**, e a nova **A03 é Software Supply Chain Failures**.
  Os títulos canônicos: A01 Broken Access Control, A02 Security Misconfiguration,
  A03 Software Supply Chain Failures, A04 Cryptographic Failures, A05 Injection,
  A06 Insecure Design, A07 Authentication Failures, A08 Software or Data Integrity
  Failures, A09 Security Logging and Alerting Failures, A10 Mishandling of
  Exceptional Conditions.
- Quando uma classe já é uma categoria inteira da Top 10, a lente é **curta e
  cruzada** — só o detalhe de técnica que o título da categoria não dá. As
  classes que a Top 10 **não** enumera como item próprio (SSTI, desserialização,
  request smuggling, confusão de dependência, segredos de CI/CD, JWT, cadeia de
  suprimentos, escape de container, LLM) ganham lente cheia.
- Escopo: só classes que se revisam em **código-fonte/config de repositório**.
  Fora ataque a sistema em execução, RF, pessoa (wireless, C2/EDR,
  pós-exploração, engenharia social, recon).

## Procedência e licença
Lentes **derivadas/inspiradas** no repositório `SnailSploit/claude-red` (MIT),
**reescritas** em formato defensivo report-only a partir de conhecimento OWASP —
nada colado verbatim. claude-red é MIT (derivar é permitido, com crédito). OWASP
citada por URL, com palavras próprias (repo MIT, OWASP CC BY-SA 4.0).

---

## A. Injeção (web) — afia A05 Injection (2025)

### SQL Injection (afia: A05 Injection)
**Severidade padrão:** high · **Derivada de:** claude-red/web/offensive-sqli (MIT)
**Onde procurar:** SQL montado por concatenação/interpolação de input
(`"... WHERE id=" + req.x`, f-strings/template strings com valor de request,
`String.format` em SQL); ORMs em modo raw (`session.execute(text(...))`,
`.raw()`, `.$queryRawUnsafe`); `ORDER BY`/nome de coluna/tabela vindo de input
(bind não cobre identificadores); stored procedures que concatenam.
**Como o seguro se parece:** consulta parametrizada / prepared statement em
100% dos caminhos; identificadores dinâmicos validados contra allow-list fixa;
ORM sem raw com input. No Protheus/ADVPL: `FWExecStatement`/bind, nunca `%exp%`
com input cru montando cláusula.
**Procedimento de revisão:** liste todo acesso a banco; para cada, confirme que
todo valor de request entra por bind; caçe o caminho de `ORDER BY`/coluna
dinâmica; verifique erros de banco não vazam query ao cliente.
**Formato de achado:** arquivo:linha · a forma concatenada · "input de <campo>
alcança a cláusula WHERE sem bind" · severidade. Report-only.

### RCE / Command Injection (afia: A05 Injection)
**Severidade padrão:** critical · **Derivada de:** claude-red/web/offensive-rce (MIT)
**Onde procurar:** shell com input (`os.system`, `subprocess(..., shell=True)`,
`exec`/`eval`, `child_process.exec`, backticks, `Runtime.exec` com string
única); desserialização/`pickle`/`yaml.load` inseguro (ver lente própria);
template server-side (ver SSTI); `Function()`/`vm` com input.
**Como o seguro se parece:** sem shell — argumentos como lista/array
(`execFile`, `subprocess([...], shell=False)`); nenhum `eval`/`exec` sobre
input; binário e args de allow-list; entradas validadas por tipo, não por
sanitização de string.
**Procedimento de revisão:** caçe toda execução de processo/avaliação dinâmica;
trace se algum argumento vem de request/arquivo/env atacável; confirme ausência
de `shell=True`/concatenação.
**Formato de achado:** arquivo:linha · a chamada · "input de <origem> vira
comando/código executado" · severidade. Report-only.

### Cross-Site Scripting (XSS) (afia: A05 Injection)
**Severidade padrão:** high · **Derivada de:** claude-red/web/offensive-xss (MIT)
**Onde procurar:** sink de HTML cru com input — `innerHTML`, `dangerouslySetInnerHTML`,
`v-html`, `document.write`, `$(...).html()`, template server-side com
auto-escape desligado (`| safe`, `{{{ }}}`, `mark_safe`, `Html.Raw`); reflexão
de parâmetro em resposta HTML/atributo/JS; DOM XSS via `location`/`postMessage`
em sink.
**Como o seguro se parece:** auto-escape do framework ligado e não contornado;
saída contextual (HTML/atributo/URL/JS) correta; sanitização por biblioteca
(DOMPurify) só quando HTML rico é requisito; CSP restritiva como defesa em
profundidade, não como controle único.
**Procedimento de revisão:** liste sinks de HTML/atributo; para cada, veja se o
dado é de origem não confiável e se o escape do contexto está garantido; cheque
`Content-Type` correto em respostas de API que devolvem HTML por engano.
**Formato de achado:** arquivo:linha · o sink · "input de <campo> chega ao DOM
sem escape de contexto" · severidade. Report-only.

### Server-Side Template Injection (SSTI) (afia: A05 Injection)
**Severidade padrão:** critical · **Derivada de:** claude-red/web/offensive-ssti (MIT)
**Onde procurar:** input concatenado na **string do template**, não nos dados —
`render_template_string(user)`, `Template(user).render()`, `env.from_string(user)`,
Twig/Freemarker/Velocity/Handlebars/ERB montando o corpo do template com input;
mensagens de erro, assuntos de e-mail e "temas" configuráveis que passam por
motor de template.
**Como o seguro se parece:** templates são **arquivos estáticos**; input entra
só como **contexto/variável** (`render(tpl, {name})`), nunca como corpo; se o
produto exige templates do usuário, motor em sandbox (SandboxedEnvironment) e
lista de atributos permitidos, tratado como superfície RCE.
**Procedimento de revisão:** caçe toda API de template que receba string
dinâmica; separe "template dinâmico" (perigo) de "contexto dinâmico" (ok);
onde houver template de usuário, exija sandbox explícita.
**Formato de achado:** arquivo:linha · a chamada · "input de <origem> compõe o
corpo do template; motor avalia como código" · critical. Report-only.

### XML External Entities (XXE) (afia: A02 Security Misconfiguration, também A05)
**Severidade padrão:** high · **Derivada de:** claude-red/web/offensive-xxe (MIT)
**Onde procurar:** parser XML com defaults inseguros — `DocumentBuilderFactory`
sem desabilitar DTD/entidades externas, `lxml` com `resolve_entities`/`no_network`
default, `libxml_disable_entity_loader` ausente (PHP antigo), SAX/DOM sem
`FEATURE_SECURE_PROCESSING`; upload/import de XML, SVG, DOCX/XLSX (zip de XML),
SOAP, SAML.
**Como o seguro se parece:** DTD e entidades externas **desligadas** no parser;
`XMLConstants.FEATURE_SECURE_PROCESSING` ligado; onde possível, JSON no lugar de
XML; SVG/office sanitizados antes de parse.
**Procedimento de revisão:** liste todo ponto que faz parse de XML (inclusive
formatos que são XML por baixo); confirme a config anti-DTD em cada um; cheque
libs que fazem parse implícito.
**Formato de achado:** arquivo:linha · o parser · "XML de <origem> é parseado
com DTD/entidade externa habilitada (leitura de arquivo/SSRF)" · severidade.
Report-only.

### Insecure Deserialization (afia: A08 Software or Data Integrity Failures)
**Severidade padrão:** critical · **Derivada de:** claude-red/web/offensive-deserialization (MIT)
**Onde procurar:** desserialização de dado não confiável em formato que
reconstrói objetos — `pickle.loads`, `yaml.load` sem `SafeLoader`,
`ObjectInputStream.readObject` (Java), `unserialize()` (PHP),
`BinaryFormatter`/`JavaScriptSerializer`/Newtonsoft com `TypeNameHandling`
(.NET), `Marshal.load` (Ruby); cookies/sessão/cache/fila que carregam objetos
serializados.
**Como o seguro se parece:** formato de dados sem execução (JSON/protobuf) para
dado externo; `yaml.safe_load`; sem `TypeNameHandling.All`; se objeto complexo é
inevitável, allow-list de tipos + assinatura/HMAC do blob antes de desserializar.
**Procedimento de revisão:** caçe toda desserialização; classifique a origem do
byte (externo = perigo); confirme formato seguro ou allow-list+integridade.
**Formato de achado:** arquivo:linha · a chamada · "blob de <origem> é
desserializado reconstruindo tipos arbitrários" · critical. Report-only.

---

## B. Acesso e lógica (web)

### IDOR / Broken Access Control (afia: A01 Broken Access Control / API1 BOLA)
**Severidade padrão:** high · **Derivada de:** claude-red/web/offensive-idor (MIT)
**Onde procurar:** handler que pega id do request e busca no store **sem**
cláusula de dono/tenant (`findByPk(id)`, `Model.objects.get(pk=id)` retornado ao
chamador); mass assignment (`Model(**body)`, `Object.assign(e, body)`); decisão
de acesso só no cliente; ids sequenciais expostos.
**Como o seguro se parece:** todo fetch escopado pelo principal **na query**
(`WHERE id=:id AND tenant=:ctx`), não num `if` pós-fetch; autorização
centralizada (policy/guard) em toda rota incl. PUT/PATCH/DELETE e API; allow-list
de campos graváveis; ids imprevisíveis **e** checagem de dono.
**Procedimento de revisão:** liste rotas que recebem id; trace até o acesso a
dados; confirme cláusula de dono; separe leitura de escrita (escrita costuma
esquecer o escopo); teste escalonamento horizontal e vertical (campo role/owner
vindo do cliente).
**Formato de achado:** arquivo:linha · origem do id · a checagem ausente ·
"usuário A acessa recurso de B; handler consulta só por id" · severidade. Report-only.

### Server-Side Request Forgery (SSRF) (afia: API7 SSRF; na Top 10 2025 sem item próprio — reporte sob A01/A02 conforme o vetor)
**Severidade padrão:** high · **Derivada de:** claude-red/web/offensive-ssrf (MIT)
**Onde procurar:** cliente HTTP/fetch com URL de input (`requests.get(url)`,
`fetch(user)`, webhooks, "importar de URL", geradores de PDF/preview de link,
proxies); parsers de imagem/SVG que buscam recurso remoto; SDK de cloud que
aceita endpoint configurável.
**Como o seguro se parece:** allow-list de host/esquema/porta; bloqueio de IP
privado/loopback/link-local/metadata (169.254.169.254) **após** resolução DNS
(anti-rebinding); sem seguir redirect para destino fora da allow-list; egress
de rede fechado por default.
**Procedimento de revisão:** liste toda saída de rede iniciada pelo servidor com
destino influenciável; confirme allow-list e bloqueio de faixas internas
pós-DNS; cheque metadata de cloud alcançável.
**Formato de achado:** arquivo:linha · a chamada · "URL de <origem> faz o
servidor requisitar destino interno/metadata" · severidade. Report-only.

### Business Logic Abuse (afia: A06 Insecure Design / API6)
**Severidade padrão:** medium · **Derivada de:** claude-red/web/offensive-business-logic (MIT)
**Onde procurar:** fluxo multi-etapa sem checar ordem/estado (pular pagamento,
reusar cupom, checkout com preço/quantidade do cliente); confiança em valor
calculável no cliente (preço, desconto, total); limites de negócio sem teto
(saque negativo, quantidade fracionada); idempotência ausente em operação
financeira.
**Como o seguro se parece:** máquina de estados server-side valida transição;
valores sensíveis recalculados no servidor; invariantes de negócio (>=0, tetos)
impostas na escrita; chave de idempotência em operação de dinheiro.
**Procedimento de revisão:** modele o fluxo feliz e pergunte "o que acontece se
eu pular/repetir/inverter esta etapa?"; caçe valor de negócio vindo do cliente.
**Formato de achado:** arquivo:linha · a etapa · "cliente controla <valor/ordem>
que deveria ser imposto no servidor" · severidade. Report-only.

### Open Redirect (afia: A01 Broken Access Control)
**Severidade padrão:** medium · **Derivada de:** claude-red/web/offensive-open-redirect (MIT)
**Onde procurar:** redirect com destino de input (`redirect(req.next)`,
`Location: <param>`, `returnUrl`/`continue` em login/SSO); meta-refresh/JS
`location = param`.
**Como o seguro se parece:** destino validado contra allow-list de caminhos
relativos/hosts próprios; nunca redireciona para URL absoluta de input; em SSO,
`redirect_uri` casado exatamente com registro.
**Procedimento de revisão:** liste redirects; confirme validação de destino;
atenção a fluxos de login (open redirect + OAuth vaza token).
**Formato de achado:** arquivo:linha · o redirect · "destino de <param> não é
validado; leva a domínio externo" · severidade. Report-only.

### HTTP Parameter Pollution (afia: A05 Injection)
**Severidade padrão:** low · **Derivada de:** claude-red/web/offensive-parameter-pollution (MIT)
**Onde procurar:** parâmetro duplicado tratado de forma divergente entre
camadas (WAF vê o primeiro, app vê o último; framework vira lista quando espera
escalar); dessincronia entre proxy e app.
**Como o seguro se parece:** leitura canônica de parâmetro (primeiro/último
definido e documentado); rejeição de duplicata onde faz sentido; validação de
tipo (escalar vs lista) explícita.
**Procedimento de revisão:** cheque como o framework resolve duplicatas e se
alguma decisão de segurança depende disso.
**Formato de achado:** arquivo:linha · o parse · "parâmetro duplicado resolve
diferente entre WAF/app, contornando validação" · severidade. Report-only.

---

## C. Protocolo e concorrência (web)

### HTTP Request Smuggling (afia: A02 Security Misconfiguration)
**Severidade padrão:** high · **Derivada de:** claude-red/web/offensive-request-smuggling (MIT)
**Onde procurar:** cadeia com proxy/CDN + backend que divergem no parsing de
`Content-Length` vs `Transfer-Encoding`; front-end e back-end de servidores/versões
diferentes; normalização de header inconsistente; keep-alive/pipelining entre
camadas.
**Como o seguro se parece:** um único servidor/normalização canônica na borda;
rejeitar requisição com CL **e** TE, ou TE malformado; HTTP/2 fim-a-fim onde
possível; versões de proxy e app alinhadas na interpretação.
**Procedimento de revisão:** mapeie a topologia de proxies; confirme política
única de CL/TE; isto é mais config/infra que código — reporte a divergência.
**Formato de achado:** componente · "proxy X e backend Y divergem em CL/TE,
permitindo dessincronizar requisições" · severidade. Report-only.

### Race Condition / TOCTOU (afia: A06 Insecure Design)
**Severidade padrão:** medium · **Derivada de:** claude-red/web/offensive-race-condition (MIT)
**Onde procurar:** checar-depois-agir sem atomicidade (saldo lido, validado e
gravado em passos separados; "resgatar cupom uma vez"; criação idempotente por
`SELECT then INSERT`); ausência de lock/transação/constraint única em operação
concorrente sensível.
**Como o seguro se parece:** operação atômica no banco (UPDATE condicional,
constraint única, `SELECT ... FOR UPDATE`, upsert); idempotência por chave; sem
janela entre validação e efeito.
**Procedimento de revisão:** caçe sequências ler→validar→gravar em recurso
compartilhado; pergunte "duas requisições simultâneas quebram a invariante?".
**Formato de achado:** arquivo:linha · a sequência · "duas chamadas concorrentes
gastam o mesmo saldo/cupom" · severidade. Report-only.

### GraphQL Abuse (afia: A05 Injection / API)
**Severidade padrão:** medium · **Derivada de:** claude-red/web/offensive-graphql (MIT)
**Onde procurar:** introspection ligada em produção; ausência de limite de
profundidade/complexidade/custo (query aninhada = DoS); autorização no resolver
ausente (BOLA por campo); `batching`/aliases sem rate limit; mutations sem os
mesmos controles das REST.
**Como o seguro se parece:** introspection off em prod; limite de profundidade e
custo; autorização por campo/objeto no resolver; rate limit ciente de
alias/batch; validação de input igual à das mutations REST.
**Procedimento de revisão:** confirme controles de custo e autorização por
resolver; cheque introspection e batching.
**Formato de achado:** arquivo:linha/resolver · "campo <x> sem checagem de
autorização" ou "sem limite de complexidade" · severidade. Report-only.

### File Upload (afia: A05 Injection / A06 Insecure Design)
**Severidade padrão:** high · **Derivada de:** claude-red/web/offensive-file-upload (MIT)
**Onde procurar:** upload que confia em extensão/`Content-Type` do cliente;
gravação dentro do webroot com nome do cliente; ausência de checagem de conteúdo
real (magic bytes); imagem processada por lib vulnerável; path do nome de arquivo
sem sanitização (path traversal); SVG/HTML servido inline.
**Como o seguro se parece:** allow-list de tipo por conteúdo real; nome gerado
pelo servidor; armazenamento **fora** do webroot ou em bucket sem execução;
`Content-Disposition: attachment` e `Content-Type` correto ao servir; limites de
tamanho; antivírus quando aplicável.
**Procedimento de revisão:** trace do recebimento à gravação e ao serviço;
confirme validação por conteúdo, destino não executável e nome seguro.
**Formato de achado:** arquivo:linha · "upload de <campo> gravado no webroot com
extensão do cliente; pode ser servido como código" · severidade. Report-only.

### WAF não é controle de origem (afia: A02 Security Misconfiguration)
**Severidade padrão:** informativo · **Derivada de:** claude-red/web/offensive-waf-bypass (MIT)
**Onde procurar:** correção que existe **só** no WAF/regra de borda enquanto o
código de origem segue vulnerável; comentário "protegido pelo WAF" sobre input
não sanitizado.
**Como o seguro se parece:** a vulnerabilidade é corrigida **na origem**; o WAF é
defesa em profundidade, não o conserto. Um achado real não é rebaixado porque
"o WAF pega".
**Procedimento de revisão:** ao avaliar qualquer achado, ignore o WAF como
mitigação suficiente; exija correção no código. Esta lente **não** descreve
evasão de WAF — descreve por que não se deve depender dele.
**Formato de achado:** arquivo:linha · "único controle é o WAF; origem segue
vulnerável a <classe>" · manter severidade da classe subjacente. Report-only.

---

## D. Autenticação e API

### JWT (afia: A07 Authentication Failures / API2)
**Severidade padrão:** high · **Derivada de:** claude-red/auth/offensive-jwt (MIT)
**Onde procurar:** verificação que aceita `alg: none`; verificação sem fixar o
algoritmo esperado (confusão RS256↔HS256, usando a chave pública como segredo
HMAC); segredo HMAC fraco/hardcoded; `verify=False`/decode sem verify;
`exp`/`nbf`/`aud`/`iss` não checados; revogação inexistente; `kid` usado para
carregar chave de caminho/URL de input.
**Como o seguro se parece:** algoritmo fixado na verificação (allow-list de um);
`none` rejeitado; segredo forte de secret manager; claims de tempo/audiência/
emissor validados; `kid` resolvido contra conjunto de chaves confiável; estratégia
de revogação (lista curta/rotação).
**Procedimento de revisão:** ache a verificação do token; confirme alg fixo,
rejeição de none, validação de claims, origem do segredo/chave.
**Formato de achado:** arquivo:linha · "verificação aceita alg de input / não
valida exp/aud" · severidade. Report-only.

### OAuth / OIDC (afia: A07 Authentication Failures / API2)
**Severidade padrão:** high · **Derivada de:** claude-red/auth/offensive-oauth (MIT)
**Onde procurar:** `redirect_uri` sem match exato (permite subpath/wildcard/host
parecido); ausência de `state` (CSRF no callback); ausência de PKCE em cliente
público; token em query string/URL (vaza em log/referer); `implicit flow`; `id_token`
sem validar assinatura/`nonce`/`aud`.
**Como o seguro se parece:** `redirect_uri` casado exatamente com registro;
`state` obrigatório e verificado; PKCE em SPA/mobile; `authorization code` flow;
tokens fora da URL; validação completa do `id_token`.
**Procedimento de revisão:** trace o fluxo de autorização e callback; confirme
match exato de redirect, state, PKCE e validação do id_token.
**Formato de achado:** arquivo:linha · "callback aceita redirect_uri não
registrado / sem state" · severidade. Report-only.

### API Abuse — rate, BOLA, BFLA (afia: API3/API4/API5)
**Severidade padrão:** medium · **Derivada de:** claude-red/api/offensive-api-abuse (MIT)
**Onde procurar:** endpoint sem rate limit/quota (força bruta, enumeração,
custo); função administrativa sem checar role (BFLA); recurso por id sem checar
dono (BOLA — ver IDOR); ausência de limite de tamanho/página; endpoints de
autenticação sem proteção anti-automação.
**Como o seguro se parece:** rate limit por identidade e por rota sensível;
autorização por função **e** por objeto; paginação com teto; anti-automação em
login/OTP/reset.
**Procedimento de revisão:** liste endpoints; para cada, verifique
autenticação, autorização de função, de objeto e limite de taxa.
**Formato de achado:** arquivo:linha · "rota <x> sem rate limit / sem checagem
de função" · severidade. Report-only.

### API Security — mass assignment e exposição excessiva (afia: API3 BOPLA / API6)
**Severidade padrão:** medium · **Derivada de:** claude-red/api/offensive-api-security (MIT)
**Onde procurar:** serializer/DTO que devolve o objeto inteiro (vaza campos
internos, hash de senha, flags); update que aceita o body cru (grava `is_admin`,
`owner_id`); versionamento/rotas antigas sem os mesmos controles.
**Como o seguro se parece:** DTO explícito de saída (allow-list de campos); DTO
de entrada com allow-list de campos graváveis; rotas legadas cobertas pelos
mesmos guards.
**Procedimento de revisão:** compare o modelo de dados com o que a API expõe e
aceita; caçe binding direto request→entidade.
**Formato de achado:** arquivo:linha · "endpoint devolve/aceita campo sensível
sem allow-list" · severidade. Report-only.

---

## E. CI/CD e cadeia de suprimentos

### CI/CD Pipeline (afia: A03 Software Supply Chain Failures / A08)
**Severidade padrão:** high · **Derivada de:** claude-red/cicd/offensive-cicd-pipeline (MIT)
**Onde procurar (GitHub Actions e afins):** `pull_request_target`/`workflow_run`
com checkout do código do PR **e** segredos no escopo; `issue_comment`/eventos de
fork com permissão de escrita (`contents:write`, `pull-requests:write`); expressão
`${{ github.event.* }}` interpolada direto em `run:` (injeção de script); actions
de terceiros **não pinadas por SHA**; `permissions` default amplas; `self-hosted
runner` em repo público.
**Como o seguro se parece:** `permissions` mínimas por job; sem segredo em
workflow disparado por fork não confiável; input de evento passado por `env:`,
nunca interpolado em `run:`; toda action de terceiro pinada por SHA completo;
runner efêmero/isolado.
**Procedimento de revisão:** leia cada workflow; caçe o par gatilho-de-fork +
segredo/escrita; caçe interpolação de `github.event` em `run`; confirme pinning
por SHA e escopo de `permissions`.
**Formato de achado:** arquivo:linha do YAML · "workflow <x> em <evento> tem
`contents:write` e roda código de fork" · severidade. Report-only.

### CI/CD Secrets (afia: A04 Cryptographic Failures / A07)
**Severidade padrão:** critical · **Derivada de:** claude-red/cicd/offensive-cicd-secrets (MIT)
**Onde procurar:** segredo hardcoded no repo (token, chave, senha, `.env`
commitado, chave privada, `id` de service account); segredo em log/echo do
pipeline; segredo passado por arg de linha de comando (aparece em `ps`); histórico
do git com segredo removido só no HEAD; `secrets` impressos em `set -x`.
**Como o seguro se parece:** segredos em secret manager/CI vault, injetados por
env em runtime; `.gitignore` cobre `.env`/chaves; scanner de segredo no
pre-commit e no CI; mascaramento em log; rotação após qualquer exposição.
**Procedimento de revisão:** grep por padrões de segredo no diff **e** no
histórico dos arquivos tocados; cheque se o pipeline ecoa segredo; confirme
`.gitignore` e scanner. **Este é o achado mais crítico antes de publicar.**
**Formato de achado:** arquivo:linha (ou commit) · tipo de segredo · "exposto em
repo/log; rotacionar" · critical. Report-only — **não cole o valor do segredo**,
só o local e o tipo.

### Dependency Confusion (afia: A03 Software Supply Chain Failures)
**Severidade padrão:** high · **Derivada de:** claude-red/supply-chain/offensive-dependency-confusion (MIT)
**Onde procurar:** pacote interno cujo nome **não** está registrado/reservado no
registro público (npm/PyPI/nuget) e cujo cliente resolve de múltiplos registros
sem prioridade; `.npmrc`/`pip.conf` sem escopo/registro fixo; nomes de pacote
interno vazados em `package.json`/lockfile público.
**Como o seguro se parece:** escopo/namespace reservado no registro público;
registro interno com prioridade explícita e `--index-url`/`registry` fixo;
lockfile com hash/integridade; nomes internos não vazados.
**Procedimento de revisão:** liste dependências internas; confirme reserva do
nome no público e resolução por registro fixo; cheque lockfile.
**Formato de achado:** arquivo:linha · "pacote interno <x> não reservado no
público; instalação pode puxar impostor" · severidade. Report-only.

### Supply Chain (afia: A03 Software Supply Chain Failures / A08)
**Severidade padrão:** high · **Derivada de:** claude-red/supply-chain/offensive-supply-chain (MIT)
**Onde procurar:** dependência sem lockfile/hash; versão flutuante (`^`,`latest`,
`*`); dependência abandonada/typosquat; `postinstall`/script de build de
dependência não auditado; imagem base sem pin de digest; ausência de SBOM/scan
de vulnerabilidade (`npm audit`, `pip-audit`, Dependabot).
**Como o seguro se parece:** lockfile com integridade; versões pinadas; scan de
vulnerabilidade e de licença no CI; imagens base por digest; revisão de scripts
de postinstall; procedência verificada onde possível.
**Procedimento de revisão:** confirme lockfile+hash, pinning, scanner ativo e
pin de digest das imagens.
**Formato de achado:** arquivo:linha · "dependência <x> flutuante/sem hash;
superfície de comprometimento na build" · severidade. Report-only.

---

## F. Cripto e transporte

### Crypto Attacks (afia: A04 Cryptographic Failures)
**Severidade padrão:** high · **Derivada de:** claude-red/crypto/offensive-crypto-attacks (MIT)
**Onde procurar:** algoritmo fraco/quebrado (MD5/SHA1 para senha, DES, RC4, ECB);
senha sem hash lento com sal (`bcrypt`/`argon2`/`scrypt` ausente); IV/nonce fixo
ou reusado; chave hardcoded; `Math.random`/RNG não-cripto para token/segredo;
comparação de MAC/hash não constante; criptografia caseira.
**Como o seguro se parece:** AEAD (AES-GCM/ChaCha20-Poly1305) com nonce único;
KDF lento para senha; RNG criptográfico para tokens; comparação constante;
chaves em secret manager; bibliotecas padrão, nunca cripto caseira.
**Procedimento de revisão:** liste uso de cripto/hash/RNG; caçe algoritmo fraco,
IV/nonce reusado, RNG errado e chave embutida.
**Formato de achado:** arquivo:linha · "senha com MD5 sem sal / nonce fixo em
AES" · severidade. Report-only.

### TLS (afia: A04 Cryptographic Failures / A02 Security Misconfiguration)
**Severidade padrão:** medium · **Derivada de:** claude-red/crypto/offensive-tls-attacks (MIT)
**Onde procurar:** validação de certificado desligada (`verify=False`,
`rejectUnauthorized:false`, `InsecureSkipVerify:true`, `TrustAllCerts`);
protocolo velho (SSLv3/TLS1.0/1.1) habilitado; HTTP sem redirect para HTTPS;
ausência de HSTS; cipher fraco; pin de certificado ausente onde é requisito.
**Como o seguro se parece:** validação de cadeia sempre ligada; TLS 1.2+ (ideal
1.3); HTTPS obrigatório + HSTS; ciphers modernos; verificação de hostname.
**Procedimento de revisão:** caçe qualquer desligamento de verificação TLS no
código/cliente HTTP; confirme versão mínima e HSTS.
**Formato de achado:** arquivo:linha · "cliente HTTP com verify desligado" ·
severidade. Report-only.

---

## G. Infra e IA

### Container Escape (afia: A02 Security Misconfiguration)
**Severidade padrão:** high · **Derivada de:** claude-red/container/offensive-container-escape (MIT)
**Onde procurar (Dockerfile/compose/manifest):** `privileged: true`; montar
`docker.sock` no container; `cap_add: [SYS_ADMIN, ...]`; `--pid=host`/`network:
host`; rodar como root (sem `USER`); FS raiz gravável; `hostPath` sensível
montado; seccomp/apparmor desabilitado.
**Como o seguro se parece:** sem privileged; capabilities mínimas (drop ALL);
usuário não-root; `readOnlyRootFilesystem`; sem socket do runtime montado;
seccomp/apparmor default ligados; sem namespaces do host.
**Procedimento de revisão:** leia Dockerfile e manifests; caçe privilégio,
socket do runtime, root e host namespaces.
**Formato de achado:** arquivo:linha · "container privileged / monta
docker.sock" · severidade. Report-only.

### Kubernetes (afia: A02 Security Misconfiguration / A01 Broken Access Control)
**Severidade padrão:** high · **Derivada de:** claude-red/container/offensive-k8s-attacks (MIT)
**Onde procurar:** RBAC amplo (`cluster-admin`, `verbs: ["*"]`, `resources:
["*"]`); ServiceAccount default automontada com poder; `securityContext`
permissivo (privileged, `runAsUser: 0`, `allowPrivilegeEscalation: true`);
Secrets em env/plaintext; ausência de NetworkPolicy; PodSecurity/admission fraco.
**Como o seguro se parece:** RBAC de menor privilégio; SA dedicada, automount
off quando não usa; securityContext restrito; secrets via secret store; Network
Policies default-deny; admission (PodSecurity/OPA) impondo baseline.
**Procedimento de revisão:** leia RBAC, SA, securityContext e NetworkPolicy dos
manifests; caçe curinga e privilégio.
**Formato de achado:** arquivo:linha · "Role com verbs:[*] / pod privileged" ·
severidade. Report-only.

### Cloud (IaC e credenciais) (afia: A02 Security Misconfiguration / A01 / A04)
**Severidade padrão:** high · **Derivada de:** claude-red/cloud/offensive-cloud (MIT)
**Onde procurar (Terraform/CFN/IaC):** bucket/blob público; SG/firewall
`0.0.0.0/0` em porta sensível; IAM com `Action:*`/`Resource:*`; chave de acesso
de longa duração hardcoded; storage/DB sem encryption at rest; logging/audit
desligado; secrets em variável de IaC em texto.
**Como o seguro se parece:** storage privado por default; ingress restrito;
IAM de menor privilégio; identidade de workload (roles) em vez de chave estática;
encryption at rest; audit log ligado; secrets em manager.
**Procedimento de revisão:** leia o IaC; caçe exposição pública, IAM curinga,
chave estática e criptografia/log desligados.
**Formato de achado:** arquivo:linha · "S3 público / IAM Action:*" · severidade.
Report-only.

### IA / LLM Security (afia: A05 Injection / A06 Insecure Design)
**Severidade padrão:** medium · **Derivada de:** claude-red/ai/offensive-ai-security (MIT)
**Onde procurar:** prompt montado com input não confiável sem fronteira
(injeção de prompt direta/indireta via conteúdo buscado); saída do LLM usada
como comando/SQL/HTML sem validação (o modelo é fonte não confiável); segredo/PII
no prompt de sistema exposto; ferramenta/função exposta ao modelo com poder
excessivo e sem confirmação humana; RAG que ingere fonte não confiável;
ausência de limite de custo/tamanho.
**Como o seguro se parece:** separação clara de instrução vs dados; saída do
modelo tratada como não confiável (validar/escapar antes de usar em sink);
princípio do menor privilégio nas tools expostas + confirmação para ação de
efeito; sanitização do conteúdo de RAG; tetos de custo/tamanho; segredos fora do
prompt.
**Procedimento de revisão:** trace input não confiável até o prompt e a saída do
modelo até qualquer sink de efeito; confirme tratamento da saída como não
confiável e privilégio das tools.
**Formato de achado:** arquivo:linha · "saída do LLM vira comando/SQL sem
validação" ou "conteúdo buscado entra no prompt sem fronteira" · severidade.
Report-only.
