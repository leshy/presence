colors = require 'colors'
async = require 'async'
_ = require 'underscore'
helpers = require 'helpers'
Bacbone = require 'backbone4000'
collections = require 'collections/serverside'

lwebTcp = require 'lweb3/transports/server/tcp'
lwebWs = require 'lweb3/transports/server/websocket'

queryProtocol = require 'lweb3/protocols/query'
channelProtocol = require 'lweb3/protocols/channel'

ribcage = require 'ribcage'

settings =
    production: false
    module:
        db:
            name: 'presence'
            host: 'localhost'
            port: 27017
        express:
            port: 3005
            static: __dirname + '/static'
            views: __dirname + '/ejs'
            cookiesecret: helpers.rndid(30)


    probePort: 3131
    
    irc:
        nick: 'mamaPresence'
        pass: false
        channel: '#mamapresence'
        
    user: false


env = { settings: settings }

initRibcage = (env,callback) ->
    express = require 'express'
    ejslocals = require 'ejs-locals'
    connectmongodb = require 'connect-mongodb'

    env.settings.module.express.configure = ->
        env.app.engine 'ejs', ejslocals
        env.app.set 'view engine', 'ejs'
        env.app.set 'views', env.settings.module.express.views
        env.app.use express.compress()
        env.app.use express.favicon()
        env.app.use express.bodyParser()
        
        env.app.set 'etag', true
        env.app.set 'x-powered-by', false

        env.app.use env.app.router
        env.app.use express.static(env.settings.module.express.static)

        env.app.use (err, req, res, next) =>
            throw err
            env.log 'web request error', { error: util.inspect(err) }, 'error', 'http'
            console.error util.inspect(err)
            if not env.settings.production then res.send 500, util.inspect(err)
            else res.send 500, 'error 500'
            
    env.logres = (name, callback) ->
        (err,data) -> 
            if (err)
                env.log name + ' (' + colors.red(err) + ")", { error: err }, 'init', 'fail'
            else
                if data?.constructor isnt String then logStr="..." else logStr = " (" + colors.green(data) + ")"
                env.log name + logStr, {}, 'init', 'ok'
            callback(err,data)
            
    ribcage.init env, callback

initIrc = (env,callback) ->
    if not env.settings.irc.enabled then return callback()        
    irc = require 'irc'
    
    client = env.ircclient = new irc.Client env.settings.irc.server, env.settings.irc.nick,  { channels: [ env.settings.irc.channel ] }
    
    client.addListener 'join', ->
        if pass = env.settings.irc.nickpass then client.say('nickserv', "identify #{pass}")            
        client.say env.settings.irc.channel, "My body (v.#{env.version}) is ready"
                
        callback()            

initLweb = (env,callback) ->
    env.lweb = new lwebWs.webSocketServer http: env.http, verbose: false
    env.lweb.addProtocol new queryProtocol.serverServer verbose: false
    env.lweb.addProtocol new channelProtocol.serverServer verbose: false
    callback()

initModels = (env,callback) ->
    callback()

initRoutes = (env,callback) ->
    logreq = (req,res,next) ->
        host = req.socket.remoteAddress
        if host is "127.0.0.1" then if forwarded = req.headers['x-forwarded-for'] then host = forwarded
        env.log host + " " + req.method + " " + req.originalUrl, { level: 2, ip: host, headers: req.headers, method: req.method }, 'http', req.method, host
        next()

    env.app.use (req, res, next) -> 
      res.header("Access-Control-Allow-Origin", "*")
      res.header("Access-Control-Allow-Headers", "Origin, X-Requested-With, Content-Type, Accept")
      next()
    
    env.app.get '*', logreq
    env.app.post '*', logreq
    
    env.app.get '/', (req,res) ->
        res.render 'index', { title: 'mama - presence', version: env.version, production: env.settings.production }

    callback()

dropPrivileges = (env,callback) ->
    if not env.settings.user then return callback null, colors.magenta("WARNING: staying at uid #{process.getuid()}")

    user = env.settings.user
    group = env.settings.group or user
    try
        process.initgroups user, group
        process.setgid group
        process.setuid user
    catch err
        if err.code is 'EPERM' then return callback null, colors.magenta("WARNING: permission denied")
        else return callback err
    callback null, "dropped to " + user + "/" + group

initLweb = (env,callback) ->
    env.lweb = new lwebWs.webSocketServer http: env.http, verbose: false
    env.lweb.addProtocol new queryProtocol.serverServer verbose: false
    env.lweb.addProtocol new channelProtocol.serverServer verbose: true
    callback()

initIgnoreList = (env,callback) ->
    

initReader = (env,callback) ->
    env.probeListener = new lwebTcp.tcpServer
        port: settings.probePort, name: 'probe', verbose: true

        
    packet = (state,mac) ->
        if state is undefined or not mac then return
        if env.ignore[mac] then return

        console.log 'mac', mac, 'state', state
        
        env.lweb.channel('macs').broadcast mac: mac, state: state
        
    env.probeListener.on 'connect', (channel) -> 
        channel.subscribe true, (msg) ->
            _.map msg.split('\n'), (line) ->
                if not line then return
                [state, mac] = line.split(' ')
                packet Number(state), mac
        
    callback null, "port #{settings.probePort}"

initModels = (env,callback) ->
    env.ignore = {}
    env.db.log = new collections.MongoCollection collection: 'log', db: env.db
    env.logon = env.db.log.defineModel 'on', {}
    env.logoff = env.db.log.defineModel 'off', {}
    
    env.db.ignore = new collections.MongoCollection collection: 'ignore', db: env.db
    env.db.ignore.find {}, {}, ((err,entry) ->
        env.ignore[entry.mac] = true
    ), (err,data) ->
        console.log 'ignoring', env.ignore
        callback null, true

initWriter = (env,callback) ->
    callback null, true


init = (env,callback) ->
    async.auto
        ribcage: (callback) -> initRibcage env, callback
        irc: [ 'ribcage', (callback) -> initIrc env, env.logres('irc',callback) ]
        privileges: [ 'ribcage', (callback) -> dropPrivileges env, env.logres('drop user',callback) ]
        routes: [ 'ribcage', (callback) -> initRoutes env, env.logres('routes',callback) ]
        lweb: [ 'ribcage', (callback) -> initLweb env, env.logres('lweb', callback) ]
        models: [ 'ribcage', (callback) -> initModels env, env.logres('models',callback) ]
        reader: [ 'models', (callback) -> initReader env, env.logres('reader',callback) ]
        writer: [ 'ribcage', 'reader' , (callback) -> initWriter env, env.logres('writer',callback) ]
        callback

init env, (err,data) ->
    if err
        env.log(colors.red('my body is not ready, exiting'), {}, 'init', 'error' )
        process.exit 15
    else
        env.log('application running', {}, 'init', 'completed' )
        console.log colors.green('\n\n\t\t\tMy body is ready\n\n')

