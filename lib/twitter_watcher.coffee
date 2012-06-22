events = require 'events'

class Service extends events.EventEmitter
  constructor: (@provider)->
    @watchers = []

  startWatching: (credentials)->
    # screen_name, user_id, oauth_token, oauth_token_secret
    existing = this.watchersFor(credentials)
    if existing.length == 0
      watcher = new Watcher(credentials, this)
      @watchers.push watcher
      watcher.watch @provider
    else
      existing[0]
  stopWatching: (credentials)->
    @watchers = @watchers.filter (watcher)->
      if watcher.watching credentials
        watcher.close()
        false
      else
        true
    
  watchersFor: (credentials)->
    @watchers.filter (watcher)->
      watcher.watching(credentials)

class Watcher
  constructor: (@user, @service)->
  watch: (provider)->
      # body...
    self = this
    user = @user
    service = @service
    @client = provider.makeClient(@user)
    req = @client.request 'https://userstream.twitter.com/2/user.json', stream:true, (res)->
      self.response = res
      console.log user.screen_name, "Streaming", res.statusCode
      res.on 'data', (data)->
        data.toString().split(Watcher.LINE_SEPERATOR).forEach (data)->
          if data.trim() != ""
            try
              message = JSON.parse data
              if message.entities && message.entities.user_mentions.filter((mention)-> mention.id_str == user.user_id ).length > 0
                service.emit 'mention', user, message
            catch error
              console.error user.screen_name, error, data, data.toString(), data.length
          
      res.on 'end', ()->
        console.log user.screen_name, "Done Streaming"
        self.response = null
      res.on 'error', (e)->
        console.error e
        self.response = null
    req.on 'error', (e)->
      self.response = null
      console.log user.screen_name, "Streaming failed"
    this
  close: ()->
    if @response
      @response.destroy()
      @response = null
  watching: (user)->
    user.user_id == @user.user_id
  active: ()->
    @response?
    
Watcher.LINE_SEPERATOR = new Buffer([0x0D, 0x0A]);

module.exports = {
  Service: Service,
  Watcher: Watcher
}