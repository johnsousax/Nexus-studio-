#!/usr/bin/env bash
# Nexus Studio: starts one of the three MCP servers (photocraft | filmcraft | effectcraft).
# Binaries live in ~/.nexus-studio/bin (installed by scripts/install.sh).
# Work folder: ~/NexusStudio (entrada, saidas, projetos, templates, marca).
set -u

APP="${1:-}"
PREFIX="${NEXUS_STUDIO_HOME:-$HOME/.nexus-studio}"
BIN_DIR="$PREFIX/bin"
WORK="${NEXUS_STUDIO_WORK:-$HOME/NexusStudio}"

# Optional user settings, e.g. NEXUS_EFFECTCRAFT_GPU=1
if [ -f "$PREFIX/config" ]; then
  # shellcheck disable=SC1091
  . "$PREFIX/config"
fi

mkdir -p "$WORK/entrada" "$WORK/saidas" "$WORK/projetos" "$WORK/templates" "$WORK/marca" 2>/dev/null

case "$APP" in
  photocraft|filmcraft|effectcraft) ;;
  *)
    echo "nexus-studio: app desconhecido '$APP' (use photocraft, filmcraft ou effectcraft)" >&2
    exit 2
    ;;
esac

EXE="$BIN_DIR/$APP-cli"
if [ ! -x "$EXE" ]; then
  echo "nexus-studio: $APP-cli nao esta instalado em $BIN_DIR." >&2
  echo "nexus-studio: rode /nexus-studio:instalar no Claude Code e depois reconecte os servidores em /mcp." >&2
  exit 1
fi

case "$APP" in
  photocraft)
    # PhotoCraft only touches files inside these roots: reads anywhere in your home folder,
    # writes only inside the Nexus Studio work folder.
    exec "$EXE" mcp \
      --automation-read-root "$HOME" \
      --automation-write-root "$WORK"
    ;;
  filmcraft)
    exec "$EXE" mcp
    ;;
  effectcraft)
    args=(mcp --autosave)
    if [ "${NEXUS_EFFECTCRAFT_GPU:-0}" = "1" ]; then
      args+=(--gpu)
    fi
    exec "$EXE" "${args[@]}"
    ;;
esac
