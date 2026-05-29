#!/usr/bin/env bash
# lib/logger.sh — kolorowe logowanie do stdout + pliku

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC}  $(date '+%H:%M:%S') $*"; }
log_ok()      { echo -e "${GREEN}[PASS]${NC}  $(date '+%H:%M:%S') $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $(date '+%H:%M:%S') $*"; }
log_fail()    { echo -e "${RED}[FAIL]${NC}  $(date '+%H:%M:%S') $*"; }
log_banner()  {
  echo ""
  echo -e "${CYAN}${BOLD}════════════════════════════════════════════════${NC}"
  echo -e "${CYAN}${BOLD}  $*${NC}"
  echo -e "${CYAN}${BOLD}════════════════════════════════════════════════${NC}"
}
log_section() {
  echo ""
  echo -e "${BOLD}┌─ $* ─────────────────────────────────────────${NC}"
}
