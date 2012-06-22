irc = require 'irc'
events = require 'events'

module.exports = (host, nick, options)->
  new Bot(host, nick, options)
  
class Bot extends events.EventEmitter
  constructor:(host, @nick, options)->
    @client = new irc.Client host, @nick, options
    @client.on 'message', @message.bind(this)
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
      available = @commands.slice()
      available.push @helpCommand()
      commands= available.reduce(
        (matches, command)->
          match = command.matcher(args)
          if match?
            matches.push command:command, args:match
          matches
        , []
      )
        
      if commands && commands[0]
        commands[0].command.action.call(this, from, channel, commands[0].args, args)
      else
        @say channel, "Don't know how to do that, #{from}, to see what I can do say: #{@client.nick}: help"
      
  command:(config)->
    # config.name display name
    # config.matcher RegExp or function that takes the raw text
    # config.help help to display for the command
    # config.action the callback that handles the command
    console.log "Add command", config.name
    
    @commands.push @prepareCommand(config)
    this
  prepareCommand:(config)->
    config.client = @client
    config.matcher ?= new RegExp("^" + config.name + "$", 'i')
    # if matcher is a regexp then turn it into a function
    if config.matcher.constructor == RegExp
      regex = config.matcher
      config.matcher = (text)->
        regex.exec(text)
    config
    
  helpCommand:()->
    @prepareCommand
      name: 'help',
      help: 'help :command',
      matcher: /^help(.*)$/i,
      action: (from, channel)->
        @say from, "Here are the things you can ask me to do:"
        @commands.forEach((command)->
          @say from, " * #{command.name} -- #{command.help}"
        , this)
      
    
  say:()->
    @client.say.apply(@client, arguments)
    
  

module.exports.Bot = Bot  
  