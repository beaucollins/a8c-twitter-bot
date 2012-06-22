irc      = require 'irc'
url      = require 'url'
express  = require 'express'
mongoose = require 'mongoose'
models   = require('./lib/models')(mongoose)
oauth    = require './lib/oauth'
twitter_watcher  = require './lib/twitter_watcher'
bot      = require './lib/bot'


username = process.env.NICK || 'twitterbot'
channel = process.env.CHANNEL || '#mobile-bot'
debug = process.env.DEBUG_NICK
host = process.env.HTTP_HOST || 'localhost:3000'

# Set up the Twitter oauth provider
provider = oauth key: process.env.TWITTER_OAUTH_KEY
               , secret: process.env.TWITTER_OAUTH_SECRET
               , callback: url.format(protocol:'http', host:host, pathname:"/auth/twitter_callback")
               , urls: {
                  request_token: "https://api.twitter.com/oauth/request_token"
                , authorize: "https://api.twitter.com/oauth/authorize"
                , access_token: "https://api.twitter.com/oauth/access_token"
               }




client = new irc.Client process.env.IRC_HOST
                      , username
                      , port: process.env.IRC_PORT
                      , channels: [channel]
                      , realName: "Mobile Team Twitter Bot"
                      , userName: username
                      , password: process.env.IRC_PASSWORD
                      , secure: (process.env.IRC_USE_SECURE == 'YES')
                      
# create the watcher service
watcher = new twitter_watcher.Service(provider)
watcher.on 'mention', (user, message)->
  u = "https://twitter.com/#{message.user.screen_name}/status/#{message.id_str}"
  client.say channel, "@#{message.user.screen_name}: #{message.text} -- #{u}"
  

mongoose.connect 'mongodb://localhost/twitter_irc'

models.Account.find (err, accounts)->
  accounts.forEach (account)->
    watcher.startWatching account
    

client.on 'command', (command, params, from, channel, text, message)->
  client.action debug, "Command: #{command} with params: #{params.join(', ')}" if debug?

client.on 'command.add', (command, params, from, channel)->
  oauth_client = provider.makeClient()
  callback_url = url.format protocol:'http', host:process.env.HOST || 'localhost:3000', pathname:'authorize'
  console.log "Requesting authorization key for", from
  client.say channel, "Requesting authorization key for #{from}"
  req = oauth_client.requestAuthorization callback:callback_url, (oauth_client)->
    client.say from, "Log in here: #{oauth_client.loginURL()}"
  req.on 'error', ()->
    client.say channel, "Could not get authorization key for #{from}. Is twitter down? https://dev.twitter.com/status"

client.on 'command.remove', (command, params, from, channel)->
  # remove the @
  screen_names = params.map (screen_name)->
    screen_name.replace(/^@/, '')
  
  models.Account.find screen_name:screen_names, (err, accounts)->
    removed_accounts = accounts.map (account)->
      account.remove()
      watcher.stopWatching account
      '@' + account.screen_name
    if removed_accounts.length > 0
      client.say channel, 'Stopped monitoring: ' + removed_accounts.join(', ')
    else
      client.say channel, "No accounts matching " + accounts.join(', ')

client.on 'command.status', (command, params, from, channel)->
  watcher.watchers.forEach (watcher)->
    client.say channel, "@" + watcher.user.screen_name + ": " + if watcher.active() then "monitoring" else "down"
    

# Receives message in channels you are in
client.on 'message', (from, channel, text, message)->
  text = text.trim()
  if channel == username and text.indexOf(username) != 0
    text = username + " " + text
  expression = new RegExp '^' + username + "([: ]+)?(.*)$"
  command = text.match expression
  if command and command[2]
    args = command[2].trim().toLowerCase().split(" ")
    name = args.slice(0, 1)
    params = args.slice(1)
    channel = from if channel == username
    client.emit 'command', name, params, from, channel, text, message
    client.emit "command.#{name}", name, params, from, channel, text, message
    

app = express()

app.get '/authorize', (req, res)->
  tw = provider.makeClient(token:req.param('oauth_token'))
  tw.verifyToken req.param('oauth_verifier'), (tw, params)->
    query = models.Account.update user_id:params.user_id, params, {upsert:true}, (err, count, info)->
      res.send "Success! Now monitoring: @#{params.screen_name}"
      watcher.startWatching params
      client.say channel, "Started monitoring @#{params.screen_name}"
      

app.listen process.env.PORT || 3000

console.log "Web server listening on", process.env.PORT || 3000