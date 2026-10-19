#!/usr/bin/env bash
# Nexus Studio doctor: checks each CLI and talks MCP to each server (initialize + tools/list).
# Exit status 0 when all three servers answer.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
PREFIX="${NEXUS_STUDIO_HOME:-$HOME/.nexus-studio}"
BIN="$PREFIX/bin"
WORK="${NEXUS_STUDIO_WORK:-$HOME/NexusStudio}"

ok()   { printf '  \033[1;32mOK\033[0m   %s\n' "$*"; }
bad()  { printf '  \033[1;31mFALHA\033[0m %s\n' "$*"; }
info() { printf '  \033[1;36m--\033[0m   %s\n' "$*"; }

# portable timeout (macOS has no `timeout`)
with_timeout() { perl -e 'alarm shift; exec @ARGV' "$@"; }

INIT='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"nexus-studio-doctor","version":"1.0.0"}}}'
INITED='{"jsonrpc":"2.0","method":"notifications/initialized"}'
LIST='{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
TRANSCRIBE='{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"command_list","arguments":{"filter":"transcript.generate"}}}'

FAILS=0
echo "Nexus Studio - diagnostico"
echo "  binarios: $BIN"
echo "  trabalho: $WORK"
[ -f "$PREFIX/versions.txt" ] && sed 's/^/  versao: /' "$PREFIX/versions.txt"

for app in photocraft filmcraft effectcraft; do
  echo
  echo "[$app]"
  if [ ! -x "$BIN/$app-cli" ]; then
    bad "$app-cli nao instalado (rode o instalador)"
    FAILS=$((FAILS + 1))
    continue
  fi
  ok "$app-cli encontrado"

  extra=""
  [ "$app" = "filmcraft" ] && extra="$TRANSCRIBE"
  out="$( { printf '%s\n%s\n%s\n' "$INIT" "$INITED" "$LIST"; [ -n "$extra" ] && printf '%s\n' "$extra"; sleep 4; } \
          | with_timeout 40 bash "$HERE/run-mcp.sh" "$app" 2>"$PREFIX/doctor-$app.log" )"

  if printf '%s' "$out" | grep -q '"serverInfo"'; then
    ok "servidor MCP respondeu ao initialize"
  else
    bad "servidor MCP nao respondeu (veja $PREFIX/doctor-$app.log)"
    FAILS=$((FAILS + 1))
    continue
  fi

  n="$(printf '%s' "$out" | grep -o '"inputSchema"' | wc -l | tr -d ' ')"
  if [ "${n:-0}" -gt 0 ]; then ok "$n ferramentas MCP disponiveis"; else bad "tools/list vazio"; FAILS=$((FAILS + 1)); fi

  if [ "$app" = "filmcraft" ]; then
    if printf '%s' "$out" | grep -qE 'enabled\\?"[[:space:]]*:[[:space:]]*true'; then
      ok "transcricao automatica (Whisper) disponivel"
    else
      info "transcricao automatica NAO disponivel nesta versao: para legendas automaticas rode o instalador com --legendas"
    fi
  fi
done

echo
if [ "$FAILS" = 0 ]; then
  echo "Tudo certo: os 3 servidores responderam."
  exit 0
fi
echo "$FAILS problema(s) encontrado(s)."
exit 1
