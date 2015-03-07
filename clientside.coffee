bootstrap = require 'bootstrap-browserify'
Backbone = require 'backbone4000'
helpers = require 'helpers'
async = require 'async'
_ = window._ =  require 'underscore'
$ = require 'jquery-browserify'

lweb = require 'lweb3/transports/client/websocket'
queryProtocol = require 'lweb3/protocols/query'
channelProtocol = require 'lweb3/protocols/channel'


settings = 
    websockethost: window.location.protocol + "//" + window.location.host
    
env = { settings: settings}

window.env = env


waitDocument = (env,callback) -> $(document).ready -> callback()

initLogger = (env,callback) ->
    env.log = (text,data,taglist...) ->
        tags = {}
        _.map taglist, (tag) -> tags[tag] = true
        if tags.error then text = text.red
        if tags.error and _.keys(data).length then json = " " + JSON.stringify(msg.data) else json = ""
        console.log "-> " + _.keys(tags).join(', ') + " " + text + json

    env.wrapInit = (text, f) ->
        (callback) ->
            console.log '>', text
            
            f env, (err,data) ->
                    console.log '<', text, "DONE"
                    callback err,data
        
    env.log('logger', {}, 'init', 'ok')

    callback()

initCore = (env,callback) -> 
    env.lweb = new lweb.webSocketClient( host: env.settings.websockethost, verbose: false )
    env.lweb.addProtocol new queryProtocol.client( verbose: true )
    env.lweb.addProtocol new channelProtocol.client( verbose: true )
    callback()
    
initWebsocket = (env,callback) ->
    if env.lweb.attributes.socketIo.socket.connected then callback()
    else env.lweb.on 'connect', callback

initViews = (env,callback) ->
    callback()
    

init = (env,callback) ->
    initLogger env, -> 

        async.auto
            documentready: ((callback) -> waitDocument env, callback)
            views:       [ 'documentready', (callback) -> initViews env, callback ]
            core:        [ 'views', env.wrapInit "Initializing core...", initCore ]
            websocket:   [ 'core', env.wrapInit "Initializing connection...", initWebsocket ]

init env, (err,data) ->
    if err then env.log('clientside init failed', {}, 'init', 'fail', 'error');return
    env.log('clientside ready', {}, 'init', 'ok', 'completed')
