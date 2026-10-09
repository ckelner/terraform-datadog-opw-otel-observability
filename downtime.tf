# Monitors are created muted so a new deployment cannot page on a threshold that has
# not been observed against real traffic yet. Unmuting is a deliberate, auditable
# Terraform change: set start_monitors_muted = false and apply.
#
# This is a downtime rather than the monitor `silenced` option. `silenced` was
# deprecated and then removed from the Datadog provider, and because
# datadog_monitor_json diffs the entire monitor document, an operator unmuting a
# monitor in the UI would be silently re-muted by the next apply. A downtime is a
# single resource an operator can see, and cancelling it does not fight Terraform
# on the monitors themselves.
#
# Selection is by monitor tag, not by monitor ID. monitor_tags matches monitors
# carrying ALL listed tags, and every monitor in this module carries
# managed-by:terraform-opw-otel, so the downtime covers exactly this module's
# monitors and nothing else in the organization.
resource "datadog_downtime_schedule" "initial_mute" {
  count = var.start_monitors_muted ? 1 : 0

  # Scope is the tag scope of the monitored data, not of the monitor. Monitor
  # selection is done entirely by monitor_tags below.
  scope = "*"

  monitor_identifier {
    monitor_tags = ["managed-by:terraform-opw-otel"]
  }

  # No start means the downtime begins the moment it is created. No end means it
  # never expires. Together: muted indefinitely from creation.
  one_time_schedule {}

  message = var.mute_message

  # When the downtime is cancelled, notify for anything already firing, so turning
  # alerting on surfaces the current state instead of waiting for the next
  # transition.
  notify_end_types  = ["canceled", "expired"]
  notify_end_states = ["alert", "warn", "no data"]
}
