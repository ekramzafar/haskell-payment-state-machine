 # PaySwitch



A Haskell-based payment orchestration and smart routing engine inspired by modern payment infrastructure such as Juspay HyperSwitch.



PaySwitch provides a unified payment API over multiple payment gateways, with intelligent routing, retries, idempotency, webhooks, reconciliation, background processing, monitoring, and an operations dashboard.



## Architecture



```text

                    ┌─────────────────────┐

                    │   Admin Dashboard    │

                    │   React + TypeScript │

                    └──────────┬──────────┘

                               │ REST

                               ▼

                    ┌─────────────────────┐

                    │    PaySwitch API    │

                    │       Haskell       │

                    └──────────┬──────────┘

                               │

                    ┌──────────▼──────────┐

                    │   Payment Service   │

                    └──────────┬──────────┘

                               │

                    ┌──────────▼──────────┐

                    │   Smart Router      │

                    │ priority + health   │

                    │ retry + failover    │

                    └───────┬───────┬─────┘

                            │       │

                   ┌────────▼─┐   ┌─▼────────┐

                   │  Stripe  │   │   Mock   │

                   │ Gateway  │   │ Gateways │

                   └──────────┘   └──────────┘



             ┌──────────────────────────────┐

             │ PostgreSQL │ Redis │ Worker  │

             └──────────────────────────────┘

```



 ---



 ## Key Features



 ### Payment Processing



 - Create payments through a unified REST API

 - Payment state machine with controlled transitions

 - Capture and refund operations

 - Payment attempt tracking

 - Persistent payment event history



 ### Smart Gateway Routing



 - Gateway abstraction layer

 - Multiple gateway candidates

 - Priority-based routing

 - Gateway health awareness

 - Automatic failover

 - Retryable vs non-retryable error classification



 ### Reliability



 - Idempotency-Key support

 - Duplicate payment protection

 - Retry and failover handling

 - Background reconciliation worker

 - Gateway health tracking



 ### Webhooks



 - Gateway webhook processing

 - Duplicate webhook detection

 - Out-of-order state transition protection

 - Webhook event persistence



 ### Reconciliation



 - Compare internal payment state with gateway state

 - Detect MATCH / MISMATCH conditions

 - Persist reconciliation records

 - Support synchronous and asynchronous reconciliation



 ### Infrastructure



 - PostgreSQL persistence

 - Redis job queue

 - Background worker

 - Dockerized deployment

 - Docker Compose environment

 - Health endpoint

 - Application metrics



 ### Operations Dashboard



 - React + TypeScript

 - Payment creation

 - Payment status visibility

 - Gateway health overview

 - Basic operational statistics

 - Backend health monitoring



 ---



 ## Tech Stack



 ### Backend



 - Haskell

 - GHC 9.10

 - Servant

 - PostgreSQL

 - postgresql-simple

 - Redis

 - hedis

 - HTTP client / Stripe API integration



 ### Frontend



 - React

 - TypeScript

 - Vite

 - CSS



 ### Infrastructure



 - Docker

 - Docker Compose

 - PostgreSQL 16

 - Redis 7



 ---



 ## API



 * *Base URL: * *



```text

http://localhost:8080

```



 ### Health



```

GET /v1/health

```



 ### Create Payment



```

POST /v1/payments

Idempotency-Key: <unique-key>

Content-Type: application/json

```



Example:



```json

{

  "amount": 10000,

  "currency": "INR",

  "paymentMethod": "card"

}

```



 ---



 ## Payment Lifecycle



```text

CREATED

   │

   ▼

PROCESSING

   ├──────────────► FAILED

   │

   ▼

SUCCESS

   │

   ▼

CAPTURED

   │

   ▼

REFUNDED

```



 ---



 ## Running with Docker



Make sure Docker Desktop is running.



From the project root:



```bash

docker compose up -d --build

```



Check containers:



```bash

docker compose ps

```



The services are exposed as:



| Service        | URL                     |

|----------------|--------------------------|

| PaySwitch API  | http://localhost:8080   |

| Frontend       | http://localhost:5173   |

| PostgreSQL     | localhost:5434           |

| Redis          | localhost:6380           |



Health check:



```bash

curl http://localhost:8080/v1/health

```



 ---



 ## Running the Dashboard



Open another terminal:



```bash

cd frontend

npm install

npm run dev

```



Then open:



```text

http://localhost:5173

```



 ---



 ## Example Payment Request



```bash

curl -X POST http://localhost:8080/v1/payments   

  -H "Content-Type: application/json"   

  -H "Idempotency-Key: demo-payment-001"   

  -d '{

    "amount": 10000,

    "currency": "INR",

    "paymentMethod": "card"

  }'

```



 ---



 ## Stripe Integration



PaySwitch includes a Stripe gateway implementation behind the common gateway abstraction.



Stripe test mode can be configured through the application's gateway configuration/environment.



The gateway sends PaymentIntent requests using Stripe's test API and maps gateway responses into PaySwitch's internal payment result model.



This allows the same payment orchestration flow to work with both external and mock gateways.



 ---



 ## Database



The system persists payment and reliability data in PostgreSQL.



Important tables include:



 - `payments`

 - `payment _attempts`

 - `payment _events`

 - `idempotency _keys`

 - `webhook _events`

 - `routing _rules`

 - `gateway _health`

 - `reconciliation _records`



 ---



 ## Project Structure



```text

PaySwitch/

├── app/

│   └── Main.hs

│

├── src/

│   ├── Domain/

│   │   └── Payment.hs

│   │

│   ├── Gateway/

│   │   ├── AppGateway.hs

│   │   └── StripeGateway.hs

│   │

│   ├── Monitoring/

│   │

│   ├── Repository/

│   │   ├── Database.hs

│   │   ├── PaymentRepository.hs

│   │   └── RedisRepository.hs

│   │

│   ├── Service/

│   │   └── PaymentService.hs

│   │

│   └── Worker/

│

├── test/

│   └── Spec.hs

│

├── frontend/

│   ├── src/

│   ├── package.json

│   └── vite.config.ts

│

├── Dockerfile

├── docker-compose.yml

├── .dockerignore

├── PaySwitch.cabal

├── CHANGELOG.md

└── LICENSE

```



 ---



 ## Testing



Run the Haskell test suite:



```bash

cabal test

```



The project also includes API-level regression coverage for payment flows, idempotency, gateway behaviour, and state transitions.



 ---



 ## Design Decisions



 ### Gateway Abstraction



Payment processing is separated from individual gateway implementations.



```text

PaymentService

      │

      ▼

PaymentRouter

      │

      ▼

Gateway Interface

   ┌──┴──────┐

   ▼         ▼

 Stripe     Mock

```



This makes adding another payment provider possible without changing the core payment flow.



 ### Idempotency



Clients provide an `Idempotency-Key` with payment creation requests.



The key is persisted and mapped to the generated payment ID. Repeating the same request returns the previously created payment instead of creating another payment.



 ### Retry and Failover



Gateway failures are classified into retryable and non-retryable categories.



For retryable failures, the router can move to another healthy gateway candidate.



This prevents temporary gateway failures from unnecessarily becoming permanent payment failures.



 ### State Machine



Payment state transitions are explicitly controlled rather than allowing arbitrary status updates.



This protects the payment lifecycle from invalid transitions and inconsistent state.



 ### Background Processing



Redis is used as a lightweight job queue.



Background workers process asynchronous reconciliation work without blocking the main API request path.



 ---



 ## Why PaySwitch?



Payment systems need more than simply calling a payment gateway.



A production-oriented orchestration layer must handle:



 - gateway selection

 - failures

 - retries

 - duplicate requests

 - asynchronous events

 - inconsistent gateway states

 - reconciliation

 - observability



PaySwitch demonstrates these backend engineering concerns in a single system built from scratch with Haskell.



 ---



 ## Future Extensions



Possible production-scale extensions include:



 - additional payment gateways

 - circuit breaker persistence

 - distributed locking

 - Kafka/event streaming

 - stronger authentication and authorization

 - OpenTelemetry tracing

 - Prometheus/Grafana integration

 - advanced rule-based routing

 - merchant-specific routing policies



 ---



 ## Author



 * *Ekram Zafar * *



Built as a backend engineering project focused on payment orchestration, reliability, distributed systems concepts, and production-oriented API design.

