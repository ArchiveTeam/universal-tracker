if (process.argv.length != 3) {
    console.error("Specify the path of the environment.json file please!");
    console.error("Usage: node server.js environment.json");
    process.exit(2);
}

var fs = require('fs');
var env = JSON.parse(fs.readFileSync(process.argv[2]));

var trackerConfig = env['tracker_config'];

var app = require('http').createServer(httpHandler),
    io = require('socket.io').listen(app),
    redis = require('redis').createClient(Number(env['redis_port'] || 6379),
                                          env['redis_host'] || '127.0.0.1',
                                          Number(env['redis_db'] || 0)),
    numberOfClients = 0,
    recentMessages = {};

app.listen(8080);

redis.on("error", function (err) {
  console.log("Error " + err);
});

redis.on("message", redisHandler);

function httpHandler(request, response) {
  var m;
  if (m = request.url.match(/^\/recent\/(.+)/)) {
    var channel = m[1];
    response.writeHead(200, {"Content-Type": "text/plain; charset=UTF-8",
                             'Access-Control-Allow-Origin': '*',
                             'Access-Control-Allow-Credentials': 'true'});
    output = JSON.stringify(recentMessages[channel] || []);
    response.end(output);

  } else {
    response.writeHead(200, {"Content-Type": "text/plain"});
    output = "" + numberOfClients;
    response.end(output);
  }
}

function redisHandler(pubsubChannel, message) {
  console.log(message);
  var msgParsed = JSON.parse(message);
  console.log(msgParsed);
  var channel = msgParsed['log_channel'];
  if (!recentMessages[channel]) {
    recentMessages[channel] = [];
  }
  var msgList = recentMessages[channel];
  msgList.push(msgParsed);
  while (msgList.length > 20) {
    msgList.shift();
  }
  io.of('/'+channel).emit('log_message', message);
}


io.configure(function() {
  io.set("transports", ["websocket", "xhr-polling"]);
  io.set("polling duration", 10);

  var path = require('path');
  var HTTPPolling = require(path.join(
    path.dirname(require.resolve('socket.io')),'lib', 'transports','http-polling')
  );
  var XHRPolling = require(path.join(
    path.dirname(require.resolve('socket.io')),'lib','transports','xhr-polling')
  );

  XHRPolling.prototype.doWrite = function(data) {
    HTTPPolling.prototype.doWrite.call(this);

    var headers = {
      'Content-Type': 'text/plain; charset=UTF-8',
      'Content-Length': (data && Buffer.byteLength(data)) || 0
    };

    if (this.req.headers.origin) {
      headers['Access-Control-Allow-Origin'] = '*';
      if (this.req.headers.cookie) {
        headers['Access-Control-Allow-Credentials'] = 'true';
      }
    }

    this.response.writeHead(200, headers);
    this.response.write(data);
    // this.log.debug(this.name + ' writing', data);
  };
});

io.sockets.on('connection', function(socket) {
  numberOfClients++;
  socket.on('disconnect', function() {
    numberOfClients--;
  });
});


if (env['redis_password']) {
  redis.auth(env['redis_password']);
}
redis.subscribe(trackerConfig['redis_pubsub_channel']);

