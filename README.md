# SIP / VoIP Lab on Kubernetes

A carrier-style voice platform you can run on a laptop. **Kamailio** is the SIP edge proxy: it classifies calls by destination, load-balances them across a pool of **Asterisk** media servers, fails over when one breaks, and blocks floods. **SIPp** generates realistic call traffic. **Prometheus and Grafana** track the KPIs voice teams live by: ASR, NER, ACD and PDD. Everything runs on **Docker Compose** or **Kubernetes**.

![Kamailio](https://img.shields.io/badge/Kamailio-5.7-00A0DF)
![Asterisk](https://img.shields.io/badge/Asterisk-20-F68F1E?logo=asterisk&logoColor=white)
![SIPp](https://img.shields.io/badge/SIPp-load%20testing-6E6E6E)
![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?logo=kubernetes&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-2496ED?logo=docker&logoColor=white)
![Prometheus](https://img.shields.io/badge/Prometheus-E6522C?logo=prometheus&logoColor=white)
![Grafana](https://img.shields.io/badge/Grafana-F46800?logo=grafana&logoColor=white)

## Architecture

```
                         SIP (UDP 5060)
 SIPp / softphone ───────────────────────► Kamailio  (edge proxy, 2 replicas on Kubernetes)
                                            │ • trusted networks only, pike flood protection
                                            │ • classify by prefix: uk, france, lebanon-mobile…
                                            │ • dispatcher: round robin + OPTIONS health checks
                                            │ • failover on 5xx / timeout to the next server
                                            │ • KPIs → /metrics (attempts, codes, PDD, duration)
                                  ┌─────────┴─────────┐
                                  ▼                   ▼
                             Asterisk 0          Asterisk 1     (StatefulSet, graceful drain)
                             echo test 600 · IVR 700 · carrier simulator for E.164 numbers
                             (per-country answer rate, busy, no answer, wrong number, PDD)

 Prometheus ◄── scrapes Kamailio + Asterisk ──► recording rules (ASR/NER/ACD/PDD) → alerts → Grafana
```

## What it demonstrates

| Topic | How |
|---|---|
| **SIP routing** | Prefix classification, Record-Route, in-dialog routing, CANCEL handling, dialog tracking |
| **High availability** | Asterisk pool behind Kamailio's dispatcher, OPTIONS health checks, failover on 500/502/503 or timeout, DNS re-resolution of restarted pods |
| **Zero-downtime maintenance** | Asterisk drains gracefully (preStop hook / `rolling-restart.sh`): no new calls, waits for active ones, then exits |
| **Security** | Calls accepted only from trusted networks, `pike` drops floods from other sources, non-root containers |
| **Telecom KPIs** | ASR, NER, ACD and PDD per destination, from Kamailio counters and histograms |
| **Load testing** | SIPp scenario dialing 500 numbers across 7 destinations. Busy, no-answer and wrong-number outcomes are expected, infrastructure errors are not |
| **CI/CD** | GitHub Actions builds the images, runs calls on Docker Compose (load, rolling restart, crash) and on a real **kind** Kubernetes cluster, then publishes to GHCR |

## Quick start (Docker Compose)

```bash
git clone https://github.com/TouficMad/sip-voip-lab.git
cd sip-voip-lab
docker compose up -d --build --wait

docker compose run --rm sipp                              # 300 calls at 10 calls/s
docker compose run --rm -e RATE=50 -e CALLS=3000 sipp      # push harder
```

| Service | URL |
|---|---|
| Grafana (admin / admin): **VoIP Lab** dashboard | http://localhost:3000 |
| Prometheus | http://localhost:9091 |
| Alertmanager | http://localhost:9093 |
| Kamailio metrics | http://localhost:9090/metrics |
| Asterisk metrics | http://localhost:8088/metrics, http://localhost:8089/metrics |

### Resilience experiments

```bash
# Zero-downtime maintenance: restart both Asterisk servers during a load test
docker compose run --rm -e RATE=20 -e CALLS=600 sipp &
./scripts/rolling-restart.sh           # result: 600/600 calls succeed

# Chaos: kill asterisk-1 without warning during a load test
./scripts/crash-test.sh
```

In the crash test, calls that were already connected to asterisk-1 are lost, because a crashed media server takes its calls with it. Every new call is failed over to asterisk-2. That difference is why the rolling restart drains servers first.

### Call it from a softphone

Point a SIP softphone (Linphone, Zoiper, MicroSIP) at `localhost:5060` over UDP, with no registration, and dial:
- `600`: echo test, so you hear yourself
- `700`: demo IVR prompt
- any international number such as `447700900123`: the carrier simulator rings, answers, or returns busy

Audio works when the containers are reachable from your machine (Linux). Kamailio relays signalling only; adding **rtpengine** for media relay is on the roadmap.

## Kubernetes

```bash
kind create cluster --name voip-lab --config kind-config.yaml
kubectl apply -k .            # images from ghcr.io/touficmad/voip-lab-*
kubectl -n voip-lab get pods

# load test as a Kubernetes Job
kubectl -n voip-lab create job --from=cronjob/sipp-load-test sipp-$(date +%s)
kubectl -n voip-lab logs -f job/sipp-<id>
```

| Resource | Details |
|---|---|
| `asterisk` StatefulSet | 2 pods with stable DNS (`asterisk-0.asterisk…`), preStop graceful drain, 300 s grace period |
| `kamailio` Deployment | 2 replicas. Record-Route carries the pod IP, so each call sticks to one proxy. The init container waits for Asterisk DNS |
| `kamailio` Service | NodePort 30060/UDP (kind maps it to `localhost:5060`) |
| Prometheus + Grafana | Pod discovery via annotations, Grafana on `localhost:3000` |
| `sipp-load-test` CronJob | Suspended template: create a Job from it on demand |

## KPIs

| KPI | Meaning | Source |
|---|---|---|
| **ASR** | Answered / attempted calls | `kamailio_sip_call_final_total{code="200"}` |
| **NER** | Calls the network completed (answered, busy, no answer, wrong number) | `kamailio_sip_call_final_total` |
| **ACD** | Average call duration | `kamailio_sip_call_duration_seconds_total / kamailio_sip_calls_ended_total` |
| **PDD** | INVITE → first ringing (p95) | `kamailio_sip_pdd_seconds` histogram |

Simulated carrier profiles (configured in [`extensions.conf`](asterisk/config/extensions.conf)) and what the lab measured in a 1,500-call run:

| Destination | Configured answer rate | Measured ASR | Max PDD | Measured PDD p95 |
|---|---|---|---|---|
| UK | 65% | 66% | 2 s | 2.9 s |
| France | 60% | 58% | 2 s | 2.9 s |
| Lebanon mobile | 55% | 53% | 3 s | 4.6 s |
| Lebanon | 50% | 52% | 3 s | 4.5 s |
| UAE | 45% | 47% | 4 s | 4.8 s |

### Alerts

`VoipMediaServerDown` · `VoipEdgeProxyDown` · `VoipNoMediaServerAvailable` · `VoipFailovers` · `VoipLowASR` · `VoipHighPDD` · `VoipSipFlood`. Unit tests live in [`monitoring/prometheus/tests`](monitoring/prometheus/tests).

## Repository layout

```
kamailio/          kamailio.cfg (routing, dispatcher, pike, metrics), Dockerfile
asterisk/config/   pjsip, dialplan (echo, IVR, carrier simulator), Prometheus, minimal modules
sipp/              uac.xml scenario, 500 test numbers, load-test runner
monitoring/        Prometheus (compose + k8s), rules + tests, Alertmanager, Grafana dashboard
k8s/               namespace, Asterisk StatefulSet, Kamailio, Prometheus/Grafana, SIPp job
scripts/           rolling-restart.sh, crash-test.sh
kustomization.yaml, kind-config.yaml, docker-compose.yml
```

## Roadmap

- [ ] rtpengine for media relay and NAT traversal
- [ ] TLS/SRTP and digest authentication for softphones
- [ ] Least-cost routing between several carriers with Kamailio `drouting`
- [ ] CDR export to the [VoIP Routing Monitor](https://github.com/TouficMad/voip-routing-monitor)
