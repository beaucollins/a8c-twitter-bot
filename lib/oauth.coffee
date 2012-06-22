
# Options
#  secret
#  key
#  endpoints
module.exports = Oauth = (options)->
  new Oauth.Provider(options)

net = require 'net'
url = require 'url'
http = require 'https'
crypto = require 'crypto'
querystring = require 'querystring'

merge = (one, other)->
  merged = {}
  for k, v of one
    merged[k] = v
  for k, v of other
    merged[k] = v
  merged

Oauth.Provider = ( settings )->
  this.urls = settings.urls || {}
  this.key = settings.key
  this.secret = settings.secret
  provider = this
  this.makeClient = (options)->
    new Oauth.Client( options, this )
  # authorizes a session by setting up the authenticator
  # and determining the login status
  this.sessionAuthorizor = ()->
    self = this
    (req, res, next)->
      req.client = provider.makeClient(req.session.oauth)
      next()
  this
      
Oauth.Client = ( settings, provider )->
  # if we have a request token but no access_token we are still waiting for
  # the user to authorize our app
  settings = {} unless settings?
  this.settings = settings
  
  # token = settings.oauth_token || settings.token
  settings.token = settings.oauth_token if !settings.token?
  settings.token_secret = settings.oauth_token_secret if !settings.token_secret?
    
  # if we have an access token then we are authorized
  # token_secret = settings.oauth_secret_token || settings.token_secret
  client = this
  # we need to make a call to twitter to get a request token
  this.requestAuthorization = ( options, callback )->
    if typeof options == 'function'
      callback = options
      options = {}
    options.method = 'POST'
    this.request( provider.urls.request_token, options, (body)->
      token_properties = querystring.parse(body)
      settings.token = token_properties.oauth_token
      settings.token_secret = token_properties.oauth_token_secret
      callback( client, token_properties )
    )
  
  this.verifyToken = ( verifier, callback )->
    this.request( provider.urls.access_token, { body: {oauth_verifier: verifier} }, (body)->
      params = querystring.parse(body)
      settings.token = params.oauth_token
      settings.token_secret = params.oauth_token_secret
      settings.user_id = params.user_id
      settings.screen_name = params.screen_name
      callback( client, params )
    )
    
  
  this.loginURL = ()->
    provider.urls.authorize + "?oauth_token=" + settings.token
  
  this.isAuthenticated = ()->
    settings.token? and settings.token_secret? and settings.user_id? and settings.screen_name?
    # do we have a token?
  
  # options:
  #  method: default GET
  #  body: for POST/PUT requests
  this.request = ( u, options, callback )->
    if typeof options == 'function'
      callback = options
      options = {}
    
    u = url.parse(u)
    query = querystring.parse(u.query)
    
    options.body ?= {}
    
    u.method = options.method || 'GET'
    u.headers = options.headers || {}
    u.headers['User-Agent'] = "Stratweegery Twitter Client v2"
    u.headers['Authorization'] = this.makeAuthorizationHeader(u.method, u, merge(query, options.body), options)
    req = http.request u, (res)->
      if options.stream
        callback res
      else
        body = ""
        res.setEncoding('utf8')
        # body...
        res.on 'data', (data)->
          body += data
          
        res.on 'end', ()->
          callback body, res
            
    req.write(querystring.stringify(options.body)) if options.body?
    req.end()

    req
      
  # creates the oauthHeader
  this.makeAuthorizationHeader = (method, u, request_parameters, options)->
    options = {} unless options?
    ts = Math.round((new Date).getTime()/1000)
    
    oauth_properties=
      oauth_consumer_key: provider.key,
      oauth_nonce: createNonce(),
      oauth_signature_method: 'HMAC-SHA1',
      oauth_timestamp: ts,
      oauth_version:"1.0"
    
    oauth_properties['oauth_callback'] = options.callback if options.callback?
    oauth_properties['oauth_token'] = settings.token if settings.token?
    
    base_url = url.format({
      host: u.hostname,
      protocol: u.protocol,
      pathname: u.pathname
    })
    
    # if the base_url is the same as the provider request token resource then add the callback url
    
    parameters = []
    for k, v of merge(oauth_properties, request_parameters)
      parameters.push querystring.escape(k) + "=" + querystring.escape(v)
      
    parameter_string = parameters.sort().join("&")
    base_string = [ method.toUpperCase(), querystring.escape(base_url), querystring.escape(parameter_string)].join('&')
    signing_key = provider.secret + "&" + ( settings.token_secret ? '' )
    hmac = crypto.createHmac('sha1', signing_key)
    
    hmac.update(base_string)
    oauth_properties['oauth_signature'] = signature = hmac.digest('base64')
    
    oauth_header = []
    for k, v of oauth_properties
      oauth_header.push querystring.escape(k) + "=\"" + querystring.escape(v) + "\""
    
    "OAuth " + oauth_header.join(", ")
  
  createNonce = ()->
    crypto.randomBytes(32).toString('base64').replace(/[\W]/g,'')
  
  this

