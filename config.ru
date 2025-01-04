# encoding: UTF-8
require './karmabot'

Thread.new do
  puts "Starting bot"
  $bot.run
  puts "Bot stopped"
end

puts "Starting web server"
run Sinatra::Application
