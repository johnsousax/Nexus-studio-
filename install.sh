#!/usr/bin/env bash
# Nexus Studio installer: puts photocraft-cli, filmcraft-cli and effectcraft-cli in ~/.nexus-studio/bin.
#
# By default it downloads the official builds from the latest GitHub releases of
# storytold/photocraft, storytold/filmcraft and storytold/effectcraft: the signed and notarized
# CLI on macOS, the Linux tarball (x86_64 or aarch64) on Linux. Checksums are verified.
#
# Options:
#   --legendas     build filmcraft-cli from source with Whisper (automatic transcription and
#                  captions). Needs Xcode Command Line Tools; installs Rust if missing. 10-30 min.
#   --apps         also install the desktop apps (PhotoCraft, FilmCraft, EffectCraft) in /Applications
#   --fonte        build every CLI from source instead of downloading
#   --forcar       reinstall even if a CLI is already installed
#   --so APP       only this app (photocraft | filmcraft | effectcraft); repeatable
#
# Works with the bash 3.2 that ships with macOS.
set -euo pipefail

APPS_ALL="photocraft filmcraft effectcraft"
PREFIX="${NEXUS_STUDIO_HOME:-$HOME/.nexus-studio}"
BIN="$PREFIX/bin"
WORK="${NEXUS_STUDIO_WORK:-$HOME/NexusStudio}"
GH_API="${NEXUS_GH_API:-https://api.github.com}"
GH_GIT="${NEXUS_GH_GIT:-https://github.com}"
VERSIONS="$PREFIX/versions.txt"

WANT_CAPTIONS=0
WANT_APPS=0
FROM_SOURCE=0
FORCE=0
ONLY=""

while [ $# -gt 0 ]; do
  case "$1" in
    --legendas) WANT_CAPTIONS=1 ;;
    --apps) WANT_APPS=1 ;;
    --fonte) FROM_SOURCE=1 ;;
    --forcar) FORCE=1 ;;
    --so) shift; ONLY="$ONLY ${1:-}" ;;
    -h|--help) sed -n '2,17p' "$0"; exit 0 ;;
    *) echo "Opcao desconhecida: $1 (use --help)" >&2; exit 2 ;;
  esac
  shift
done

APPS="${ONLY:-$APPS_ALL}"

log()  { printf '\033[1;35m[nexus-studio]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[nexus-studio] aviso:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[nexus-studio] erro:\033[0m %s\n' "$*" >&2; exit 1; }

OS="$(uname -s)"
IS_MAC=0
[ "$OS" = "Darwin" ] && IS_MAC=1
IS_MAC="${NEXUS_ASSUME_MAC:-$IS_MAC}"  # testing hook
if [ "$IS_MAC" = 0 ] && [ "$OS" != "Linux" ] && [ "$FROM_SOURCE" = 0 ]; then
  warn "Nao ha pacote pronto para $OS: os CLIs serao compilados a partir do codigo-fonte."
  FROM_SOURCE=1
fi

command -v curl >/dev/null 2>&1 || die "curl nao encontrado."

mkdir -p "$BIN" "$PREFIX/src"
mkdir -p "$WORK/entrada" "$WORK/saidas" "$WORK/projetos" "$WORK/templates" "$WORK/marca"
touch "$VERSIONS"

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/nexus-studio.XXXXXX")"
cleanup() {
  if [ "$IS_MAC" = 1 ] && [ -d "$TMP_ROOT/mnt" ]; then hdiutil detach "$TMP_ROOT/mnt" -quiet >/dev/null 2>&1 || true; fi
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

# ---------------------------------------------------------------- helpers

sha256_of() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
  else sha256sum "$1" | awk '{print $1}'; fi
}

release_json() { # app -> JSON of the latest release (empty on failure)
  local auth=()
  if [ -n "${GITHUB_TOKEN:-}" ]; then auth=(-H "Authorization: Bearer $GITHUB_TOKEN"); fi
  curl -fsSL --retry 3 -H "Accept: application/vnd.github+json" ${auth[@]+"${auth[@]}"} \
    "$GH_API/repos/storytold/$1/releases/latest" 2>/dev/null || true
}

json_tag() { printf '%s' "$1" | grep -oE '"tag_name": *"[^"]+"' | head -1 | sed -E 's/.*"([^"]+)"$/\1/'; }

asset_url() { # json, extended regex matched against the URL
  printf '%s' "$1" | grep -oE '"browser_download_url": *"[^"]+"' \
    | sed -E 's/.*"(http[^"]+)"$/\1/' | grep -E "$2" | head -1 || true
}

record_version() { # app, how
  local tmp="$VERSIONS.tmp"
  grep -v "^$1 " "$VERSIONS" > "$tmp" 2>/dev/null || true
  echo "$1 $2 $(date +%Y-%m-%d)" >> "$tmp"
  mv "$tmp" "$VERSIONS"
}

verify_checksum() { # json, file, asset url
  local sums_url expected actual name
  if [ -n "$1" ]; then sums_url="$(asset_url "$1" '/SHA256SUMS(\.txt)?$')"
  else sums_url="$(dirname "$3")/SHA256SUMS.txt"; fi
  if [ -z "$sums_url" ]; then warn "release sem SHA256SUMS; checksum nao verificado"; return 0; fi
  curl -fsSL --retry 3 -o "$TMP_ROOT/SHA256SUMS" "$sums_url" || { warn "nao baixei SHA256SUMS"; return 0; }
  name="$(basename "$3")"
  expected="$(grep -E "[ *]$name\$" "$TMP_ROOT/SHA256SUMS" | awk '{print $1}' | head -1)"
  if [ -z "$expected" ]; then warn "$name nao esta no SHA256SUMS"; return 0; fi
  actual="$(sha256_of "$2")"
  [ "$expected" = "$actual" ] || die "checksum invalido para $name (esperado $expected, veio $actual)"
  log "checksum ok: $name"
}

unzip_to() { # zip, dir
  mkdir -p "$2"
  if [ "$IS_MAC" = 1 ] && command -v ditto >/dev/null 2>&1; then ditto -x -k "$1" "$2"
  else unzip -q -o "$1" -d "$2"; fi
}

# ---------------------------------------------------------------- download

latest_tag_git() { # app -> newest vX.Y.Z tag, read with git (works when the GitHub API is rate limited)
  git ls-remote --tags --refs "$GH_GIT/storytold/$1.git" 2>/dev/null | awk -F/ '{print $3}' \
    | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1
}

# Sets REL_JSON (may be empty) and REL_TAG for an app.
resolve_release() {
  REL_JSON="$(release_json "$1")"
  REL_TAG="$(json_tag "$REL_JSON")"
  if [ -z "$REL_TAG" ] && command -v git >/dev/null 2>&1; then
    REL_JSON=""
    REL_TAG="$(latest_tag_git "$1")"
  fi
}

# asset URL from the release JSON, or the conventional download URL when only the tag is known
pick_asset() { # app, regex, conventional file name
  if [ -n "$REL_JSON" ]; then asset_url "$REL_JSON" "$2"
  elif [ -n "$REL_TAG" ]; then echo "$GH_GIT/storytold/$1/releases/download/$REL_TAG/$3"; fi
}

install_linux_release() { # app: official Linux tarball (bin/ + its files) under $PREFIX/apps/<app>
  local app="$1" arch url tgz dest
  case "$(uname -m)" in aarch64|arm64) arch=aarch64 ;; x86_64|amd64) arch=x86_64 ;; *) warn "$app: arquitetura $(uname -m) sem pacote"; return 1 ;; esac
  log "$app: procurando a ultima versao..."
  resolve_release "$app"
  [ -n "$REL_TAG" ] || { warn "$app: nao consegui descobrir a ultima versao"; return 1; }
  url="$(pick_asset "$app" "/${app}-[0-9][^/]*-linux-${arch}\\.tar\\.gz\$" "$app-${REL_TAG#v}-linux-$arch.tar.gz")"
  [ -n "$url" ] || { warn "$app: a release $REL_TAG nao tem pacote Linux $arch"; return 1; }
  tgz="$TMP_ROOT/$app.tar.gz"
  log "$app: baixando $(basename "$url") ($REL_TAG)"
  curl -fL --retry 3 --progress-bar -o "$tgz" "$url" || { warn "$app: download falhou"; return 1; }
  verify_checksum "$REL_JSON" "$tgz" "$url"
  dest="$PREFIX/apps/$app"
  rm -rf "$dest"; mkdir -p "$dest"
  tar -xzf "$tgz" -C "$dest" --strip-components=1 || { warn "$app: nao consegui abrir o pacote"; return 1; }
  [ -x "$dest/bin/$app-cli" ] || { warn "$app: o pacote nao contem bin/$app-cli"; return 1; }
  ln -sf "$dest/bin/$app-cli" "$BIN/$app-cli"
  record_version "$app" "$REL_TAG release linux-$arch"
  log "$app: instalado ($REL_TAG)"
}

install_cli_release() { # app
  local app="$1" json tag url zip x exe
  if [ "$IS_MAC" = 0 ]; then install_linux_release "$app"; return $?; fi
  log "$app: procurando a ultima versao..."
  resolve_release "$app"
  json="$REL_JSON"; tag="$REL_TAG"
  [ -n "$tag" ] || { warn "$app: nao consegui ler as releases no GitHub"; return 1; }
  url="$(pick_asset "$app" "/${app}-cli-[^/]*-macos-universal\\.zip\$" "$app-cli-${tag#v}-macos-universal.zip")"
  [ -n "$url" ] || { warn "$app: a release $tag nao tem o CLI para macOS"; return 1; }

  zip="$TMP_ROOT/$app-cli.zip"
  log "$app: baixando $(basename "$url") ($tag)"
  curl -fL --retry 3 --progress-bar -o "$zip" "$url" || { warn "$app: download falhou"; return 1; }
  verify_checksum "$json" "$zip" "$url"

  x="$TMP_ROOT/$app-cli"
  unzip_to "$zip" "$x" || { warn "$app: nao consegui abrir o zip"; return 1; }
  exe="$(find "$x" -type f -name "$app-cli" | head -1)"
  [ -n "$exe" ] || { warn "$app: o zip nao contem $app-cli"; return 1; }
  install -m 0755 "$exe" "$BIN/$app-cli" || return 1
  if [ "$IS_MAC" = 1 ]; then xattr -d com.apple.quarantine "$BIN/$app-cli" >/dev/null 2>&1 || true; fi
  record_version "$app" "$tag release"
  log "$app: instalado ($tag)"
}

# ---------------------------------------------------------------- build from source

ensure_toolchain() {
  if [ "$IS_MAC" = 1 ] && ! xcode-select -p >/dev/null 2>&1; then
    log "Abrindo o instalador das Command Line Tools da Apple (compilador e git)..."
    xcode-select --install >/dev/null 2>&1 || true
    die "Termine a instalacao das Command Line Tools na janela que abriu e rode o instalador de novo."
  fi
  command -v git >/dev/null 2>&1 || die "git nao encontrado."
  if ! command -v cargo >/dev/null 2>&1 && [ -f "$HOME/.cargo/env" ]; then
    # shellcheck disable=SC1091
    . "$HOME/.cargo/env"
  fi
  if ! command -v cargo >/dev/null 2>&1; then
    log "Instalando Rust (rustup)..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal
    # shellcheck disable=SC1091
    . "$HOME/.cargo/env"
  fi
  local v major minor
  v="$(rustc --version | awk '{print $2}')"
  major="${v%%.*}"; minor="$(echo "$v" | cut -d. -f2)"
  if [ "$major" -lt 1 ] || { [ "$major" -eq 1 ] && [ "$minor" -lt 95 ]; }; then
    if command -v rustup >/dev/null 2>&1; then
      log "Atualizando Rust ($v -> stable)..."
      rustup update stable >/dev/null
      rustup default stable >/dev/null
    else
      die "Rust $v e antigo demais (precisa 1.95+)."
    fi
  fi
}

build_cli_source() { # app, extra cargo args...
  local app="$1"; shift
  ensure_toolchain
  local json tag src
  json="$(release_json "$app")"
  tag="$(json_tag "$json")"
  src="$PREFIX/src/$app"
  rm -rf "$src"
  if [ -n "$tag" ]; then
    log "$app: baixando o codigo-fonte ($tag)..."
    GIT_LFS_SKIP_SMUDGE=1 git clone --quiet --depth 1 --branch "$tag" "$GH_GIT/storytold/$app.git" "$src" 2>/dev/null || tag=""
  fi
  if [ -z "$tag" ]; then
    log "$app: baixando o codigo-fonte (main)..."
    GIT_LFS_SKIP_SMUDGE=1 git clone --quiet --depth 1 "$GH_GIT/storytold/$app.git" "$src" \
      || { warn "$app: git clone falhou"; return 1; }
    tag="main@$(git -C "$src" rev-parse --short HEAD)"
  fi
  log "$app: compilando $app-cli $* (pode levar de 10 a 30 minutos)..."
  (
    cd "$src" || exit 1
    export CARGO_PROFILE_RELEASE_CODEGEN_UNITS=16 CARGO_PROFILE_RELEASE_LTO=false
    cargo build --release --locked -p "$app-cli" "$@" || cargo build --release -p "$app-cli" "$@"
  ) || { warn "$app: a compilacao falhou"; return 1; }
  [ -x "$src/target/release/$app-cli" ] || { warn "$app: binario nao gerado"; return 1; }
  install -m 0755 "$src/target/release/$app-cli" "$BIN/$app-cli" || return 1
  record_version "$app" "$tag source $*"
  log "$app: compilado e instalado ($tag)"
}

# ---------------------------------------------------------------- desktop apps

install_desktop_app() { # app
  local app="$1" json url dmg appdir dest
  [ "$IS_MAC" = 1 ] || { warn "apps de desktop: so no macOS"; return 0; }
  json="$(release_json "$app")"
  url="$(asset_url "$json" "/${app}-[0-9][^/]*-macos-universal\\.dmg\$")"
  [ -n "$url" ] || { warn "$app: nao achei o .dmg na ultima release"; return 0; }
  dmg="$TMP_ROOT/$app.dmg"
  log "$app: baixando o app ($(basename "$url"))"
  curl -fL --retry 3 --progress-bar -o "$dmg" "$url" || { warn "$app: download do app falhou"; return 0; }
  verify_checksum "$json" "$dmg" "$url"
  mkdir -p "$TMP_ROOT/mnt"
  hdiutil attach -nobrowse -readonly -mountpoint "$TMP_ROOT/mnt" "$dmg" -quiet \
    || { warn "$app: nao consegui abrir o .dmg"; return 0; }
  appdir="$(find "$TMP_ROOT/mnt" -maxdepth 1 -name '*.app' | head -1)"
  if [ -n "$appdir" ]; then
    dest="/Applications"
    [ -w "$dest" ] || { dest="$HOME/Applications"; mkdir -p "$dest"; }
    rm -rf "$dest/$(basename "$appdir")"
    cp -R "$appdir" "$dest/"
    log "$app: app instalado em $dest/$(basename "$appdir")"
  else
    warn "$app: o .dmg nao tem um .app"
  fi
  hdiutil detach "$TMP_ROOT/mnt" -quiet || true
  rmdir "$TMP_ROOT/mnt" 2>/dev/null || true
}

# ---------------------------------------------------------------- main

log "Instalando em $BIN"
log "Pasta de trabalho: $WORK"

FAILED=""
for app in $APPS; do
  case "$app" in photocraft|filmcraft|effectcraft) ;; *) warn "app desconhecido: $app"; continue ;; esac

  if [ "$app" = "filmcraft" ] && [ "$WANT_CAPTIONS" = 1 ]; then
    build_cli_source filmcraft --features whisper || FAILED="$FAILED $app"
    continue
  fi

  if [ -x "$BIN/$app-cli" ] && [ "$FORCE" = 0 ]; then
    log "$app: ja instalado (use --forcar para reinstalar)"
    continue
  fi

  if [ "$FROM_SOURCE" = 1 ]; then
    build_cli_source "$app" || FAILED="$FAILED $app"
  elif ! install_cli_release "$app"; then
    warn "$app: vou compilar a partir do codigo-fonte."
    build_cli_source "$app" || FAILED="$FAILED $app"
  fi
done

if [ "$WANT_APPS" = 1 ]; then
  for app in $APPS; do install_desktop_app "$app"; done
fi

log "Versoes instaladas:"
sed 's/^/    /' "$VERSIONS"

if [ -n "$FAILED" ]; then
  die "nao consegui instalar:$FAILED"
fi

log "Testando os servidores MCP..."
bash "$(cd "$(dirname "$0")" && pwd)/doctor.sh" || true

log "Pronto. No Claude Code, abra /mcp e reconecte photocraft, filmcraft e effectcraft (ou reinicie o Claude Code)."
