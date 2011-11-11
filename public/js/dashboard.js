(function initDashboard(trackerConfig) {
  function makeEmpty(el) {
    while (el.firstChild) {
      el.removeChild(el.firstChild);
    }
  }

  function makeTD() {
    var td, span, span2;
    td = document.createElement('td');
    switch (arguments[0]) {
      case 'legend':
        span = document.createElement('span');
        span2 = document.createElement('span');
        span2.innerHTML = '&bullet;';
        span2.id = 'legend-'+arguments[1];
        span.appendChild(span2);
        span.className = 'text';
        span.appendChild(document.createTextNode(' '+arguments[1]));
        td.appendChild(span);
        break;

      case 'text':
        span = document.createElement('span');
        span.className = 'text';
        span.appendChild(document.createTextNode(arguments[1]));
        td.appendChild(span);
        break;

      case 'num':
        td.className = 'num';
        span = document.createElement('span');
        span.className = 'value';
        span.appendChild(document.createTextNode(arguments[1]));
        td.appendChild(span);
        span = document.createElement('span');
        span.className = 'unit';
        span.appendChild(document.createTextNode(arguments[2]));
        td.appendChild(span);
        break;
    }
    return td;
  }

  function redrawStats() {
    var div, table, tbody, tfoot, tr;

    var div = document.createElement('div');

    table = document.createElement('table');
    tbody = document.createElement('tbody');
    tr = document.createElement('tr');
    tr.appendChild(makeTD('text', 'users'));
    tr.appendChild(makeTD('num',
                          stats.total_users_done,
                          'done'));
    tr.appendChild(makeTD('num',
                          stats.total_users - stats.total_users_done,
                          'to do'));
    tbody.appendChild(tr);
    table.appendChild(tbody);
    div.appendChild(table);

    table = document.createElement('table');
    tbody = document.createElement('tbody');
    for (var domain in stats.domain_bytes) {
      if (trackerConfig.domains[domain]) {
        tr = document.createElement('tr');
        tr.appendChild(makeTD('text', trackerConfig.domains[domain]));
        tr.appendChild(makeTD('num',
                              Math.round(stats.domain_bytes[domain]/(1024*1024*1024)),
                              'GB'));
        tr.appendChild(makeTD('num',
                              Math.round((stats.domain_bytes[domain]/stats.total_users_done)/(1024*1024)),
                              'MB/u'));
        tbody.appendChild(tr);
      }
    }
    table.appendChild(tbody);

    tfoot = document.createElement('tfoot');
    tr = document.createElement('tr');
    tr.appendChild(makeTD('text', 'total'));
    tr.appendChild(makeTD('num',
                          Math.round(stats.total_bytes/(1024*1024*1024)),
                          'GB'));
    tr.appendChild(makeTD('num',
                          Math.round((stats.total_bytes/stats.total_users_done)/(1024*1024)),
                          'MB/u'));
    tfoot.appendChild(tr);
    table.appendChild(tfoot);
    div.appendChild(table);

    var downloaders = stats.downloaders.sort(function(a, b) {
      return stats.downloader_bytes[b] - stats.downloader_bytes[a];
    });

    table = document.createElement('table');
    tbody = document.createElement('tbody');
    for (var i=0; i<downloaders.length && i<trackerConfig.numberOfDownloaders; i++) {
      var downloader = downloaders[i];
      tr = document.createElement('tr');
      tr.appendChild(makeTD('legend', downloader));
      tr.appendChild(makeTD('num',
                            Math.round(stats.downloader_bytes[downloader]/(1024*1024*1024)),
                            'GB'));
      tr.appendChild(makeTD('num',
                            stats.downloader_count[downloader],
                            'users'));
      tbody.appendChild(tr);
    }
    table.appendChild(tbody);
    div.appendChild(table);

    var left = document.getElementById('left');
    left.parentNode.replaceChild(div, left);
    div.id = 'left';
  }

  var downloaderSeries = {};
  function updateChart() {
    var downloaders = stats.downloaders.sort(function(a, b) {
      return stats.downloader_bytes[b] - stats.downloader_bytes[a];
    });

    for (var i=0; i<downloaders.length && i<trackerConfig.numberOfDownloadersInGraph; i++) {
      var downloader = downloaders[i];
      var series = downloaderSeries[downloader];
      if (!series) {
        downloaderSeries[downloader] = series = chart.addSeries({'name':downloader, 'marker':{'enabled':false}, 'shadow':false});
        if (stats.downloader_chart[downloader]) {
          series.setData(stats.downloader_chart[downloader]);
        }
      }
      var span = document.getElementById('legend-'+downloader);
      if (span) {
        span.style.color = series.color;
      }
      series.addPoint([ new Date() * 1, stats.downloader_bytes[downloader]/(1024*1024*1024) ]);
    }
    chart.series[0].addPoint([ new Date() * 1, stats.total_users_done ]);
  }

  function updateStats(msg) {
    stats.total_users_done += 1;
    if (!stats.downloader_bytes[msg.downloader]) {
      stats.downloader_bytes[msg.downloader] = 0;
      stats.downloader_count[msg.downloader] = 0;
      stats.downloaders.push(msg.downloader);
    }
    stats.downloader_count[msg.downloader] += 1;
    for (var domain in msg.domain_bytes) {
      bytes = msg.domain_bytes[domain] * 1;
      if (!stats.domain_bytes[domain]) {
        stats.domain_bytes[domain] = 0;
      }
      stats.domain_bytes[domain] += bytes;
      stats.downloader_bytes[msg.downloader] += bytes;
    }
    redrawStats();
    updateChart();
  }

  function addLog(msg) {
    var tbody, tr;
    tbody = document.getElementById('log');

    tr = document.createElement('tr');
    tr.appendChild(makeTD('text', msg.downloader));
    tr.appendChild(makeTD('text', msg.username));
    tr.appendChild(makeTD('num',  Math.round(msg.megabytes), 'MB'));

    if (msg.version) {
      tr.title = 'Version: '+msg.version;
    }

    tbody.insertBefore(tr, tbody.firstChild);

    while (tbody.childNodes.length > trackerConfig.numberOfLogLines) {
      tbody.removeChild(tbody.childNodes[trackerConfig.numberOfLogLines]);
    }
  }

  function startLogClient() {
    var socket = io.connect('http://'+trackerConfig.logHost);
    socket.on(trackerConfig.logChannel, function(data) {
      var msg = JSON.parse(data);
      if (msg.downloader && msg.username && msg.megabytes) {
        addLog(msg);
        updateStats(msg);
      }
    });
  }

  function initLog() {
    jQuery.getJSON('http://'+(trackerConfig.logHost)+'/recent/'+(trackerConfig.logChannel), function(messages) {
      for (var i=0; i<messages.length; i++) {
        var msg = messages[i];
        if (msg.downloader && msg.username && msg.megabytes) {
          addLog(msg);
        }
      }
      startLogClient();
    });
  }

  var chart = null;
  function buildChart() {
    chart = new Highcharts.Chart({
      chart: {renderTo:'chart-container',zoomType:'xy'},
      title:{text:null},
      legend:{enabled:false},
      credits:{enabled:false},
      xAxis:{type:'datetime'},
      yAxis:[ { min:0,
                title:{text:'gigabytes per downloader'},
                labels:{align:'left',x:0,y:-2} },
              { min:0, title:{text:'users done'},
                opposite:true,
                labels:{align:'right',x:0, y:-2}} ],
      series:[{ name:'users done',
                type: 'area',
                data: stats.users_done_chart,
                color: '#aaa',
                fillColor: '#eee',
                shadow: false,
                marker: {enabled: false},
                yAxis: 1 }]
    });
  }

  var stats = null;
  jQuery.getJSON(trackerConfig.statsPath, function(newStats) {
    stats = newStats;

    buildChart();
    redrawStats();
    updateChart();

    initLog();
  });
})(window.trackerConfig);

