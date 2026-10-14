require "ipaddr"

# Shared rules for telling machine traffic (corporate link scanners, Apple
# Mail Privacy Protection, HTTP libraries) apart from people on the open
# pixel and click redirect. Used by ClickEvent and OpenEvent.
#
# Why this exists: business inboxes sit behind security gateways that fetch
# every link in every message within seconds of delivery (Microsoft Defender
# Safe Links, Proofpoint URL Defense, Mimecast, Barracuda…), and Apple Mail
# prefetches every image through a proxy. Without filtering, a campaign to a
# business list shows click-through rates of 20%+ that are almost entirely
# robots, and the numbers can't be used to judge the campaign.
#
# Every threshold below is a plain constant so it's easy to find and tune.
# The rules are deliberately one-way: they can only flag an event as
# automated. A later event on the same delivery that matches none of them
# still counts as human (a scanner pass followed by the real reader is the
# common case).
module MachineTraffic
  # Clicks that land this soon after the message was delivered (or sent, if
  # SES hasn't reported delivery yet) are treated as scanner pre-fetches.
  # Gateways scan at delivery time, before a person could plausibly have
  # opened the message and clicked. Note `delivered_at` is stamped when the
  # SNS webhook arrives, which can be a little after the real delivery, so a
  # click that "precedes" delivery is also inside the window.
  CLICK_SEND_PROXIMITY_WINDOW = 120.seconds

  # Same idea for the open pixel. Shorter, because opens are cheap and a
  # reader with notifications on can open within a minute or two.
  OPEN_SEND_PROXIMITY_WINDOW = 60.seconds

  # Scanner fan-out: the same delivery hitting this many distinct links
  # within this many seconds. People click one link, read the page, maybe
  # come back; scanners request every link at once.
  FANOUT_WINDOW = 10.seconds
  FANOUT_MIN_DISTINCT_LINKS = 3

  # When the invisible honeypot link is hit, every click on that delivery
  # within this window either side of the hit is flagged too.
  HONEYPOT_BURST_WINDOW = 60.seconds

  # Bound per-delivery event rows so a replayed tracking URL can't grow the
  # table without limit. Past the cap we still bump the raw Delivery
  # counters, we just stop writing event rows.
  MAX_EVENTS_PER_DELIVERY = 100

  # User agents that are never a person clicking a link: security gateways,
  # link-preview fetchers, and generic HTTP libraries. Matched
  # case-insensitively anywhere in the UA string.
  #
  # "Microsoft Office" / "ms-office" covers the Office preview fetchers
  # (Safe Links detonation, Outlook link previews). When a person clicks a
  # link in Outlook it opens in their browser, so the click carries the
  # browser's UA, not Office's.
  CLICK_SCANNER_PATTERN = Regexp.union(
    /barracuda/i, /proofpoint/i, /mimecast/i, /safelinks/i, /microsoft office/i,
    /ms-office/i, /skypeuripreview/i, /bingpreview/i, /appriver/i, /messagelabs/i,
    /symantec/i, /forcepoint/i, /trend ?micro/i, /sophos/i, /fortinet/i, /fortiguard/i,
    /ironport/i, /cisco/i, /zscaler/i, /checkpoint/i, /trustwave/i, /mailcontrol/i,
    /python-requests/i, /python-urllib/i, /aiohttp/i, /httpx/i, /\bcurl\//i, /\bwget/i,
    /go-http-client/i, /\bjava\//i, /okhttp/i, /apache-httpclient/i, /libwww-perl/i,
    /node-fetch/i, /axios/i, /undici/i, /headlesschrome/i, /phantomjs/i,
    /facebookexternalhit/i, /slackbot/i, /twitterbot/i, /linkedinbot/i, /googlebot/i,
    /\bbot\b/i, /crawler/i, /spider/i, /scanner/i
  )

  # Open-pixel UAs that are never a person reading. Narrower than the click
  # list: Outlook desktop really does fetch images as "Microsoft Office…"
  # when someone opens the message, and Gmail/Yahoo image proxies fetch on
  # a real open, so those are NOT here.
  OPEN_SCANNER_PATTERN = Regexp.union(
    /barracuda/i, /proofpoint/i, /mimecast/i, /safelinks/i, /appriver/i, /messagelabs/i,
    /symantec/i, /forcepoint/i, /ironport/i, /zscaler/i,
    /python-requests/i, /python-urllib/i, /\bcurl\//i, /\bwget/i, /go-http-client/i,
    /\bjava\//i, /okhttp/i, /apache-httpclient/i, /node-fetch/i, /axios/i,
    /headlesschrome/i, /\bbot\b/i, /crawler/i, /spider/i
  )

  # Apple Mail Privacy Protection fetches every image through Apple's proxy
  # as soon as the message reaches the device, whether or not anyone reads
  # it. The proxy sends this bare UA (real Mail.app/WebKit UAs are longer).
  APPLE_MPP_USER_AGENT = "Mozilla/5.0"

  USER_AGENT_MAX_LENGTH = 512

  module_function

  # The moment the delivery reached (or at least left for) the recipient's
  # mail server. nil when we have neither, in which case timing rules can't
  # apply.
  def delivery_anchor(delivery)
    delivery.delivered_at || delivery.sent_at
  end

  # True when `at` is within `window` after the anchor, or before it.
  def within_send_window?(delivery, at, window)
    anchor = delivery_anchor(delivery)
    return false if anchor.nil? || at.nil?
    at - anchor < window
  end

  # Anonymized network prefix for an IP: IPv4 /24, IPv6 /48. Enough to spot
  # "these hits all came from one gateway" without storing a full address.
  def ip_prefix(ip)
    return nil if ip.blank?
    addr = IPAddr.new(ip.to_s)
    addr.ipv4? ? addr.mask(24).to_s : addr.mask(48).to_s
  rescue IPAddr::InvalidAddressError
    nil
  end

  def truncate_user_agent(user_agent)
    user_agent.to_s.strip[0, USER_AGENT_MAX_LENGTH].presence
  end
end
