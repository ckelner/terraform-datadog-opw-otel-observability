# Observability Pipelines and OTel monitoring

Datadog monitors and runbook notebooks for OpenTelemetry Collector to Observability Pipelines to BYOC log path, focused on backpressure and data loss.

> ## Unofficial
>
> At this time it is a personal project with a sole author, Chris Kelner (Datadog Employee).
>
> - Treat it as a starting point you own.
> - The thresholds will not be right for you. They are derived from a handful of comparable incidents. None of them were calibrated against your specific traffic. Expect to tune them.
> - The notebooks are opinionated. The triage order and the diagnostic charts reflect one reading of how these failure mode propagates. Yours may differ.
> - Provided as-is under Apache-2.0, with no warranty and no conditions of any kind. See [LICENSE](LICENSE).
>
> Because of the above, `start_monitors_muted` defaults to `true`. Run it muted, watch the signals against your own traffic, tune, and only then turn alerting on.
>
> The officially maintained BYOC module is [`terraform-datadog-byoc-observability`](https://github.com/DataDog/terraform-datadog-byoc-observability), and is not yet made public. Where the two overlap, prefer theirs. This module is built not to overlap it. When working with Datadog they may supply you with this private repository at your request until is is made public.

This module is a sibling of [`terraform-datadog-byoc-observability`](https://github.com/DataDog/terraform-datadog-byoc-observability) and is designed to be deployed alongside it, not instead of it. It deliberately ships none of the six core OPW monitors that module already owns.

| Module | Covers |
|---|---|
| `terraform-datadog-byoc-observability` | BYOC cluster health, plus OPW component errors, unintentional discards, buffer discards, sink buffer saturation, worker CPU, worker memory |
| this module | The OpenTelemetry Collector tier, and the OPW latency, request-admission, and disk-buffer signals the other module does not carry |

## Why this exists

Backpressure in a pipeline is observable, however the metrics that may appear best for observing this condition can show healthy. A blocked pipeline can appear neither busy nor full, so saturation and liveness read healthy while data is being refused upstream:

- `pipelines.utilization` is not emitted for sources at all, and a processor blocked on a full downstream buffer reports it falling toward zero. It cannot detect source-side backpressure, at any threshold.
- Worker CPU points in opposite directions depending on the cause, so it cannot rule backpressure in or out on its own. When the constraint is downstream I/O the workers park, CPU falls, and a CPU-target HPA can scale the fleet *down* mid-incident. When the constraint is the pipeline's own processing cost the workers are compute-bound, CPU pins near its limit, and the autoscaler asks for replicas it may not be permitted to have. The second shape is harder to spot: a fleet at its replica ceiling with CPU above target is indistinguishable, from pipeline telemetry alone, from a fleet that is correctly sized and busy.
- Destination buffer fullness can sit near zero while the buffer write path itself is the bottleneck.

The signals that do move are latency and queue depth: `source_send_batch_latency_seconds`, `source_lag_time_seconds`, `buffer_send_duration_seconds`, the source buffer occupancy ratio, and the Collector's exporter queue ratio. Those are what this module look at.

## Usage

```hcl
module "opw_otel_observability" {
  source = "github.com/DataDog/terraform-datadog-opw-otel-observability"

  datadog_site                 = "us5.datadoghq.com"
  pipeline_name_filter         = "*"
  paging_pipeline_name_include = ["prod", "production", "prd"]
  byoc_exporter_filter         = "*"      # narrow once you know the real exporter name

  notification_handles = ["@team-observability"]
  paging_handles       = ["@pagerduty-observability"]

  # Monitors are created muted. Flip to false once thresholds are validated.
  start_monitors_muted = true
}
```

Both the `datadog` and `restapi` providers must be configured for the same site and organization. See [`examples/basic`](examples/basic/main.tf). The `restapi` provider exists only because the Datadog provider has no Notebook resource.

## Design

### Verify your tags before trusting any of this

The single most important check before deploying. In Datadog, **`tag:*` matches only series that actually carry that tag**. A monitor scoped to a tag your deployment does not emit returns no data and sits in `OK` forever. That is worse than having no monitor, because it looks like coverage.

This module therefore emits **no tag term at all** when a filter is `*`, rather than `tag:*`. There is a test asserting no query contains `pipeline_name:*` or `exporter:*`.

Three tags cannot be assumed, and all three vary by deployment:

| Tag | Used for | Check it exists |
|---|---|---|
| `pipeline_name` | environment gating for paging | `avg:pipelines.source_lag_time_seconds{*} by {pipeline_name}` |
| `exporter` value | scoping exporter-tier Collector monitors | `avg:otelcol_exporter_queue_size{*} by {exporter}` |
| your workload tag | optional extra Collector grouping | `avg:otelcol_process_memory_rss{*} by {<your tag>}` |

If a group-by renders a single `N/A` series, that tag is absent. For `pipeline_name` specifically that silently disables paging, because `{{#is_match "pipeline_name.name" ...}}` can never match. Set `paging_pipeline_name_include = []` and `paging_pipeline_name_exclude = []` in that case: the module then drops `pipeline_name` from every group-by and pages on all groups.

Collector monitors always group by a tag intrinsic to the metric (`receiver`, `processor`, `exporter`, `host`), so they work regardless.

### Monitors ship muted

`start_monitors_muted` defaults to **true**, so a first apply creates all 16 monitors in a muted state and nothing pages. Set it to `false` and apply once the thresholds have been observed against real traffic.

The mute is a `datadog_downtime_schedule` with `one_time_schedule {}`: no start means it takes effect immediately, no end means it never expires. It selects monitors by `monitor_tags = ["managed-by:terraform-opw-otel"]`, which matches monitors carrying **all** listed tags, so it covers exactly this module's monitors and nothing else in the organization.

Monitor creation has an explicit `depends_on` for the downtime, so there is no window in which a monitor exists unmuted.

This is deliberately not the monitor `silenced` option. That field was deprecated and then removed from the Datadog provider, and because `datadog_monitor_json` diffs the whole monitor document, an operator unmuting a monitor in the UI would be silently re-muted by the next apply. A downtime is one visible resource, and cancelling it does not put Terraform in conflict with the monitors.

Ending the downtime notifies for anything already in `alert`, `warn`, or `no data`, so unmuting surfaces the current state rather than waiting for the next transition.

### No pipeline IDs

Monitors group by `pipeline_id` and scope by the `pipeline_name` tag (OPW 2.18 and later **with a DD feature flag turned on** - ask your account team to enable it for you; once enabled a no-op change to the pipeline must be made and deployed, a simple rename of a processor will suffice). Adding a business unit or an environment requires no Terraform change. `pipeline_name_filter` accepts a tag glob, so `example-*` or `*` both work.

### Production pages, pre-production does not

One monitor covers every environment, and paging recipients are gated per alerting group on the `pipeline_name` tag. There is no `env` tag on OPW metrics; `pipeline_name` is the only thing that knows which environment a pipeline belongs to, so the name has to carry the marker.

Matching is **substring based**, which means an include list alone is not sufficient: `prod` is a substring of both `pre-prod` and `non-prod`. Hyphens do not help either, since `mail-pre-prod-byoc` contains `-prod-`. The exclude list exists for exactly this.

| Config | Rendered gate | Behaviour |
|---|---|---|
| include + exclude (default) | `{{#is_match ...}}{{^is_match ...}}` | Pages when the name matches an include and no exclude |
| exclude only (`include = []`) | `{{^is_match ...}}` | Pages unless the name matches an exclude |
| both empty | no gate | Pages on every group |

**A caveat on the default.** Nesting two `is_match` sections is not documented by Datadog, and closing-tag resolution for same-named sections is unspecified. It is the form that most directly expresses "prod but not pre-prod", but verify it with a real test notification before relying on it.

The exclude-only form avoids that: one documented construct, no nesting, and it fails toward paging rather than toward silence. If a production pipeline is ever named without a recognised marker, include-mode silently never pages it, whereas exclude-mode pages it. For a high-volume production pipeline that is the safer direction to fail in. Set `paging_pipeline_name_include = []` and put every non-production marker in the exclude list.

Datadog does not document case handling for `is_match`, so the module expands every marker you supply into four casings and matches on all of them: lower, UPPER, `Title-Of-Each-Segment`, and `Sentence case`. Supply each marker once, in any casing.

Segments are split on `-`, `_`, `.` and space before title casing, because Terraform's `title()` treats hyphen and dot as word boundaries but **not** underscore. Without that split, `non_prod` would expand to `Non_prod` and miss `Non_Prod`.

The three default include markers therefore become nine match arguments, and the fourteen default exclude markers become fifty-two. `local.paging_include_variants` and `local.paging_exclude_variants` hold the expanded sets if you want to inspect them with `terraform console`.

OpenTelemetry Collector metrics carry no `pipeline_name` tag, so Collector monitors cannot be gated this way and page unconditionally when in the paging class. The module detects this automatically by checking whether `pipeline_name` is in each monitor's group-by, rather than relying on a hand-maintained flag.

### Finding the assets

Every monitor carries `managed-by:terraform-opw-otel`, `service:byoc-pipeline`, a `component:` tag, a `symptom:` tag, and a stable `asset-id:`. The `monitor_search_url` output links to a search for the whole set.

`asset-id:` is load-bearing. Notebook backlinks search on it, so it must stay stable across refactors.

Notebooks are named `OPW/OTel Runbook | <symptom>` and carry `metadata.type: runbook`. The Datadog Notebooks API does not support tags, so the name prefix is the only grouping mechanism.

### Attribution when shipping to more than one destination

A Collector that ships to both BYOC and another destination splits its metrics into two groups:

| Metric | Carries `exporter`? | Scoped by `byoc_exporter_filter` |
|---|---|---|
| `otelcol_exporter_enqueue_failed_log_records` | yes | yes |
| `otelcol_exporter_send_failed_log_records` | yes | yes |
| `otelcol_exporter_queue_size` / `_capacity` | yes | grouped by exporter, deliberately unscoped |
| `otelcol_receiver_refused_log_records` | no | no |
| `otelcol_processor_refused_log_records` | no | no |

`memory_limiter` reads process-wide Go heap, so when memory is high every limiter instance refuses regardless of which exporter grew it. Those two monitors carry the tag `scope:shared-with-other-destinations` and say so in their body.

The attribution tool is `monitor.otelcol-exporter-queue-saturated`, which is intentionally **not** filtered by exporter and groups by it instead. Whichever queue is growing is the one consuming collector memory.

### Version sensitivity

| Thing | Requirement |
|---|---|
| `pipeline_name` tag | OPW 2.18+ |
| `source_buffer_utilization_mean`, `source_buffer_max_size_events` | OPW 2.13+ |
| `source_send_batch_latency_seconds`, `source_lag_time_seconds` | OPW 2.16+ |
| `component_load_shed_requests_total`, `component_timed_out_requests_total`, `component_request_active`, `component_request_concurrency_limit` | OPW 2.23.0+ |
| `otelcol_processor_refused_log_records` | Collector **before** v0.155.0 |
| `otelcol_processor_memory_limiter_refused_log_records` | Collector v0.155.0+ |

Set `memory_limiter_refused_metric` to match your Collector version. The three request-admission monitors are inert below OPW 2.23.0; `pipelines.http_server_responses_sent_total{status:429}` and `{status:503}` are a version-agnostic fallback for spotting the same conditions.

### Collector telemetry level

`service::telemetry::metrics::level` defaults to `normal`, which drops every `otelhttp` and `otelgrpc` metric and strips `error.type` from export failures. Set `level: detailed` on the Collectors to distinguish a 429 from a 503 from a timeout on the hop to OPW.

### Metric names that look right and are not

- `pipelines.buffer_byte_size` and `pipelines.buffer_events` were **removed** in OPW 2.22.0, not merely deprecated. Use `pipelines.buffer_size_bytes` and `pipelines.buffer_size_events`.
- `source_buffer_utilization_mean` is an **absolute event count**, not a 0 to 1 ratio. Capacity is 1,000 events per vCPU. Always divide by `source_buffer_max_size_events`.
- The `otelcol_processor_dropped_*` family was removed in Collector v0.111.0 with no replacement.

### Two monitors that exist because a metric goes missing

`monitor.opw-source-buffer-metric-absent` and `monitor.otelcol-telemetry-absent` fire on absence, not on a value. OPW stops emitting `source_buffer_utilization_mean` once the source buffer is completely full, so without the companion monitor the saturation alert goes silent exactly when it matters.

### The mean and the tail are different questions

`pipelines.source_send_batch_latency_seconds` and `pipelines.buffer_send_duration_seconds` are **distributions**, not gauges. `avg:` returns the mean and describes the pipeline's condition. `max:` reaches inside each host's own sketch and returns the single worst sample, so a flat `max:` line is compatible with a p50 in microseconds.

Two monitors cover the source-blocked signal for that reason. The mean-based one tells you the pipeline is in trouble. The tail-based one tells you data is being lost, because harm here is a step function rather than a gradient: a batch that blocks longer than the Collector's exporter `timeout` is cancelled by the client and lost in full, up to `send_batch_max_size` records, while everything under that deadline costs nothing. Set `source_block_tail_critical_seconds` to that timeout.

A pipeline can hold a sub-millisecond mean and still shed batches in bursts. In that state the mean-based monitor is silent.

### Why there is an autoscaler monitor in a pipeline module

Every pipeline monitor in this module reports a symptom that appears *downstream* of a fleet that cannot grow. Saturated request admission, load shedding, source blocking and discards can all fire for days while the actual remedy is one number in a Helm value, and no OPW or Collector metric can see that number.

`monitor.k8s-hpa-at-ceiling` is opt-in because neither metric source is a dependency of the rest of this module. Set `hpa_monitor_source` to `datadog_agent` for `kubernetes_state.hpa.*`, which needs the Agent's `kubernetes_state_core` check, or to `otel_k8s_cluster` for `k8s.hpa.*`, emitted by the OpenTelemetry `k8sclusterreceiver`. Both report the same four gauges. Scope it with `hpa_scope`.

If it fires while worker CPU is *below* the autoscaler's target, the ceiling is not the problem and raising it will change nothing: the scaling signal is the problem.

### Sizing, if the monitors say you are undersized

Size from measured CPU per event, not from throughput:

```
pods = (events per second x pod CPU seconds per event) / (vCPU per pod x target utilisation)
```

Use **pod** CPU, from `pipelines.cpu_usage_seconds_total` over `pipelines.cpu_max_cores`. `pipelines.component_cpu_usage_ns_total` is per component, and dividing it by worker count understates utilisation by whatever the source, sink, TLS and buffer serialisation cost.

A bytes-per-day sizing heuristic embeds an assumption about processing cost per event. On a processor-heavy pipeline that assumption can be wrong by several times over, and the failure is quiet: the fleet pins at its ceiling while every byte figure anyone is looking at says there is headroom.

## Monitors

Eleven OPW monitors, seven OpenTelemetry Collector monitors, and one optional autoscaler monitor.

| Asset ID | Class | Fires on |
|---|---|---|
| `monitor.opw-source-send-latency-high` | paging | Source blocked pushing into the pipeline, mean > 5s |
| `monitor.opw-source-send-latency-tail` | paging | Worst single blocked send past the client's exporter deadline |
| `monitor.opw-worker-cpu-saturated` | paging | Worker CPU over 85% of its own cgroup allocation |
| `monitor.opw-source-lag-high` | paging | Source lag > 60s |
| `monitor.opw-buffer-write-stall` | paging | Buffer write duration > 0.5s |
| `monitor.opw-source-buffer-saturated` | paging | Source buffer occupancy ratio > 0.9 for 10m |
| `monitor.opw-source-buffer-metric-absent` | paging | Source buffer metric stopped reporting |
| `monitor.opw-request-admission-saturated` | investigation | Active requests over concurrency limit > 0.8 |
| `monitor.opw-requests-load-shed` | paging | Any request rejected at the concurrency cap |
| `monitor.opw-requests-timed-out` | paging | Any request exceeding the processing timeout |
| `monitor.opw-disk-buffer-space-low` | paging | Disk buffer volume below 20% free |
| `monitor.otelcol-memory-limiter-refusing` | paging | memory_limiter refusing records (shared) |
| `monitor.otelcol-receiver-refusing` | paging | Receiver refusing records (shared) |
| `monitor.otelcol-exporter-enqueue-failed` | paging | BYOC exporter queue rejecting batches |
| `monitor.otelcol-exporter-queue-saturated` | paging | Any exporter queue over 80% full |
| `monitor.otelcol-terminal-data-loss` | paging | `Exporting failed. Dropping data.` in Collector logs |
| `monitor.otelcol-exporter-send-failed` | investigation | BYOC exporter send attempts failing |
| `monitor.otelcol-telemetry-absent` | investigation | Collector self-telemetry stopped reporting |
| `monitor.k8s-hpa-at-ceiling` | paging | Autoscaler wanting at least its maximum replicas for 30m (opt-in) |

Terminal loss after dequeue has no counter metric. `otelcol_exporter_send_failed_log_records` also increments on every retry, so the log line and its `dropped_items` field are the only unambiguous record. That is why one monitor in the set is a log monitor.

## Notebooks

| Asset ID | Purpose |
|---|---|
| `notebook.start-here` | Navigation and architecture overview |
| `notebook.opw-backpressure-triage` | The three-layer walk, destination first |
| `notebook.opw-source-buffer-saturated` | Source channel saturation |
| `notebook.opw-request-admission-shedding` | 2.23.0 admission control |
| `notebook.otelcol-refusing-data` | Collector refusals and exporter attribution |
| `notebook.assessing-impact` | Whether data is actually being lost, and how much runway remains |

Each monitor body links to `assessing-impact` under Impact and to its runbook under What to do. Notebooks link back to monitors by `asset-id:` tag search, never by monitor ID, which keeps the Terraform dependency graph acyclic.

## Known limitations

- **Three monitors are inert below OPW 2.23.0.** `opw-request-admission-saturated`, `opw-requests-load-shed`, and `opw-requests-timed-out` depend on metrics added in that release. They will sit in `No Data` rather than error. `pipelines.http_server_responses_sent_total{status:429}` and `{status:503}` are a version-agnostic substitute.
- **Collector metric names are version-sensitive**, and getting one wrong produces a monitor that silently never fires. See the version table above, and set `memory_limiter_refused_metric` to match your build.
- **Collector monitors are inert without Collector self-telemetry.** If your Collectors do not ship `otelcol_*` to the same organization, seven of the sixteen monitors have nothing to evaluate. `otelcol-telemetry-absent` is included to detect exactly that, but it only covers groups that reported at least once.
- **Two signals cannot be attributed to a single destination.** See the dual-shipping section. If you ship to more than one place, read those two monitors as shared-fate, not as evidence about any one destination.
- **No dashboard.** Monitors and runbooks only. The out-of-the-box Observability Pipelines Overview dashboard covers most of the same series.
- **Thresholds carry no statistical basis.** They are reasoned, not fitted.

## Outputs

| Output | Purpose |
|---|---|
| `monitor_ids` / `notebook_ids` / `notebook_urls` | Created assets keyed by stable asset ID |
| `start_here_url` | Runbook entrypoint |
| `monitor_search_url` | Monitor search covering the whole managed set |
| `monitors_muted` | Whether the module is currently holding monitors muted |
| `mute_downtime_id` | The indefinite downtime, or null when unmuted |

## Development

```sh
make init    # terraform init -backend=false
make fmt     # terraform fmt -recursive
make check   # fmt -check + validate
make test    # check + terraform test
```

Tests use mocked providers and need no credentials. CI runs `check-licenses`, `init`, and `test`.

Commit both `.terraform.lock.hcl` files and update `LICENSE-3rdparty.csv` in the same change as any provider version bump, or `make check-licenses` fails.

## License

Apache-2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
