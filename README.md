# Slash | 프로젝트 문서

Slash(/)는 자연어 질문과 `/` 슬래시 명령어를 한 입력창에서 처리하는 AI 비서 서비스입니다.
이 저장소는 **어느 한 저장소에도 속하지 않는 공통 문서** 파트를 담당합니다.

## 시스템 한눈에 보기

```
사용자 → slash-web → slash-api → slash-nlu (분류·CPU 추출 요약)
                         │
                         └─ 실행 위치 결정
                              ├─ RUNNER   → slash-runner (사용자 PC, Outbound WSS)
                              └─ BACKEND  → 외부 API 또는 slash-nlu

  ※ BROWSER → slash-web의 WebLLM. 서버 결정 경로에 없고 브라우저가 스스로 판단해
     처리한 뒤 결과만 제출한다(원문을 서버에 보내지 않기 위한 것).
```

**핵심 원칙** — 클라우드는 데이터 저장소가 아니라 실행 경로를 결정하고 이력을 관리하는
관제탑입니다. 파일 절대 경로·파일 내용·코드 원문은 사용자 PC를 벗어나지 않고 결과만
올라옵니다. 사용자 PC에는 인바운드 포트를 열지 않습니다.

### 명령 7종

| 명령 | 작업 유형 | 실행 위치 |
|---|---|---|
| `/weather` | `WEATHER_LOOKUP` | 서버(외부 API) |
| `/file` | `FILE_SEARCH` | PC |
| `/open` | `FILE_OPEN` | PC |
| `/status` | `SYSTEM_STATUS` | PC |
| `/summary` | `TEXT_SUMMARY` | 브라우저 · 서버 · PC 중 하나 |
| `/code` | `CODE_ANALYSIS` | PC |
| `/usage` | `AI_AGENT_USAGE` | PC |

작업 유형의 단일 기준은 `slash-api`의 `TaskType` 열거형입니다.

## 문서 경계

폴리레포라 문서가 흩어지기 쉽습니다. 아래 기준으로 위치를 정합니다.

**여기(slash-docs)에 둡니다**

- 전체 아키텍처 다이어그램 · 컴포넌트 간 데이터 흐름
- 서비스 간 API 계약 (`web ↔ api ↔ nlu ↔ runner`)
- ERD · 데이터 모델
- 회의록 · 일정 · 의사결정 기록
- 발표 자료

**각 저장소 README에 둡니다**

- 그 저장소의 실행 방법 · 환경변수 · 의존성
- 그 저장소의 디렉터리 구조 · 내부 설계

기준은 하나입니다. **두 개 이상의 저장소가 합의해야 하는 내용이면 여기, 한 저장소 안에서 끝나는 내용이면 그 저장소 README.** API 계약을 `slash-api`에만 두면 프론트·에이전트 담당이 보지 않고, 7곳에 복사하면 곧바로 어긋납니다.

## 문서 목록

| 문서 | 내용 |
|---|---|
| [`text-summary-execution-contract.md`](./text-summary-execution-contract.md) | `TEXT_SUMMARY`(`/summary`)가 브라우저·PC·서버 중 어디서 실행되는지와 실행 위치별 결과 스키마 — `web`·`api`·`nlu`·`runner` 공통 계약 |

## 관련 저장소

| 저장소 | 역할 |
|---|---|
| [slash-web](https://github.com/LikeLionTeam4/slash-web) | 웹 클라이언트 — React·Vite UI, S3/CloudFront 배포 |
| [slash-api](https://github.com/LikeLionTeam4/slash-api) | 코어 API — 인증, 작업 원장, 실행 위치 결정, WSS 게이트웨이 |
| [slash-nlu](https://github.com/LikeLionTeam4/slash-nlu) | 자연어 분석 — slash 명령 파싱, 규칙·Kiwi 의도 분류, 인자 추출, CPU 추출 요약 |
| [slash-llm](https://github.com/LikeLionTeam4/slash-llm) | LLM 서비스 — Gemma 추론. 2026-08-25 dev 배포 제거, 기능 동결 |
| [slash-runner](https://github.com/LikeLionTeam4/slash-runner) | PC 작업 실행기 — 파일 검색·위치 열기·상태 조회·로컬 CLI 실행. Python·PyInstaller |
| [slash-infra](https://github.com/LikeLionTeam4/slash-infra) | 인프라 — Terraform(AWS), Helm·ArgoCD 배포 |
| **slash-docs** (현재) | 프로젝트 문서 — 아키텍처, API 계약, ERD, 회의록 |

## 마스터 이슈

| 이슈 | 내용 |
|---|---|
| [#3](https://github.com/LikeLionTeam4/slash-docs/issues/3) | LLM 실행 구조 전환과 분산 처리 체계 구축 — 클라우드 GPU 제거, 요약 3분산, 로컬 CLI 보안 경계, 원문 저장 정책이 이 스레드에서 확정됐습니다 |

저장소 간 판단이 필요한 사안은 이 이슈에서 근거와 함께 합의합니다.
