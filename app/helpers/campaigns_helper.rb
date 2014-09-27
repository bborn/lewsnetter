module CampaignsHelper

  def first_image(html)
    doc = Nokogiri::HTML(html)
    if img = doc.at('img')
      img['src']
    else
      ''
    end
  end

end
