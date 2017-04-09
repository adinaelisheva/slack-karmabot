#!/usr/bin/env ruby
# encoding: UTF-8
require 'rubygems' # for ruby 1.8
require 'sinatra'
require 'json'
require 'net/http'
require 'token'

def sendMessage(text, channel)

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

  if(req["event"]["subtype"] || req["token"] != "L1jzs0c6I2WHhu7jfHaBR83O") 
    return
  end

  channel = req["event"]["channel"]
  text = req["event"]["text"]

  #testing - only use the test channel for now
  if(channel == "C4WKUSNA0")
    puts req
    handleChange(text,channel)
    handleFetch(text,channel)
  end

end
