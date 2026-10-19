# Nexus Studio

**Foto, vídeo e motion graphics controlados pelo Claude.** O Nexus Studio junta três apps open source num estúdio só e ensina o Claude a usá-los como um designer faria:

| App | Equivale a | O que o Claude faz com ele |
|---|---|---|
| **EffectCraft** | After Effects | motion graphics a 60 fps com motion blur: intros, textos animados, logo reveal, ofertas animadas, Lottie |
| **FilmCraft** | Premiere Pro | vídeo vertical para Reels, corte de hesitações e pausas, legendas, cor, exportação MP4 + SRT |
| **PhotoCraft** | Photoshop | abre PSD, troca textos e fotos, gera dezenas de variações de anúncio a partir de uma planilha |

Nada aqui é vídeo gerado por IA. O Claude monta cada peça camada por camada, com keyframes e easing, e entrega o arquivo final junto com o projeto editável.

Há duas formas de usar:

- **Plugin para Claude Code** (Mac e Linux): os apps rodam no seu computador e conversam com o Claude por MCP.
- **Skill para o Claude** (claude.ai, inclusive no celular): os apps rodam no ambiente de código do Claude, sem instalar nada.

---

## 1. Plugin para Claude Code

### Instalar

No Terminal:

```bash
claude plugin marketplace add johnsousax/Nexus-studio-
claude plugin install nexus-studio@nexus
```

Depois, dentro do Claude Code:

```
/nexus-studio:instalar
```

O instalador baixa as versões oficiais mais recentes dos três apps (no Mac, os binários assinados e notarizados pela Apple; no Linux, os pacotes oficiais), confere o SHA-256 de cada arquivo e cria a pasta de trabalho `~/NexusStudio`. Opções:

| Opção | O que faz |
|---|---|
| `--legendas` | compila o FilmCraft com Whisper para ter transcrição e legendas automáticas (10 a 30 min na primeira vez; instala Rust se faltar) |
| `--apps` | também instala os apps de desktop em /Applications (Mac) |
| `--forcar` | reinstala a última versão de cada app |
| `--so <app>` | instala só um app (`photocraft`, `filmcraft` ou `effectcraft`) |

Por fim, digite `/mcp` e reconecte `photocraft`, `filmcraft` e `effectcraft` (ou reinicie o Claude Code), e rode `/nexus-studio:testar`.

### Comandos

| Comando | O que faz |
|---|---|
| `/nexus-studio:motion` | motion graphics no EffectCraft. Pergunta o assunto e o estilo antes de criar, mostra o roteiro, anima e renderiza |
| `/nexus-studio:reels-legendado` | vídeo falado → Reels vertical 1080x1920, sem "hã" nem pausas, com legenda e áudio normalizado |
| `/nexus-studio:criativos-em-lote` | PSD + planilha CSV → variações de flyer ou anúncio (teste A/B, catálogo de produtos) |
| `/nexus-studio:psd-para-motion` | anima um flyer em PSD: exporta as camadas e cria um roteiro (zoom na data, logo reveal, CTA) |
| `/nexus-studio:instalar` | instala ou atualiza os apps |
| `/nexus-studio:testar` | diagnóstico e uma peça de teste real em cada app |

Também dá para pedir em linguagem natural: *"pega o vídeo ~/NexusStudio/entrada/depoimento.mp4 e faz um Reels legendado"*.

### Pastas

```
~/NexusStudio/
  entrada/     vídeos, fotos, PSDs e logos que você traz
  templates/   PSDs e templates reutilizáveis
  projetos/    projetos editáveis (.ecproj, .fcproj, .pcraft)
  saidas/      entregas finais (MP4, PNG, SRT, Lottie)
  marca/       sua identidade: logo em PNG, cores.txt (hex) e fontes.txt
```

Por segurança, o PhotoCraft só lê arquivos da sua pasta pessoal e só grava dentro de `~/NexusStudio`.

---

## 2. Skill para o Claude (claude.ai e celular)

1. Baixe [`dist/nexus-studio-skill.zip`](dist/nexus-studio-skill.zip).
2. No Claude, abra as configurações de **Skills** e envie o arquivo.
3. Peça normalmente, por exemplo: *"cria um motion de 10 s para Reels anunciando a promoção de sexta"* ou *"faz 6 variações deste flyer"*, anexando os arquivos.

A skill baixa os três apps no ambiente de código do Claude (uns 15 s por conversa, com verificação de SHA-256), faz o trabalho pela linha de comando e devolve os arquivos. Ela precisa da execução de código com acesso a `github.com` ligada. O código da skill está em [`skill/nexus-studio/SKILL.md`](skill/nexus-studio/SKILL.md).

Nesse ambiente o Whisper não roda. A skill transcreve com o conector da ElevenLabs, quando ele estiver ligado, ou com um `.srt` que você mandar, e o FilmCraft faz o corte e as legendas a partir disso.

---

## O que foi testado

- Instalação dos pacotes oficiais de Linux pelo instalador (EffectCraft 0.11.1, FilmCraft 0.9.0, PhotoCraft 0.10.0), com checksum, e diagnóstico conversando por MCP com os três servidores reais (27, 17 e 25 ferramentas).
- O roteiro do `/nexus-studio:testar` executado nos servidores reais: composição a 60 fps com motion blur renderizada em MP4, flyer exportado em PNG e vídeo importado, sequenciado e exportado no FilmCraft.
- Pela linha de comando: Reels 1080x1920 com preenchimento de quadro e legenda queimada no vídeo, e corte de hesitação e de pausa a partir de uma transcrição importada, gerando as legendas.
- Plugin validado e carregado pelo Claude Code: 7 skills e 3 servidores MCP.

Ainda não testado num Mac de verdade: o download do CLI de macOS segue o nome oficial dos arquivos (`<app>-cli-<versão>-macos-universal.zip`), mas não rodou numa máquina Apple. A compilação com `--legendas` também não foi testada.

## Limitações

- Os três apps estão em **alpha**: funcionam, mas podem ter bugs, e o resultado não é idêntico ao da Adobe.
- Não abrem `.aep` nem `.prproj`. O PSD salvo pelo PhotoCraft nem sempre abre perfeito no Photoshop, então entregue em PNG, JPG ou MP4.
- Windows: ainda sem instalador. Os apps têm versões para Windows, mas o plugin cobre Mac e Linux.

## Créditos e licença

PhotoCraft, FilmCraft e EffectCraft são criados pela equipe [ArtCraft/Storytold](https://github.com/storytold) e distribuídos sob MIT ou Apache-2.0. O Nexus Studio não inclui nem modifica o código deles: só baixa as versões oficiais, configura e orquestra.

ArtCraft, Adobe, Photoshop, Premiere Pro e After Effects são marcas de seus respectivos donos. Este projeto é independente e não é afiliado a nenhum deles.

O código do Nexus Studio (plugin, skills e scripts) está sob a licença MIT: veja [LICENSE](LICENSE). Feito pela Nexus Company.
