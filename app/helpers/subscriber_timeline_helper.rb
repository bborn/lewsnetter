module SubscriberTimelineHelper
  # Maps Account::SubscriberTimeline `kind` values to human labels for the
  # mono-caps eyebrow on each timeline row. Kept here rather than in the
  # service so the service stays presentation-agnostic.
  TIMELINE_KIND_LABELS = {
    "signup" => "Signup",
    "campaign_sent" => "Sent",
    "delivered" => "Delivered",
    "opened" => "Opened",
    "clicked" => "Clicked",
    "bounced" => "Bounced",
    "complained" => "Complained",
    "unsubscribed" => "Unsubscribed",
    "custom_event" => "Event"
  }.freeze

  # Tailwind text-color classes per kind. Semantic colors from DESIGN.md:
  # opened/delivered = success green, clicked = info blue, bounced /
  # complained / unsubscribed = rose danger, custom_event neutral, sent
  # neutral (not its own moment — the campaign header carries the weight).
  TIMELINE_KIND_COLORS = {
    "signup" => "text-zinc-500 dark:text-zinc-400",
    "campaign_sent" => "text-zinc-500 dark:text-zinc-400",
    "delivered" => "text-emerald-600 dark:text-emerald-400",
    "opened" => "text-emerald-600 dark:text-emerald-400",
    "clicked" => "text-blue-700 dark:text-blue-400",
    "bounced" => "text-rose-600 dark:text-rose-400",
    "complained" => "text-rose-600 dark:text-rose-400",
    "unsubscribed" => "text-rose-600 dark:text-rose-400",
    "custom_event" => "text-zinc-600 dark:text-zinc-300"
  }.freeze

  def timeline_kind_label(kind)
    TIMELINE_KIND_LABELS.fetch(kind.to_s, kind.to_s.humanize)
  end

  def timeline_kind_color(kind)
    TIMELINE_KIND_COLORS.fetch(kind.to_s, "text-zinc-500 dark:text-zinc-400")
  end
end
