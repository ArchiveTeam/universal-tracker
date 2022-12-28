import io from 'socket.io';
import redis from 'redis';

import { createServer } from 'http';
import { readFileSync } from 'fs';

import HTTPPolling from 'socket.io/lib/transports/http-polling.js';
import XHRPolling from 'socket.io/lib/transports/xhr-polling.js';

const httpHandler = async (request, response) => {
  let m;
  let output;

  if (m = request.url.match(/^\/recent\/(.+)/)) {
    let channel = m[1];
    response.writeHead(200, {
      "Content-Type": "text/plain; charset=UTF-8",
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Credentials': 'true'
    });
    output = JSON.stringify(recentMessages[channel] || []);

  } else {
    response.writeHead(200, {"Content-Type": "text/plain"});
    output = "" + numberOfClients;
  }

  response.end(output);
}

if (process.argv.length != 3) {
    console.error("Specify the path of the environment.json file please!");
    console.error("Usage: node server.js environment.json");
    process.exit(2);
}

const env = JSON.parse(readFileSync(process.argv[2])),
      trackerConfig = env['tracker_config'];

const app = createServer(httpHandler),
    ioApp = io.listen(app),
    redisClient = redis.createClient(Number(env['redis_port'] || 6379),
                                          env['redis_host'] || '127.0.0.1',
                                          Number(env['redis_db'] || 0)),
    recentMessages = {};

await redisClient.connect();
if (env['redis_password']) {
  await redisClient.auth(env['redis_password']);
}

var numberOfClients = 0;

app.listen(8080);

ioApp.configure(function () {
  ioApp.set("transports", ["websocket", "xhr-polling"]);
  ioApp.set("polling duration", 10);
  ioApp.set("log level", 2); // INFO

  XHRPolling.prototype.doWrite = function (data) {
    HTTPPolling.prototype.doWrite.call(this);

    const headers = {
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
  };
});

ioApp.sockets.on('connection', function (socket) {
  numberOfClients++;
  socket.on('disconnect', function () {
    numberOfClients--;
  });
});

const subscriber = redisClient.duplicate();
await subscriber.connect();

await subscriber.subscribe(trackerConfig['redis_pubsub_channel'], (message, channel) => {
  const msgParsed = JSON.parse(message);
  const logChannel = msgParsed['log_channel'];
  if (!recentMessages[logChannel]) {
    recentMessages[logChannel] = [];
  }
  const msgList = recentMessages[logChannel];
  msgList.push(msgParsed);
  while (msgList.length > 20) {
    msgList.shift();
  }
  ioApp.of('/' + logChannel).emit('log_message', message);
});

redisClient.on("error",  (err) => {
  console.error("redis error ", err);
});
