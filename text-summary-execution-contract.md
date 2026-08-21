# `TEXT_SUMMARY` 실행 경로 계약

`/summary`(`TEXT_SUMMARY`)가 브라우저·PC·서버 세 곳 중 어디서 실행되는지, 그
실행 위치별 결과가 어떤 모양인지에 대한 계약입니다. `slash-web`·`slash-api`·
`slash-nlu`·`slash-runner` 네 저장소가 같이 합의해야 하는 내용이라 여기(공통
문서)에 둡니다 — 지금까지는 `slash-api`의 `docs/frontend-api-contract.md`에만
있었는데, 그쪽은 slash-api 자신의 REST 계약서라 다른 저장소가 참조하기엔
위치가 맞지 않았습니다.

배경 결정은 [`slash-docs#3`](https://github.com/LikeLionTeam4/slash-docs/issues/3)
(마스터 이슈)을 따릅니다 — 여기 있는 건 그 이슈가 확정한 계약을 실무에서 바로
참조할 수 있게 정리한 것이고, 원칙 자체가 바뀌면 이슈가 먼저입니다.

## 실행 위치 세 가지

| `executionTarget` | 담당 | 조건 |
|---|---|---|
| `BROWSER` | `slash-web`의 WebLLM | 브라우저가 WebGPU를 지원하고 사용자가 브라우저 실행을 선택(또는 자동)한 경우 |
| `RUNNER` | `slash-runner`와 Claude Code/Codex 어댑터 | 사용자가 PC를 선택했고 그 PC가 `device_capabilities`에 `TEXT_SUMMARY`를 보고한 경우 |
| `BACKEND` | `slash-nlu`의 CPU 추출 요약(TF-IDF) | 위 둘 다 아니면 항상 이쪽 — 조건 없는 기본 경로 |

우선순위는 **브라우저(WebGPU) > 선택한 PC(능력 보고 시) > 서버 추출 요약(기본)**
순이고, 앞 조건이 만족되면 뒤 조건은 안 봅니다. `processingRoute`(유형에서
파생되는 옛 값)와는 별개 필드입니다 — 어디서 실행할지 정하는 게 `processingRoute`가
아니라 `executionTarget`입니다.

### `BROWSER`는 서버가 결정하지 않습니다

다른 두 경로(`RUNNER`·`BACKEND`)는 `slash-api`의 `TaskService.resolveExecutionTarget()`가
서버 쪽에서 결정하지만, `BROWSER`는 다릅니다 — **브라우저가 `isWebGpuSupported()`로
스스로 판단해서 그 자리에서 처리**하고, 서버는 이미 끝난 결과만 접수합니다(아래
접수 경로 참고). 서버의 `resolveExecutionTarget()`가 `BROWSER` 케이스를 만나면
아직 예외를 던집니다 — 이 계약이 "서버가 조합해서 결정한다"는 문구로 다시
정리되기 전까지는 의도된 동작입니다.

## 접수 경로 두 가지

### 1) 일반 접수 — `RUNNER`·`BACKEND`

```
POST /api/v1/requests → 202 (또는 곧바로 SUCCEEDED)
{ "text": "/summary 요약할 긴 글", "selectedDeviceId": "…"(선택) }
```

일반 작업 접수와 같은 경로입니다. `selectedDeviceId`를 보냈고 그 PC가 능력을
보고했으면 `RUNNER`, 아니면 조용히 `BACKEND`로 넘어갑니다(실패로 보이지 않음).
CPU 추출 요약은 수십 밀리초에 끝나 접수 응답이 곧바로 `SUCCEEDED`로 올 수
있습니다 — `status`를 고정값으로 가정하지 말고 그대로 읽어야 합니다.

### 2) 브라우저 결과 제출 — `BROWSER`

```
POST /api/v1/tasks/text-summary/browser-result → 200
Idempotency-Key: {UUID v4}   ← 필수, 없으면 400
{ "inputLength": 1200, "modelId": "Qwen2.5-1.5B-Instruct-q4f16_1-MLC",
  "promptVersion": "v1", "status": "SUCCEEDED",
  "summary": "…", "durationMs": 2400 }
```

- **원문(`text`) 자체는 이 요청에 없습니다.** `inputLength`(글자 수)만 보냅니다 —
  "명시적인 브라우저 요약은 원문을 브라우저에 유지한다"는 원칙 그대로입니다.
- 이미 실행이 끝난 걸 기록하는 것이라 `202`가 아니라 `200`, 응답 시점에 이미
  최종 상태(`SUCCEEDED`/`FAILED`)입니다 — 폴링할 게 없습니다.
- `Idempotency-Key`가 **필수**입니다. 일반 접수와 달리, 여기서 재전송은 "같은
  작업 재조회"가 아니라 "새 이력을 또 만드는 것"으로 이어지므로 요약 1회당
  키 하나만 써야 합니다.
- `status`가 `FAILED`면 `summary` 대신 `errorMessage`(선택)를 보냅니다.
  `SUCCEEDED`인데 `summary`가 없으면 `VALIDATION_ERROR`(400)로 거부됩니다.

## 결과 스키마 — 네 가지, `summary` 필드만 공통

화면은 `summary`만 그리면 됩니다. 나머지는 "무엇으로 요약했는지"를 남긴
값이라 이력·조사용입니다.

**CPU 추출 요약**(`BACKEND`, 지금 기본값)
```json
{ "summary": "…", "engine": "EXTRACTIVE", "algorithm": "TFIDF_CENTROID",
  "algorithmVersion": "1", "inputSentenceCount": 8, "outputSentenceCount": 3,
  "durationMs": 16 }
```

**GPU 모델(Gemma)**(`BACKEND`, 과거 이력에만 남음 — 신규 유입 중단됨)
```json
{ "summary": "…", "model": "gemma3:4b" }
```

**PC 실행기**(`RUNNER`, Claude Code/Codex)
```json
{ "summaryAdapter": "CLAUDE_CODE", "summary": "…",
  "durationMs": 1820, "collectedAt": "2026-08-21T20:30:00+09:00" }
```

**브라우저 WebLLM**(`BROWSER`)
```json
{ "summary": "…", "modelId": "Qwen2.5-1.5B-Instruct-q4f16_1-MLC",
  "promptVersion": "v1", "durationMs": 2400 }
```

네 결과의 `executionTarget`은 서로 다릅니다 — CPU·GPU는 `BACKEND`, PC 실행기는
`RUNNER`, 브라우저 WebLLM은 `BROWSER`. 어디서 실행했는지는 `executionTarget`으로,
무엇으로 했는지는 결과 안의 `engine`/`model`/`summaryAdapter`/`modelId`로
가릅니다.

## 오류 코드

| code | HTTP | 뜻 |
|---|---|---|
| `BROWSER_TASK_FAILED` | 422 | 브라우저가 스스로 실패를 보고함(`AGENT_TASK_FAILED`와 같은 자리 — 실행 주체가 브라우저일 뿐) |
| `VALIDATION_ERROR` | 400 | `SUCCEEDED`인데 `summary` 없음, `Idempotency-Key` 누락 등 |
| `LLM_NOT_READY` | 503 | GPU 경로 한정, 모델이 밀렸을 때 |
| `UPSTREAM_UNAVAILABLE` | 503 | CPU 추출 요약 서비스(`slash-nlu`)에 닿지 못함 |

## 아직 계약으로 정리되지 않은 것

- `slash-web`이 `BROWSER`/`RUNNER`/`BACKEND`/`AUTO`를 사용자가 직접 고르는 UI는
  없습니다 — 지금은 WebGPU 지원 여부로 자동 분기합니다.
- 브라우저 결과를 대화 이력에 남길지 여부의 사용자 선택 UX(`slash-docs#3`
  "구현 전 결정 사항")는 아직 없습니다 — 지금은 항상 남깁니다.
- WebLLM 미지원 시 사용자가 다른 경로를 직접 선택하는 UI는 없습니다 — 서버
  경로로 조용히 넘어갑니다(새로 생긴 동작은 아님, 원래도 서버로 가던 경로).

최신 진행 상태는 [`slash-docs#3`](https://github.com/LikeLionTeam4/slash-docs/issues/3)의
체크리스트를 참고하세요.
