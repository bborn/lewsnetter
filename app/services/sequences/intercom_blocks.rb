# Converts an Intercom message's content blocks (the `blocks` /
# `subject_blocks` arrays in a Series export) to the markdown a SequenceStep
# stores. Merge tags are left exactly as Intercom wrote them; CampaignRenderer
# understands {{attr|fallback:"x"}} and the custom_data./company. namespaces.
#
#   md, warnings = Sequences::IntercomBlocks.to_markdown(blocks)
module Sequences
  module IntercomBlocks
    module_function

    def to_markdown(blocks)
      warnings = []
      parts = convert(blocks, warnings)
      [parts.join("\n\n").strip, warnings.uniq]
    end

    def subject(blocks)
      Array(blocks).map { |b| inline(b["text"], plain: true) }.reject(&:empty?).join(" ").strip
    end

    def convert(blocks, warnings)
      Array(blocks).flat_map do |block|
        case block["type"]
        when "paragraph" then para(block)
        when "heading", "header" then heading("##", block)
        when "subheading" then heading("###", block)
        when "unorderedList" then list(block, ordered: false)
        when "orderedList" then list(block, ordered: true)
        when "button" then button(block)
        when "image" then image(block)
        when "horizontalRule" then ["---"]
        when "table"
          Array(block["rows"]).flat_map do |row|
            Array(row["cells"]).flat_map { |cell| convert(cell["content"], warnings) }
          end
        when "ifElseStatement"
          warnings << "conditional content block: kept the fallback (else) branch"
          convert(block["fallbackBlocks"], warnings)
        when "video", "videoFile"
          url = block["url"] || block["embedUrl"]
          url ? ["[Watch the video](#{url})"] : []
        else
          warnings << "unsupported block dropped: #{block["type"]}"
          []
        end
      end
    end

    def para(block)
      text = inline(block["text"])
      text.empty? ? [] : [escape_line_starts(text)]
    end

    def heading(marker, block)
      text = inline(block["text"], plain: true)
      text.empty? ? [] : ["#{marker} #{text}"]
    end

    def list(block, ordered:)
      lines = Array(block["items"]).each_with_index.map do |item, i|
        text = inline(item.is_a?(String) ? item : item["text"])
        "#{ordered ? "#{i + 1}." : "-"} #{text}"
      end
      [lines.join("\n")]
    end

    def button(block)
      url = block["linkUrl"] || block["url"]
      text = inline(block["text"], plain: true)
      url.present? ? ["**[#{text}](#{decode_tags(url)})**"] : [text]
    end

    def image(block)
      return [] if block["url"].blank?
      img = "![#{block["alt"].to_s.tr("[]", "")}](#{block["url"]})"
      block["linkUrl"].present? ? ["[#{img}](#{block["linkUrl"]})"] : [img]
    end

    # Intercom's inline HTML → markdown: bold, italics, links, line breaks.
    def inline(html, plain: false)
      s = html.to_s.gsub(/<br\s*\/?>/i, plain ? " " : "  \n")
      unless plain
        s = s.gsub(%r{<(b|strong)>(.*?)</\1>}im) { "**#{$2.strip}**" }
        s = s.gsub(%r{<(i|em)>(.*?)</\1>}im) { "*#{$2.strip}*" }
        s = s.gsub(%r{<a [^>]*href="([^"]*)"[^>]*>(.*?)</a>}im) { "[#{$2}](#{decode_tags(CGI.unescapeHTML($1))})" }
      end
      s = s.gsub(/<[^>]+>/, "")
      CGI.unescapeHTML(s).delete("​").strip
    end

    # Intercom URL-encodes merge tags inside hrefs (%7B%7B ... %7D%7D).
    def decode_tags(url)
      url.gsub(/%7B%7B(.*?)%7D%7D/i) { "{{#{CGI.unescape($1).strip}}}" }
    end

    # A paragraph that happens to start with "#1" or "1." must not turn into
    # a heading or a list.
    def escape_line_starts(text)
      text.gsub(/^(\s*)(#|>|[-+*](?=\s)|\d+(?=[.)]\s))/) { "#{$1}\\#{$2}" }
    end
  end
end
