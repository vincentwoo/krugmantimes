require 'sinatra'
require 'sinatra/reloader' if development?

require 'http'
require 'nokogiri'

get '/' do
  nyt_body = HTTP.get('https://www.nytimes.com/').to_s
  doc = Nokogiri::HTML nyt_body

  doc.css('head').children.first
    .add_previous_sibling('<base href="https://www.nytimes.com">')
  # remove all scripts
  # doc.css('script').remove

  # cleanup absolute paths without host
  # doc.css('[href]').each do |node|
  #   if node['href'].start_with? '/'
  #     node['href'] = 'https://www.nytimes.com' + node['href']
  #   end
  # end
  # doc.css('[src]').each do |node|
  #   if node['src'].start_with? '/'
  #     node['src'] = 'https://www.nytimes.com' + node['src']
  #   end
  # end

  # unintelligent hardcode to delete pre-masthead div
  doc.css('.css-1ichrj1').remove

  # '.adWrapper, .singleAd, .advertisement, meta, .ad'

  doc.to_s
end

# proxy CSS requests to nytimes server
# get '/*' do
#   HTTP.get("https://www.nytimes.com#{request.fullpath}").to_s
# end
