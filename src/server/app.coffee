# required modules
_              = require "underscore"
fs             = require "fs"
async          = require "async"
http           = require "http"
express        = require "express"
path           = require "path"
methodOverride = require "method-override"
bodyParser     = require "body-parser"
socketio       = require "socket.io"
ioClient       = require "socket.io-client"
ss             = require "socket.io-stream"
errorHandler   = require "error-handler"
SoxCommand     = require "sox-audio"
sox            = require "sox-stream"

log            = require "./lib/log"

app          = express()
server       = http.createServer app
io           = socketio.listen server
# fixed location of service registry
servRegAddress = "http://localhost:3001"

SERVICE_NAME = "web-server"

# collection of client sockets
sockets = []

# websocket connection logic
io.on "connection", (socket) ->
  # add socket to client sockets
  sockets.push socket
  log.info "Socket connected, #{sockets.length} client(s) active"

  # TODO some kind of filter to pass on to the generators
  socket.on "setFilter", (filter) ->
    console.log filter

  # disconnect logic
  socket.on "disconnect", ->
    # remove socket from client sockets
    sockets.splice sockets.indexOf(socket), 1
    log.info "Socket disconnected, #{sockets.length} client(s) active"

# express application middleware
app
  .use bodyParser.urlencoded extended: true
  .use bodyParser.json()
  .use methodOverride()
  .use express.static path.resolve __dirname, "../client"

# express application settings
app
  .set "view engine", "jade"
  .set "views", path.resolve __dirname, "./views"
  .set "trust proxy", true

# express application routes
app
  .get "/", (req, res, next) ->
    res.render "main"

subCommand = (file) ->
  return SoxCommand()
    .input(file)
    .output('-p')
    .outputFileType('mp3')

app
  .get "/audiostream.mp3", (req, res) ->
    res.set
      'Content-Type': 'audio/mpeg3'
      'Transfer-Encoding': 'chunked'

    src1 = "/home/stofstik/Downloads/Comfort_Fit_-_03_-_Sorry.mp3"
    src2 = "/home/stofstik/Downloads/Kriss_-_03_-_jazz_club.mp3"
    soxCommand = SoxCommand()

    soxCommand.subCommandChainable = (files) ->
      for file in files
        this.inputSubCommand(subCommand(file))
      return this

    soxCommand
      .subCommandChainable([src1, src2], soxCommand)
      .output(res)
      .outputFileType('mp3')
      .outputChannels(1)
      .combine('merge')

    soxCommand.on "prepare", (args) ->
      console.log "preparing with #{args.join ' '}"

    soxCommand.on "start", (cmdline) ->
      console.log "spawned sox with cmd: #{cmdline}"

    soxCommand.on "error", (err, stdout, stderr) ->
      console.log "cannot process audio #{err.message}"
      console.log "sox command stdout #{stdout}"
      console.log "sox command stderr #{stderr}"

    soxCommand.run()

# connect to the service registry
serviceRegistry = ioClient.connect servRegAddress,
  "reconnection": true

# when we are connected to the registry start the web server
serviceRegistry.on "connect", (socket) ->
  log.info "service registry connected"
  server.listen 3000
  log.info "Listening on port", server.address().port

  # we want to subscribe to whatever person-generator emits
  serviceRegistry.emit "subscribe-to",
    name: "person-generator"
  serviceRegistry.emit "subscribe-to",
    name: "audio-streamer"

instances = []
audioStreams = []
# when a new service we are subscribed to starts, connect to it
serviceRegistry.on "service-up", (service) ->
  switch service.name
    when "person-generator"
      if(instances.indexOf(service.port) != -1)
        log.info "already connected"
        return
      instance = ioClient.connect "http://localhost:#{service.port}",
        "reconnection": false

      instance.on "connect", (socket) ->
        console.info "connected to, #{service.name}:#{service.port}"
        instances.push service.port

      instance.on "disconnect", (socket) ->
        console.info "disconnected from, #{service.name}:#{service.port}"
        instances.splice instances.indexOf(service.port), 1

      instance.on "data", (data) ->
        log.info data
        socket.emit "persons:create", data for socket in sockets

    when "audio-streamer"
      instance = ioClient.connect "http://localhost:#{service.port}",
        "reconnection": false

      instance.on "connect", (socket) ->
        console.info "connected to, #{service.name}:#{service.port}"
        instances.push service.port


    else
      log.info "unknown service, did we subscribe to that?"

# notify of service registry disconnect
serviceRegistry.on "disconnect", () ->
  log.info "service registry disconnected"
