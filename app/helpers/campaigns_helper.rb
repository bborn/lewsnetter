module CampaignsHelper

  def entry_image(entry)
    if entry.image
      #add protocol to relative protocol images
      entry.image.starts_with?('//') ? "http:#{entry.image}" : entry.image
    else
      first_image(entry.summary)
    end
  end

  def first_image(html)
    doc = Nokogiri::HTML(html)
    if img = doc.at('img')
      img['src']
    else
      ''
    end
  end

end
