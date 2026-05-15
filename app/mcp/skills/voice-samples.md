---
name: voice-samples
description: The team's last 10 sent campaigns (subject + body excerpt) for grounding draft prompts.
when_to_use: When generating a campaign draft, include this resource so the new draft matches the team's established voice.
---

# Voice samples — <%= context.team.name %>

The last 10 campaigns this team sent, in reverse-chronological order. Use these to ground the tone of any new draft.

<% samples = context.team.campaigns.where(status: "sent").order(sent_at: :desc).limit(10) %>
<% if samples.any? %>
<% samples.each_with_index do |c, i| %>
## <%= i + 1 %>. <%= c.sent_at&.strftime("%Y-%m-%d") %> — "<%= c.subject %>"

<%= (c.body_markdown.presence || c.body_mjml.to_s.gsub(/<[^>]+>/, " ").squish).to_s[0, 600] %>...

<% end %>
<% else %>
The team hasn't sent any campaigns yet. There are no voice samples to learn from. The drafter should use a default friendly-clear tone.
<% end %>

## Voice notes

When drafting:
- **Match the salutation pattern.** If past sends use first-name greetings, do the same. If they jump straight into the news, do that.
- **Match the CTA style.** "Read more →", "Get started", "Book a call" — whatever pattern is established.
- **Match the length.** If past sends are 3 short paragraphs, don't ship a wall of text.
- **Match the formality.** Past sends set the register; departing from it without intent reads as a different brand.
