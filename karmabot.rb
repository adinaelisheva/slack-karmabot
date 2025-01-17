# encoding: UTF-8
require 'mysql2'
require 'rubygems' # for ruby 1.8
require 'sinatra'
require 'json'
require 'net/http'
require './tokens'
require 'discordrb'

$tablename = nil
$client = nil
$curApp = nil

set :port, 9999
set :bind, '0.0.0.0'

$token = nil

$dbLastConnected = 0

########## SHARED ##########
def doKarma(text, isSlack)
  puts "checking karma for '#{text}'"
  regexp = /(([^()\-+\s]+)|\(([^)]+)\))/
  str = ""
  text.scan(regexp).each_with_index do |m,i|
    puts "checking karma for #{i}th item in command"
    word = m[1] ? m[1] : m[2]
    word = canonicalizeText(word, isSlack)
    karma = fetchKarmaFromDB(word)
    str += "#{word} has #{karma} karma. "
  end

  return str
end

def canonicalizeText(text, isSlack)
  if (isSlack) 
    text = replaceUIDWithSlackUname(text)
  end
  return reduceToCanonicalAlias(text)
end

def reduceToCanonicalAlias(text)
  puts "checking aliases for '#{text}'"
  for list in $aliases do
    canonicalAlias = list[0]
    for word in list do
      if text == word
        puts "found '#{canonicalAlias}'"
        return canonicalAlias
      end
    end
  end
  return text
end

def doTop(count)
  if (!count)
    count = 3
  end
  puts "getting top karma for '#{count}'"
  sth = $client.prepare("SELECT thing,points FROM `#{$tablename}` ORDER BY points DESC, thing ASC LIMIT #{count};")
  results = sth.execute()

  str = ""
  results.each_with_index do |row, rank|
    thing = "#{row['thing']}".force_encoding('utf-8').gsub('"','&quot;')
    str += "#{rank + 1}. \"#{thing}\" (#{row['points']}) "
  end
  return str

end

def doBottom(count)
  if (!count)
    count = 3
  end
  puts "getting bottom karma for '#{count}'"
  sth = $client.prepare("SELECT thing,points FROM `#{$tablename}` ORDER BY points ASC, thing ASC LIMIT #{count};")
  results = sth.execute()
  str = ""
  results.each_with_index do |row, rank|
    thing = "#{row['thing']}".force_encoding('utf-8').gsub('"','&quot;')
    str += "#{rank + 1}. \"#{thing}\" (#{row['points']}) "
  end
  return str
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

def updateKarma(text, user, isSlack)
  regexp = /(([^()\-+\s]+)|\(([^)]+)\))(\+\+|--)/
  matches = text.scan(regexp)
  user = canonicalizeText(user, isSlack)

  if(matches.length == 0)
    return false
  end

  matches.each do |match|
    amt = (match[3]=='++' ? 1 : match[3]=='--' ? -1 : 0)
    thing = match[1] ? match[1] : match[2]
    thing = canonicalizeText(thing, isSlack)
    if (amt && thing)
      if (thing == user)
        adjustKarmaInDB(user, -1)
        return "#{user}-- for attempting to modify own karma"
      else
        adjustKarmaInDB(thing, amt)
      end
    end
  end

  return true
end

########## SLACK ##########

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

def handleChange(text, channel, user)
  ret = updateKarma(text, user, true)
  if (ret)
    sendMessage(ret,channel)
  end
  return true
end

def fetchKarma(text)
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
  return doKarma(text, true)
end

def fetchTop(text)
  count = 3
  m = text.match(/^!top(?<count>\d+)/)
  if (m)
    count = m[:count].to_i
  end

  return doTop(count)
end

def fetchBottom(text)
  count = 3
  m = text.match(/^!bottom(?<count>\d+)/)
  if (m)
    count = m[:count].to_i
  end
  return doBottom(count)
end

def handleFetch(text,channel,user)
  str = ""
  if(text.match(/^!karma\b/))
    str = fetchKarma(text)
  elsif(text.match(/^!top/))
    str = fetchTop(text)
  elsif(text.match(/^!bottom/))
    str = fetchBottom(text)
  else
    return false
  end

  if(str != "")
    sendMessage(str,channel)
    return true
  end

  return false
end

def replaceUIDWithSlackUname(strWithUID)
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
  $curApp = 'slack'

  channel = req["event"]["channel"]
  text = req["event"]["text"]
  user = replaceUIDWithSlackUname(req["event"]["user"])

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

########## DISCORD ##########
$bot = Discordrb::Bot.new(token: $discordToken, intents: :all)

def initDiscordTable() 
  curtime = Time.now.to_i
  # Reconnect to the db every 5 minutes
  if ($curApp != 'discord' or (curtime - $dbLastConnected > 500)) 
    $client = Mysql2::Client.new(host: "localhost", username: $dbUser, password: $dbToken, database: $dbName)
    $tablename = $discordTableName
    $curApp = 'discord'
  end
  $dbLastConnected = curtime
end

$bot.register_application_command(:karma, 'Check the karma of something (if not specified, will check your karma!)', server_id: ENV.fetch($discordServerId, nil)) do |cmd|
  cmd.string('item', 'item(s) to check')
end

$bot.register_application_command(:top, 'List the top n karmas (default 3)', server_id: ENV.fetch($discordServerId, nil)) do |cmd|
  cmd.integer('n', 'top N')
end

$bot.register_application_command(:bottom, 'List the bottom n karmas (default 3)', server_id: ENV.fetch($discordServerId, nil)) do |cmd|
  cmd.integer('n', 'bottom N')
end

$bot.application_command(:karma) do |event|
  initDiscordTable()
  item = event.options['item']
  if not item 
    item = event.user.username
  end
  event.respond(content: doKarma(item, false))
end

$bot.application_command(:top) do |event|
  initDiscordTable()
  event.respond(content: doTop(event.options['n']))
end

$bot.application_command(:bottom) do |event|
  initDiscordTable()
  event.respond(content: doBottom(event.options['n']))
end

$bot.message do |event|
  initDiscordTable()
  ret = updateKarma(event.message.content, event.user.username, false)
  if (ret.instance_of? String)
    event.respond(ret)
  end
end
