---
name: criativos-em-lote
description: Gera várias versões de um flyer, anúncio, post ou cardápio a partir de um template PSD no PhotoCraft (Photoshop open source) via MCP, trocando textos, preços, fotos e cores por planilha CSV ou lista, para teste A/B, catálogo de produtos ou campanhas. Também redimensiona para vários formatos. Use quando o usuário pedir criativos em massa, variações, versões de anúncio ou flyers a partir de PSD.
argument-hint: "[template.psd] [dados.csv]"
---

# Criativos em lote a partir de um PSD

Entrada: `$ARGUMENTS`. O template fica em `~/NexusStudio/templates/` ou `entrada/`; os dados vêm de um CSV ou de uma lista na conversa.

## 1. Entender o template (servidor `photocraft`)

1. `doc_open {"path":"/abs/template.psd"}`
2. `doc_inspect` e liste para o usuário as camadas editáveis:
   - camadas de texto (tipo e conteúdo atual): candidatas a `textReplacement`
   - smart objects e camadas de imagem (foto do produto, logo): candidatas a `pixelReplacement`
   - grupos ou camadas que ligam e desligam (selo "PROMO", "NOVO"): `visibility`
3. `doc_render_preview` e olhe o template.
4. Combine com o usuário quais campos variam. Se os dados vieram soltos, monte o CSV em `~/NexusStudio/entrada/<campanha>.csv`: a primeira linha tem os nomes das variáveis, a primeira coluna pode ser o nome de cada versão. Fotos entram como caminho absoluto. Exemplo:

   ```csv
   nome,titulo,preco,foto
   tenis-runner,Tênis Runner,"R$ 49,90",/Users/voce/NexusStudio/entrada/fotos/tenis.jpg
   bone-classic,Boné Classic,"R$ 79,90",/Users/voce/NexusStudio/entrada/fotos/bone.jpg
   ```

   Valores com vírgula (preços em reais) vão entre aspas. Ou use `;` como separador e passe `"delimiter":";"` no import.

## 2. Caminho A: Variáveis e Data Sets (preferido, igual ao Photoshop)

1. Defina as variáveis (confira os params com `command_list {"filter":"image.variables.define"}`):
   `command_run image.variables.define {"defs":[{"name":"titulo","layer":<id>,"type":"textReplacement"},{"name":"preco","layer":<id>,"type":"textReplacement"},{"name":"foto","layer":<id>,"type":"pixelReplacement","method":"fill"}]}`
2. `doc_import_data_sets {"path":"/abs/campanha.csv"}`
3. Teste uma versão antes de tudo: `command_run image.applyDataSet {"index":0}` → `doc_render_preview` → olhe se o texto cabe, se a foto ficou bem enquadrada e se o preço está legível. Ajuste o template (caixa de texto, `method` fit/fill) se precisar.
4. Exporte todas: `doc_export_data_sets {"dir":"<HOME>/NexusStudio/saidas/<campanha>","format":"png","naming":"{name}"}` (use `{index}` se houver nomes repetidos).

## 3. Caminho B: troca direta (quando as variáveis não servem)

Para cada versão, reabra o template para começar limpo:
1. `doc_open` no template
2. Textos: `command_run type.edit {"layer":<id>,"text":"..."}` (mantém o estilo). Para mudar cor ou tamanho de um trecho: `runs` com `start`/`end`.
3. Fotos: `command_run layer.smartObjects.replaceContents {"layer":<id>,"path":"/abs/foto.jpg"}`, ou `doc_place {"path":...,"fit":true}` em uma camada nova.
4. Cores: `command_list {"filter":"color"}` ou `{"filter":"overlay"}` para achar o comando de cor ou estilo da camada.
5. `doc_render_preview` na primeira versão; depois `doc_export {"path":"<HOME>/NexusStudio/saidas/<campanha>/<nome>.png"}` e `doc_close` sem salvar.
6. Para muitas versões, use `command_batch` com os passos de cada uma.

## 4. Formatos extras

Se pedirem vários tamanhos (feed 1080x1350, stories 1080x1920, quadrado 1080x1080), o ideal é ter um template por formato. Sem isso, use `image.canvasSize` e reposicione as camadas, ou `image.imageSize` só quando a proporção não muda. Sempre confira com `doc_render_preview`.

## 5. Variações para teste A/B

Quando o pedido for "teste A/B", proponha de 3 a 6 variações que mudem **uma coisa por vez** (headline, cor do CTA, foto, oferta) e nomeie os arquivos com a variável testada (`A-headline-dor.png`, `B-headline-ganho.png`). Para anúncios de clientes, use os textos e a identidade do cliente.

## 6. Entrega

Liste a pasta de saída (`ls`), confira a quantidade e entregue em uma ou duas linhas: quantas peças, pasta, e qualquer versão que precisou de ajuste manual (texto que não coube, foto cortada). Nunca sobrescreva o template original.
