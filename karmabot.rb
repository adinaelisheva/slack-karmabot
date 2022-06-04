#!/usr/bin/env ruby
# encoding: UTF-8
require 'mysql2'
require 'rubygems' # for ruby 1.8
require 'sinatra'
require 'json'
require 'net/http'
require './tokens'

set :port, 9999
set :bind, '0.0.0.0'

$token = nil
$tablename = nil
$client = nil

def fetchRowFromDB(text)
  statement = $client.prepare("SELECT points FROM `#{$tablename}` WHERE thing = ?;")
  return statement.execute(text)
end

def fetchKarmaFromDB(text)
  puts "fetching karma from db for #{text}"
  res = fetchRowFromDB(text)
  res.each do |row|
    # there should only be 1 row
    return row['points']
  end
  return 0
end

def adjustKarmaInDB(text,amt)  
  puts "Updating #{text} by #{amt}"
  res = fetchRowFromDB(text)
  res.each do |row|
    # there should be only one row
    puts "found entry for #{text}, updating"
    newpoints = row['points'] + amt
    statement = $client.prepare("UPDATE `#{$tablename}` SET points = ? WHERE thing = ?;");
    statement.execute(newpoints, text)
    return
  end

  #if we got here, there was no row - make one
  puts "no entry for #{text}, creating one"
  statement = $client.prepare("INSERT INTO `#{$tablename}`(thing,points) VALUES (?, ?);")
  statement.execute(text, amt)

end

def sendMessage(text, channel)
  print("Sending: #{text}")
  uri = URI('https://slack.com/api/chat.postMessage')
  params = { :token => $token, :channel => channel, :text => text }
  uri.query = URI.encode_www_form(params)

  https = Net::HTTP.new(uri.host,uri.port)
  https.use_ssl = true
  req = Net::HTTP::Post.new(uri.path+'?'+uri.query)
  res = https.request(req)
end

def handleChange(text,channel,user)
  regexp = /(([^()\-+\s]+)|\(([^)]+)\))(\+\+|--)/
  matches = text.scan(regexp)

  if(matches.length == 0)
    return false
  end

  matches.each do |match|
    amt = (match[3]=='++' ? 1 : match[3]=='--' ? -1 : 0)
    thing = match[1] ? match[1] : match[2]
    thing = replaceUIDWithUname(thing)
    if (amt && thing)
      if (thing == user)
        sendMessage("#{user}-- for attempting to modify own karma",channel)
        adjustKarmaInDB(user, -1)
      else
        adjustKarmaInDB(thing, amt)
      end
    end
  end

  return true
end

def doKarma(text,channel,user)
  puts "checking karma for '#{text}'"

  if(!text.match(/^!karma\b/))
    return false
  end

  #chop off the '!karma'
  text = text[7..text.length]
  puts "after chopping text is '#{text}'"

  if(!text || text.match(/^\s*$/))
    puts "blank input - replacing with username (#{user})"
    text = user
  end
  regexp = /(([^()\-+\s]+)|\(([^)]+)\))/
  str = ""
  text.scan(regexp).each_with_index do |m,i|
    puts "checking karma for #{i}th item in command"
    word = m[1] ? m[1] : m[2]
    karma = fetchKarmaFromDB(replaceUIDWithUname(word))
    str += "#{word} has #{karma} karma. "
  end

  if(str != "")
    sendMessage(str,channel)
    return true
  end

  return false
end

def doTop(text,channel,user)
  puts "getting top karma for '#{text}'"
  count = 3
  m = text.match(/^top(?<count>\d+)/)
  if (m)
    count = m[:count].to_int
  end

  sth = $client.prepare("SELECT thing,points FROM `#{tablename}` ORDER BY points DESC, thing ASC LIMIT #{count};")
  sth.execute()
  str = ""
  rank = 1
  sth.fetch do |row|
    thing = "#{row['thing']}".force_encoding('utf-8').gsub('"','&quot;')
    str += "#{rank}. \"#{thing}\" (#{row['points']}) "
  end
  dbh.disconnect()

  if(str != "")
    sendMessage(str,channel)
    return true
  end

  return false
end

def doBottom(text,channel,user)
  puts "getting bottom karma for '#{text}'"
  count = 3
  m = text.match(/^bottom(?<count>\d+)/)
  if (m)
    count = m[:count].to_int
  end

  sth = $client.prepare("SELECT thing,points FROM `#{tablename}` ORDER BY points ASC, thing ASC LIMIT #{count};")
  sth.execute()
  str = ""
  rank = 1
  sth.fetch do |row|
    thing = "#{row['thing']}".force_encoding('utf-8').gsub('"','&quot;')
    str += "#{rank}. \"#{thing}\" (#{row['points']}) "
  end
  dbh.disconnect()

  if(str != "")
    sendMessage(str,channel)
    return true
  end

  return false
end

def handleFetch(text,channel,user)
  if(text.match(/^!karma\b/))
    return doKarma(text,channel,user)
  elsif(text.match(/^!top/))
    return doTop(text,channel,user)
  elsif(text.match(/^!bottom/))
    return doBottom(text,channel,user)
  else
    return false
  end
end

def replaceUIDWithUname(strWithUID)
  # to fetch the username from the slack api, just send the UXXXX id
  uidRegex = /U[A-Z0-9]+/
  puts "strWithUID: #{strWithUID}"
  regexMatch = uidRegex.match(strWithUID)
  if(regexMatch && regexMatch[0])
    id = regexMatch[0]
  else
    puts "no valid UID found"
    return strWithUID
  end
  puts "fetching user for #{id}"
  uri = URI('https://slack.com/api/users.info')
  params = { :token => $token, :user => id }
  uri.query = URI.encode_www_form(params)

  https = Net::HTTP.new(uri.host,uri.port)
  https.use_ssl = true
  req = Net::HTTP::Post.new(uri.path+'?'+uri.query)
  res = JSON.parse(https.request(req).body)
  if(!res["ok"])
    return strWithUID
  end
  username = res["user"]["name"]
  # for replacing, the regex supports plain UXXX and <@UXXXX> style ids
  fullUidRegex = /(<@)?U[A-Z0-9]+>?/ 
  ret = strWithUID.gsub(fullUidRegex, username)
  puts "returning #{ret}"
  return ret
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

  $client = Mysql2::Client.new(host: "localhost", username: $dbUser, password: $dbToken, database: $dbName)
  $tablename = $tableMap[verificationToken]

  channel = req["event"]["channel"]
  text = req["event"]["text"]
  user = replaceUIDWithUname(req["event"]["user"])

  fetched = handleFetch(text,channel,user)
  if (!fetched) 
    #don't adjust karma inside a fetch
    handleChange(text,channel,user)
  end

end

#getter for all karma used by the HTML page (and maybe others)
get '/allKarma/:table' do |tablename|
  client = Mysql2::Client.new(host: "localhost", username: $dbUser, password: $dbToken, database: $dbName)
  statement = client.prepare("SELECT thing,points FROM `#{tablename}` ORDER BY points DESC, thing ASC;");
  results = statement.execute();
  start = true
  ret = '['
  results.each do |row|
    if start
      start = false
    else
      ret += ','
    end
    thing = "#{row['thing']}".force_encoding('utf-8').gsub('"','&quot;')
    ret += "[\"#{thing}\",#{row['points']}]"
  end
  ret += ']'
  ret
end

get '/' do
  File.read(File.join('public', 'index.html'))
end
