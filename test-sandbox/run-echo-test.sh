#!/usr/bin/env bash
# "hello slash" COMMAND 명령 테스트 종단 실행 스크립트
#
# slash-web-test / slash-api-test / slash-agent-test 세 브랜치를 이용해
# mock-api -> 로컬 에이전트(contract-agent CLI) -> 웹(vite dev server) 순으로
# 백그라운드에서 띄우고, 준비되면 브라우저로 /dev/echo-test를 자동으로 연다.
#
# 전제: slash-web, slash-api, slash-agent 세 저장소가 이 스크립트와 같은 부모
# 디렉터리 아래 형제 폴더로 존재해야 한다(예: ~/slash/slash-web, ~/slash/slash-api,
# ~/slash/slash-agent). 각 저장소는 -test 브랜치로 미리 체크아웃돼 있어야 한다.
#
# 사용법: ./run-echo-test.sh
# 종료:   Ctrl+C (백그라운드 프로세스 전부 정리됨)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

WEB_DIR="$BASE_DIR/slash-web"
API_DIR="$BASE_DIR/slash-api"
AGENT_DIR="$BASE_DIR/slash-agent/contract-agent"

LOG_DIR="$(mktemp -d /tmp/echo-test-logs.XXXXXX)"
PIDS=()

log() { printf '\n\033[1;36m[echo-test]\033[0m %s\n' "$1"; }
fail() { printf '\n\033[1;31m[echo-test 실패]\033[0m %s\n' "$1" >&2; exit 1; }

cleanup() {
  log "종료 중 — 백그라운드 프로세스 정리"
  for pid in "${PIDS[@]:-}"; do
    kill "$pid" >/dev/null 2>&1 || true
  done
}
trap cleanup EXIT INT TERM

# 0. 사전 점검
[ -d "$WEB_DIR" ] || fail "slash-web 저장소를 찾을 수 없습니다: $WEB_DIR"
[ -d "$API_DIR" ] || fail "slash-api 저장소를 찾을 수 없습니다: $API_DIR"
[ -d "$AGENT_DIR" ] || fail "slash-agent/contract-agent를 찾을 수 없습니다: $AGENT_DIR"

for dir in "$WEB_DIR" "$API_DIR" "$AGENT_DIR"; do
  branch="$(git -C "$dir" branch --show-current)"
  case "$branch" in
    *-test) ;;
    *) log "경고: $dir 이 -test 브랜치가 아닙니다 (현재: $branch)" ;;
  esac
done

# 1. 의존성 설치 (node_modules 없을 때만)
log "의존성 확인 중..."
[ -d "$API_DIR/node_modules" ] || (cd "$API_DIR" && npm install)
[ -d "$AGENT_DIR/node_modules" ] || (cd "$AGENT_DIR" && npm install)
[ -d "$WEB_DIR/node_modules" ] || (cd "$WEB_DIR" && npm install)

# 2. mock-api 실행
log "mock-api 실행 중 (포트 4000)..."
(cd "$API_DIR" && npm run start) > "$LOG_DIR/mock-api.log" 2>&1 &
PIDS+=($!)

for i in $(seq 1 20); do
  grep -q "listening on :4000" "$LOG_DIR/mock-api.log" 2>/dev/null && break
  sleep 0.5
  [ "$i" -eq 20 ] && fail "mock-api가 10초 안에 기동하지 않았습니다. 로그: $LOG_DIR/mock-api.log"
done
log "mock-api 준비 완료"

# 3. 로컬 에이전트(contract-agent CLI) 실행
log "로컬 에이전트 실행 중..."
(cd "$AGENT_DIR" && npm run start) > "$LOG_DIR/agent.log" 2>&1 &
PIDS+=($!)

for i in $(seq 1 20); do
  grep -q "READY" "$LOG_DIR/agent.log" 2>/dev/null && break
  sleep 0.5
  [ "$i" -eq 20 ] && fail "에이전트가 10초 안에 READY 상태가 되지 않았습니다. 로그: $LOG_DIR/agent.log"
done
log "에이전트 준비 완료 (계정: contract-agent-tester@example.com)"

# 4. 웹 dev 서버 실행
log "웹 dev 서버 실행 중 (포트 5173)..."
(cd "$WEB_DIR" && npm run dev) > "$LOG_DIR/web.log" 2>&1 &
PIDS+=($!)

for i in $(seq 1 20); do
  grep -q "Local:" "$LOG_DIR/web.log" 2>/dev/null && break
  sleep 0.5
  [ "$i" -eq 20 ] && fail "웹 서버가 10초 안에 기동하지 않았습니다. 로그: $LOG_DIR/web.log"
done
log "웹 서버 준비 완료"

# 5. 브라우저 자동으로 열기
URL="http://localhost:5173/dev/echo-test"
log "브라우저에서 $URL 여는 중..."
open "$URL" 2>/dev/null || true

cat <<EOF

--------------------------------------------------------------
모든 서비스가 준비됐습니다. 로그는 $LOG_DIR 에 있습니다.

$URL 에서 "시험 로그인 이메일"을 contract-agent-tester@example.com
으로 바꾸고 "보내기"를 눌러 테스트하세요.

이 창을 Ctrl+C로 종료하면 mock-api / 에이전트 / 웹 서버가 전부 정리됩니다.
--------------------------------------------------------------
EOF

wait
