#!/usr/bin/env ruby
# encoding: UTF-8
require 'rubygems' # for ruby 1.8
require 'sinatra'
require 'json'
require 'net/http'
require 'dbi'
require './tokens'

$dbh = nil
$token = nil
$tablename = nil

def fetchRowFromDB(text)
  sth = $dbh.prepare("SELECT points FROM `#{$tablename}` WHERE thing = ?;")
  sth.execute(text)
  return sth.fetch() 
end

def fetchKarmaFromDB(text)
  row = fetchRowFromDB(text)
  if(row.nil?)
    return 0
  else
    return row['points']
  end
end

def adjustKarmaInDB(text,amt)
  row = fetchRowFromDB(text)
  if(row.nil?)
     sth = $dbh.prepare( "INSERT INTO `#{$tablename}`(thing,points) VALUES (?, ?);" )
     sth.execute(text,amt)
  else
     sth = $dbh.prepare("UPDATE `#{$tablename}` SET points = ? WHERE thing = ?;")
     newpoints = row['points'] + amt
     sth.execute(newpoints,text)
  end
end

def sendMessage(text, channel)
    uri = URI('https://slack.com/api/chat.postMessage')
    params = { :token => $token, :channel => channel, :text => text }
    uri.query = URI.encode_www_form(params)

    https = Net::HTTP.new(uri.host,uri.port)
    https.use_ssl = true
    req = Net::HTTP::Post.new(uri.path+'?'+uri.query)
    res = https.request(req)
end

def handleChange(text,channel)
  regexp = /((\w+)|\(([^)]+)\))(\+\+|--)/
  matches = text.scan(regexp)

  if(matches.length == 0)
    return false
  end

  matches.each do |match|
    amt = (match[3]=='++' ? 1 : match[3]=='--' ? -1 : 0)
    thing = match[1] ? match[1] : match[2]
    if (amt && thing)
      adjustKarmaInDB(thing,amt)
    end
  end

  return true
end

def handleFetch(text,channel)
  if(!text.start_with?("!karma "))
    return false
  end
  regexp = /((\w+)|\(([^)]+)\))/
  str = ""
  text.scan(regexp).each_with_index do |m,i|
    if(i==0)
      next
    end
    word = m[1] ? m[1] : m[2]
    karma = fetchKarmaFromDB(word)
    str += "#{word} has #{karma} karma. "
  end
  
  if(str != "")
    sendMessage(str,channel)
    return true
  end

  return false  
end


post '/message' do 
  req = JSON.parse(request.body.read)

  if(req["challenge"])
    return req["challenge"]
  end

  verificationToken = req["token"]
  $token = $tokenMap[verificationToken]

  if(req["event"]["subtype"] || !$token) 
    return
  end

  $dbh = DBI.connect("DBI:Mysql:#{$dbName}:localhost", $dbUser, $dbtoken)
  $tablename = $tableMap[verificationToken]

  channel = req["event"]["channel"]
  text = req["event"]["text"]

  fetched = handleFetch(text,channel)
  if (!fetched) 
    #don't adjust karma inside a fetch
    handleChange(text,channel)
  end

  $dbh.disconnect()

end
