irc = require 'irc'
events = require 'events'

module.exports = (host, nick, options)->
  new Bot(host, nick, options)
  
class Bot extends events.EventEmitter
  constructor:(host, @nick, options)->
    @client = new irc.Client host, @nick, options
    @client.on 'message', this.message.bind(this)
    @commands = []
  message:(from, channel, text, message)->

    text = text.trim()
    if channel == @client.nick and text.indexOf(@client.nick) != 0
      text = @client.nick + " " + text
    channel = from if channel == @nick
        
    expression = new RegExp '^' + @client.nick + "([: ]+)?(.*)$"
    command = text.match expression
    if command and command[2]
      args = command[2].trim()
      commands= @commands.reduce(
        (matches, command)->
          console.log "Matches?", args, command.name
          match = command.matcher(args)
          if match?
            matches.push command:command, args:match
          matches
        , []
      )
        
      if commands && commands[0]
        commands[0].command.action.call(this, from, channel, commands[0].args, args)
      else
        this.say channel, "Don't know how to do that, #{from}"
      
  command:(config)->
    # config.name display name
    # config.matcher RegExp or function that takes the raw text
    # config.help help to display for the command
    # config.action the callback that handles the command
    config.client = @client
    config.matcher ?= new RegExp("^" + config.name + "$", 'i')
    if config.matcher.constructor == RegExp
      regex = config.matcher
      config.matcher = (text)->
        regex.exec(text)
    
    # if matcher is a regexp then turn it into a function
    console.log "set up", config.name, config.matcher
    @commands.push config
    this
  say:()->
    @client.say.apply(@client, arguments)
    
  

module.exports.Bot = Bot  
  