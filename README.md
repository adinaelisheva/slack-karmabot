# ![karmabot icon](pics/karma-icon.png) Karmabot
## An implementation of irc karmabot for slack and discord

### Usage
#### Basic usage
Karmabot is always listening! O_O It will detect any instance of `[word]++` or `[word]--` and adjust the score of that word accordingly.

#### Phrases and non-word characters
Karmabot will accept anything inside one layer of parentheses as a "word" to be scored. This includes spaces and other non-word characters. 

Eg:   
Valid usages:
```
> (i like cookies)++  
> (:^_^:)++
```

Not valid and won't do anything:
```
> ((troll)))++
```

#### Fetching scores
To find out scores, just send the bot any number of words or phrases in parentheses. If you don't specify anything to check, it'll return your own karma score.

_**Slack**_

Send the message `!karma` followed by the item(s) to be checked.

![score fetching example](pics/example.png)

_**Discord**_

Use the `/karma` command and enter the item(s) to be checked as an argument.

#### Fetching Top and Bottom Scores
You can list the top/bottom N scores using the top and bottom messages. These messages support an optional argument of N. If provided, N must be a positive integer. If not provided, N defaults to 3.

_**Slack**_

Send the message `!top[N]` or `!bottom[N]`

_**Discord**_

Use the commands `/top` and `/bottom`

### Setting it up on your own server

#### Prerequisites
1. Your own box
2. Ruby
3. A MySQL database

#### What to do
1. Fork this repo to your server. The main files you need are:
   
   a. The `tmp/` directory and `config.ru` for sinatra
   
   b. `karmabot.rb`
   
   c. `tokens.rb.SAMPLE` to copy (in step 4)

2. Set up the bot on your server
   
   a. [Create an app on your slack team(s)](https://api.slack.com/apps) called Karmabot (or whatever you want to call it!)
   
   b. Set up the app(s) to point to your server
   
   c. Give your app(s) the following permissions:  
![channels:history and chat:write:bot](pics/perms.png)
   
   d. Alternately, set up a bot on Discord following their instructions to do so and grab its tokens

3. Set up a db with tables for every slack team you're using the app on. The tables should have minimum these two columns:

   a. `thing`: a text field

   b. `points`: an int

4. Create a `tokens.rb` file that contains your db table names and app authentication tokens (copy tokens.rb.SAMPLE)
5. Install Bundler: `gem install bundler`
6. Install dependencies: `bundle install --deployment` (to develop, run `bundle install --path=vendor/bundle` instead)
7. Run the server: `bundle exec rackup -p$PORT -o$HOST config.ru` and you're good to go!
