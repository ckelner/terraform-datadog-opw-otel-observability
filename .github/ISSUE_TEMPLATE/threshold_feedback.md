---
name: Threshold feedback
about: Report a monitor threshold that is wrong for a real deployment
labels: threshold
---

None of the thresholds in this module were calibrated against production
traffic, so reports like this are the most useful kind of issue.

## Which monitor?

Asset ID, for example `monitor.opw-source-send-latency-high`.

## What did it do?

Too noisy, too quiet, or never fired when it should have.

## What does normal look like for you?

Rough scale helps: ingest volume, worker vCPU, pod count, and the observed
range of the metric in question during healthy operation.

## What would you set it to?
