> ⚠️ **이 문서는 통신 테스트 참고용 문서이다.** `slash-web-test` / `slash-api-test` / `slash-agent-test`라는
> 임시 검증용 브랜치(각 저장소의 `dev`에 머지되지 않음)에서, 프론트→백엔드→로컬 에이전트 종단 통신이
> 되는지만 확인하기 위해 만든 `COMMAND`라는 임시 TaskType의 흐름을 기록한 것이다. `COMMAND`는 확정된
> 6종 TaskType(`WEATHER_LOOKUP`/`FILE_SEARCH`/`SYSTEM_STATUS`/`TEXT_SUMMARY`/`CODE_ANALYSIS`/`AI_AGENT_USAGE`)에
> 포함되지 않으며, 실제 API 명세서·메시지 명세와 무관하다. Agent WSS 메시지 순서·재전송 규칙 자체는
> 실제 계약과 동일하므로 프로토콜 이해용 참고 자료로만 사용한다.

# "hello slash" COMMAND 명령 테스트 — 이벤트 타임라인 14단계 상세

> `slash-web-test` / `slash-api-test` / `slash-agent-test` 세 브랜치를 붙여서 실제 검증했을 때 나온 14개 이벤트를,
> 실제 코드(`mock-api/src/taskOrchestrator.ts`, `mock-api/src/agentWss.ts`, `contract-agent/src/agent.ts`, `contracts/src/agentMessages.ts`) 기준으로
> "컴포넌트별 송수신 메시지 형태" 정리한 문서이다.

## 테스트 조건

- mock-api(`slash-api-test`, 포트 4000) + contract-agent(`slash-agent-test`) + slash-web(`slash-web-test`, `/dev/echo-test`)
- 입력: `/command hello slash!!!!`
- 실제 확인된 값: `taskId=f27fbc84-6768-4936-804f-47696812d224`, `deviceId=bdb54ed1-89b6-4725-923d-560c43abccbc`, `correlationId=29c3ed40-251f-44b0-a279-19c3d7d5a3c3`

## 통신 종류 요약

- **HTTP(요청↔응답 1:1)**: 1번, 14번 — web ↔ mock-api
- **WebSocket(양방향, 자유 발신)**: 6·8·10·11·13번 — mock-api ↔ contract-agent
- **내부 처리(통신 없음)**: 2·4·5·7·9·12번 — mock-api 프로세스 안에서만 일어남
- **인프로세스 함수 호출**: 3번 — mock-api가 mock-nlu 코드를 같은 프로세스 안에서 직접 호출(별도 서버 아님)

---

### 1. `REQUEST_CREATED`
web(브라우저) → mock-api : `POST /api/v1/requests`
```json
{ "text": "/command hello slash!!!!", "selectedDeviceId": "bdb54ed1-89b6-4725-923d-560c43abccbc" }
```
mock-api → web : 접수 응답(즉시, 아직 처리 전 — "접수증"에 해당)
```json
{ "data": { "taskId": "f27fbc84-6768-4936-804f-47696812d224", "status": "ANALYZING", "statusUrl": "/api/v1/tasks/f27fbc84-..." } }
```
**요청을 받은 mock-api가 하는 일**: `restRouter.ts`의 핸들러가 `text`·`selectedDeviceId`를 받아 `taskId`(UUID)를 새로 발급하고 `store.tasks`에 `status:"CREATED"` 레코드를 즉시 생성한다. 그 다음 바로 `taskOrchestrator`를 호출해 2번(ANALYZING 전이)을 진행한다. **응답을 받은 web이 하는 일**: `EchoTestPage.tsx`가 응답의 `taskId`를 변수에 저장하고, 이후 14번 폴링에서 이 값을 URL에 그대로 사용한다.

### 2. `ANALYZING` — mock-api 내부, 통신 없음
`task.status`를 `CREATED → ANALYZING`으로 전이(`store.ts` 메모리 갱신). **수행하는 일**: 상태만 바꾸고 바로 3번(NLU 분석)을 호출 — 사용자에게 별도로 알리지 않는 내부 준비 단계.

### 3. `NLU_RESULT`
mock-api → mock-nlu : 함수 `analyze("/command hello slash!!!!")` 직접 호출(같은 프로세스, 네트워크 아님)
mock-nlu → mock-api : 반환값
```json
{ "taskType": "COMMAND", "parameters": { "command": "hello slash!!!!" }, "confidence": 1.0, "missingRequiredParameters": [] }
```
**호출을 받은 mock-nlu가 하는 일**: 정규식(`/^\/(\S+)\s*(.*)$/s`)으로 `/command`와 나머지 텍스트를 분리하고, `SLASH_COMMAND_TASK_TYPE` 표에서 `command`→`COMMAND`를 찾은 뒤 `parameters.command`에 나머지 문자열을 담아 반환한다. **결과를 받은 mock-api가 하는 일**: `missingRequiredParameters`가 비어있는지 확인 — 비어있지 않으면 `NEEDS_CLARIFICATION`으로 빠지고, 비어있으면 4번(라우팅 결정)으로 진행한다.

### 4. `PROCESSING_ROUTE_DECIDED` — mock-api 내부, 통신 없음
`TASK_TYPE_ROUTE["COMMAND"]` 테이블 조회 결과 `"LOCAL_AGENT"` 기록. **수행하는 일**: 이 값에 따라 다음에 실행할 함수를 분기한다 — `LOCAL_AGENT`면 5번(에이전트 큐잉), `LLM_SERVICE`면 mock-llm 위임, `BACKEND_SERVICE`면 외부 API(날씨 등) 즉시 호출. 이번 케이스는 `LOCAL_AGENT`라 5번을 진행한다.

### 5. `QUEUED` — mock-api 내부, 통신 없음
`agentDispatches`에 새 dispatch 레코드 생성, 전송 준비. **수행하는 일**: `dispatchId`를 새로 발급하고 `taskId`와 묶어서 `store.agentDispatches`에 저장한 뒤, 대상 기기(`selectedDeviceId`)가 실제로 WebSocket에 연결돼 있는지 확인하고 6번을 진행한다.

### 6. `TASK_DISPATCHED`
mock-api → contract-agent : WebSocket `/ws/agent`로 `TASK` 메시지 전송
```json
{
  "type": "TASK",
  "schemaVersion": "1.0",
  "eventId": "<uuid>",
  "sentAt": "2026-08-05T21:35:02...+09:00",
  "taskId": "f27fbc84-6768-4936-804f-47696812d224",
  "dispatchId": "<uuid>",
  "correlationId": "29c3ed40-251f-44b0-a279-19c3d7d5a3c3",
  "taskType": "COMMAND",
  "parameters": { "command": "hello slash!!!!" },
  "expiresAt": "<TASK 만료 시각>",
  "payloadSha256": "<taskId+dispatchId+taskType+parameters를 SHA-256 해싱한 64자리 hex, 정규화 알고리즘 미확정이라 존재/형식만 검증>"
}
```
**전송한 mock-api가 하는 일**: 메시지를 보낸 직후 5초짜리 ACK 타이머(`setTimeout`)를 걸어둔다 — 이 시간 안에 8번(ACK)이 오지 않으면 같은 `dispatchId`로 1회 재전송하고, 그래도 오지 않으면 `EXPIRED`로 처리한다. **수신한 contract-agent가 하는 일**: zod 스키마로 메시지 형태를 검증하고, `taskId:dispatchId` 키로 이미 처리한 적 있는 요청인지(중복) 확인한 뒤, `SUPPORTED_TASK_TYPES`에 `COMMAND`가 있는지·`parameters.command`가 비어있지 않은 문자열인지(`validateTask()`) 검사한다. 문제없으면 7번을 진행한다.

### 7. `TASK_RECEIVED` — 통신 없음
contract-agent가 6번 메시지를 실제로 받았다는 걸 mock-api가 기록한 로그(6번 수신 확인용). **수행하는 일**: 에이전트 쪽에서는 이 시점에 8번(ACK) 전송을 준비 — validateTask() 결과가 `null`(문제없음)이면 `accepted:true`로, 에러 코드가 있으면 `accepted:false`+`reasonCode`로 ACK 내용을 결정한다.

### 8. `ACK_ACCEPTED`
contract-agent → mock-api : WebSocket으로 `ACK` 메시지 전송
```json
{
  "type": "ACK",
  "taskId": "f27fbc84-...",
  "dispatchId": "<6번과 동일>",
  "correlationId": "29c3ed40-...",
  "accepted": true,
  "reasonCode": null,
  "acknowledgedAt": "..."
}
```
**전송한 contract-agent가 하는 일**: ACK를 보낸 직후 실제 `executeTask()`를 실행한다. — COMMAND의 경우 받은 `command` 문자열을 셸에서 실행하지 않고 그대로 결과로 만들 준비를 한다(자세한 내용은 아래 "참고: COMMAND는 실제 명령을 실행하지 않는다" 참조, 10번·11번을 진행한다). **수신한 mock-api가 하는 일**: 6번에서 걸어둔 5초 ACK 타이머를 즉시 취소하고(`clearTimeout`), `accepted:true`를 확인한 뒤 9번(RUNNING 전이)을 진행한다. 만약 `accepted:false`값이면 `FAILED`로 종료된다.

### 9. `RUNNING` — mock-api 내부, 통신 없음
8번의 `accepted:true` 확인 후 `task.status`를 `RUNNING`으로 전이. **수행하는 일**: 상태 전이 후 사용자 WSS(`userWss.ts`)로 "작업이 실행 중"이라는 알림을 브로드캐스트할 수 있는 지점(이번 echo-test 페이지는 폴링 방식이라 이 알림을 실제로 소비하지 않는다).

### 10. `PROGRESS`
contract-agent → mock-api : WebSocket으로 `PROGRESS` 메시지 전송
```json
{ "type": "PROGRESS", "taskId": "f27fbc84-...", "dispatchId": "<동일>", "correlationId": "29c3ed40-...", "stage": "EXECUTING", "percent": 50 }
```
**전송한 contract-agent가 하는 일**: `executeTask()`가 실제로 도는 도중 진행률을 알리는 용도 — COMMAND 명령 처리는 즉시 끝나는 작업이라 이 메시지는 형식상 한 번만 보내고 바로 11번을 진행한다(오래 걸리는 작업이면 여러 번 보낼 수 있음). **수신한 mock-api가 하는 일**: 상태 전이 없이 로그만 남긴다(`logOnly`) — Task 상태 자체는 그대로 `RUNNING` 유지.

### 11. `RESULT`
contract-agent → mock-api : WebSocket으로 `RESULT` 메시지 전송 — 실제 처리 결과가 처음 만들어지는 지점
```json
{
  "type": "RESULT",
  "taskId": "f27fbc84-...",
  "dispatchId": "<동일>",
  "correlationId": "29c3ed40-...",
  "status": "SUCCEEDED",
  "result": { "output": "hello slash!!!!", "executedAt": "2026-08-05T21:35:02.997+09:00" },
  "error": null,
  "startedAt": "...",
  "finishedAt": "2026-08-05T21:35:02.997+09:00"
}
```
**전송한 contract-agent가 하는 일**: `executeTask()`가 입력받은 `command` 문자열을 아무 가공 없이 그대로 `{output: command, executedAt: nowIsoKst()}`로 반환하면 그걸 RESULT 메시지에 담아 보내고, 동시에 이 결과를 `resultCache`(메모리)에 `acked:false` 상태로 저장한다. — 13번(RESULT_ACK)이 올 때까지 재연결 시 재전송할 수 있도록 대비 **수신한 mock-api가 하는 일**: `dispatch.status`를 `COMPLETED`로, `task.result`에 결과를 저장하고 12번(RESULT_PERSISTED)을 진행한다.

### 12. `RESULT_PERSISTED` — mock-api 내부, 통신 없음
11번의 `result`를 `task.result`에 저장, `task.status`를 `SUCCEEDED`로 전이(메모리 저장소 갱신). **수행하는 일**: 저장이 끝나면 곧바로 13번(RESULT_ACK 전송)을 준비하고, 동시에 `notifyResultAvailable()`로 사용자 WSS에도 완료를 알린다(이 echo-test는 폴링 방식이라 이 알림을 실제로 사용하지 않는다).

### 13. `RESULT_ACK_SENT`
mock-api → contract-agent : WebSocket으로 `RESULT_ACK` 메시지 전송(11번 RESULT 수신·저장 확인, 재전송 방지용)
```json
{ "type": "RESULT_ACK", "taskId": "f27fbc84-...", "dispatchId": "<동일>", "correlationId": "29c3ed40-...", "persisted": true, "taskStatus": "SUCCEEDED" }
```
**수신한 contract-agent가 하는 일**: 11번에서 `resultCache`에 저장해뒀던 항목을 찾아 `acked:true`로 표시한다(`case "RESULT_ACK"` 핸들러, `contract-agent/src/agent.ts:273`). 이렇게 표시된 결과는 재연결 시 `resendUnackedResults()`가 다시 보내지 않는다 — 즉 이 메시지 하나로 "결과 재전송 의무"가 해제된다.

### 14. `SUCCEEDED`
web(브라우저) → mock-api : `GET /api/v1/tasks/f27fbc84-...` (0.2초 간격, 최대 25회 폴링)
mock-api → web : 최종 결과 응답 — **화면 "Task 결과" 박스에 표시되는 것**
```json
{
  "data": {
    "taskId": "f27fbc84-6768-4936-804f-47696812d224",
    "status": "SUCCEEDED",
    "taskType": "COMMAND",
    "processingRoute": "LOCAL_AGENT",
    "result": { "output": "hello slash!!!!", "executedAt": "..." },
    "errorCode": null
  }
}
```
**응답을 받은 web이 하는 일**: `EchoTestPage.tsx`의 폴링 루프가 `status === 'SUCCEEDED' || status === 'FAILED'` 조건을 확인하고 참이면 루프를 멈춘다. 그 다음 `GET /api/v1/tasks/{taskId}/events`를 한 번 더 호출해 1~14번 이벤트 전체 이력을 받아오고, `setTask()`·`setEvents()`로 React 상태를 갱신해 화면에 "Task 결과"와 "이벤트 타임라인"을 렌더링한다.

---

## 참고: COMMAND는 실제 명령을 실행하지 않는다

`contract-agent/src/agent.ts`의 `executeTask()`에서 COMMAND를 처리하는 부분은 다음과 같다.

```ts
if (message.taskType === "COMMAND") {
  // 백그라운드 명령 실행의 최소 구현 — 지금은 받은 명령을 그대로 에코한다.
  const command = String(message.parameters.command ?? "");
  return { ok: true, result: { output: command, executedAt: nowIsoKst() } };
}
```

`child_process.exec()`나 `spawn()` 같은 셸 실행 코드는 없다. 받은 `command` 문자열을 아무 처리 없이 그대로 `output`에 담아 되돌려주는 순수 문자열 반사(mirror)일 뿐이며, 실제 OS 명령을 실행하는 기능이 아니다. 따라서 이 테스트가 검증하는 것은 "`hello slash!!!!`라는 명령이 실제로 실행됐다"가 아니라, **"프론트 → 백엔드 → WebSocket → 로컬 에이전트까지 데이터가 왜곡 없이 왕복했다"**는 사실이다.

실제 명령 실행 기능을 추가하려면 이 부분에 셸 실행 로직을 새로 구현해야 하며, 임의 명령 실행은 샌드박싱·화이트리스트 등 별도의 보안 검토가 반드시 필요한 기능이므로 이번 검증 범위에 포함되지 않는다.