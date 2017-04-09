#!/usr/bin/env ruby
# encoding: UTF-8
require 'rubygems' # for ruby 1.8
require 'sinatra'
require 'json'
require 'net/http'

def sendMessage(text, channel)
    token = "xoxp-18389917205-31824788208-167317729894-68eda642b565103074c8b170aaa011cd"

    uri = URI('https://slack.com/api/chat.postMessage')
    params = { :token => token, :channel => channel, :text => text }
    uri.query = URI.encode_www_form(params)

    https = Net::HTTP.new(uri.host,uri.port)
    https.use_ssl = true
    req = Net::HTTP::Post.new(uri.path+'?'+uri.query)
    res = https.request(req)
end

def handleChange(text,channel)
  regexp = /(\w+)(\+\+|--)/
  matches = text.scan(regexp)

  if(matches.length == 0)
    return
  end

  str = ""  
  matches.each do |match|
    str += match[0]
    str += case match[1]
      when '++' then ' improves. '
      when '--' then ' worsens. '
    end
  end

  sendMessage(str,channel)
end

def handleFetch(text,channel)
  if(!text.start_with?("!karma "))
    return
  end
  str = text[7...text.length]
  sendMessage("You tried to find the karma of _#{str}_, but my db access isn't set up yet :(",channel)

end


post '/message' do 
  req = JSON.parse(request.body.read)

  puts req

  if(req["event"]["subtype"]) 
    return
  end

  channel = req["event"]["channel"]
  text = req["event"]["text"]

  #testing - only use the test channel for now
  if(channel == "C4WKUSNA0")
    handleChange(text,channel)
    handleFetch(text,channel)
  end

end
