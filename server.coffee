url      = require 'url'
express  = require 'express'
mongoose = require 'mongoose'
models   = require('./lib/models')(mongoose)
oauth    = require './lib/oauth'
twitter_watcher  = require './lib/twitter_watcher'
irc_bot  = require './lib/irc_bot'

mongoose.connect 'mongodb://localhost/twitter_irc'

username = process.env.NICK || 'twitterbot'
channel = process.env.CHANNEL || '#mobile-bot'
debug = process.env.DEBUG_NICK
host = process.env.HTTP_HOST || 'localhost:3000'
http_port = process.env.PORT || 3000

# Set up the Twitter oauth provider
provider = oauth key: process.env.TWITTER_OAUTH_KEY
               , secret: process.env.TWITTER_OAUTH_SECRET
               , callback: url.format(protocol:'http', host:host, pathname:"/auth/twitter_callback")
               , urls: {
                  request_token: "https://api.twitter.com/oauth/request_token"
                , authorize: "https://api.twitter.com/oauth/authorize"
                , access_token: "https://api.twitter.com/oauth/access_token"
               }

# create the watcher service
watcher = new twitter_watcher.Service(provider)

# start watching each account
models.Account.find (err, accounts)->
  accounts.forEach (account)->
    watcher.startWatching account

bot = irc_bot process.env.IRC_HOST
            , username
            , port: process.env.IRC_PORT
            , channels: [channel]
            , realName: "Mobile Team Twitter Bot"
            , userName: username
            , password: process.env.IRC_PASSWORD
            , secure: (process.env.IRC_USE_SECURE == 'YES')
            # , debug: true


watcher.on 'mention', (user, message)->
  u = "https://twitter.com/#{message.user.screen_name}/status/#{message.id_str}"
  bot.say channel, "@#{message.user.screen_name}: #{message.text} -- #{u}"

bot
  .command(
    name: 'status',
    description: 'displays monitoring status'
    action: (from, channel, args, text)->
      if watcher.watchers.length > 0
        watcher.watchers.forEach (watcher)->
          bot.say channel, "@" + watcher.user.screen_name + ": " + if watcher.active() then "monitoring" else "down"
      else
        bot.say channel, "Not monitoring anything"
  )
  .command(
    name: 'add',
    description: 'Create URL to authenticate a new twitter user to monitor, sent as private message to user who made the command',
    action: (from, channel, args, text)->
      oauth_client = provider.makeClient()
      callback_url = url.format protocol:'http', host:process.env.HOST || 'localhost:3000', pathname:'authorize'
      console.log "Requesting authorization key for", from
      bot.say channel, "Requesting authorization key for #{from}"
      req = oauth_client.requestAuthorization callback:callback_url, (oauth_client)->
        bot.say from, "Log in here: #{oauth_client.loginURL()}"
      req.on 'error', ()->
        bot.say channel, "Could not get authorization key for #{from}. Is twitter down? https://dev.twitter.com/status"
  )
  .command(
    name: 'remove'
    matcher: /^remove([\s]{1,}.*)?$/i,
    help: 'remove :screen_name',
    description: 'stop monitoring the specified twitter user',
    action: (fram, channel, args, text)->
      names = args[1]
      if names?
        screen_names = names.trim().split(',').map (screen_name)->
          screen_name.trim().replace(/^@/, '')
          
        models.Account.find screen_name:screen_names, (err, accounts)->
          removed_accounts = accounts.map (account)->
            account.remove()
            watcher.stopWatching account
            '@' + account.screen_name
          if removed_accounts.length > 0
            bot.say channel, 'Stopped monitoring: ' + removed_accounts.join(', ')
          else
            bot.say channel, "No accounts matching " + screen_names.join(', ')
        
      else
        bot.say channel, "Please give me a user to remove. Example: remove @BobaFett"
  )
  
web = express()

web.get '/authorize', (req, res)->
  tw = provider.makeClient(token:req.param('oauth_token'))
  tw.verifyToken req.param('oauth_verifier'), (tw, params)->
    query = models.Account.update user_id:params.user_id, params, {upsert:true}, (err, count, info)->
      res.send "Success! Now monitoring: @#{params.screen_name}"
      watcher.startWatching params
      bot.say channel, "Started monitoring @#{params.screen_name}"
      

web.listen http_port

console.log "Web server listening on", http_port

