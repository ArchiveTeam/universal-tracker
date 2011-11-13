(function initDashboard(trackerConfig) {
  function DifferenceSeries(periodDuration, unitDuration) {
    this.periodDuration = periodDuration;
    this.unitDuration = unitDuration;
    this.startOfPeriodIndex = null;
    this.data = [];
    this.rateData = [];
    this.series = null;
  }
  DifferenceSeries.prototype.addPoint = function(options, redraw, shift, animation) {
    var idx = this.startOfPeriodIndex,
        dur = this.periodDuration,
        data = this.data, n = data.length;
    if (idx != null && n > 1) {
      while (idx < n && data[idx][0] < options[0] - dur) {
        idx++;
      }
      idx = idx - 1;

      if (idx >= 0) {
        var prevPoint = data[idx];
        var timeDiff = options[0] - prevPoint[0];
        var valueDiff = options[1] - prevPoint[1];
        var rate = valueDiff / (timeDiff / this.unitDuration);
        if (this.series) {
          this.series.addPoint([ options[0], rate ], redraw, shift, animation);
        } else {
          this.rateData.push([ options[0], rate ]);
        }

        this.startOfPeriodIndex = idx + 1;
      }
    } else {
      this.startOfPeriodIndex = 0;
    }
    this.data.push(options);
  };

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
      tr.downloader = downloader;
      tr.style.cursor = 'pointer';
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

  var lastRedrawn = null;
  var downloaderSeries = {};
  function updateChart() {
    var downloaders = stats.downloaders.sort(function(a, b) {
      return stats.downloader_bytes[b] - stats.downloader_bytes[a];
    });

    chart.series[0].addPoint([ new Date() * 1, stats.total_users_done ],
                             false, false, false);
    stats.users_done_rate.addPoint([ new Date() * 1, stats.total_users_done ],
                                   false, false, false);
    stats.bytes_download_rate.addPoint([ new Date() * 1, stats.total_bytes ],
                                   false, false, false);

    for (var i=0; i<downloaders.length && i<trackerConfig.numberOfDownloadersInGraph; i++) {
      var downloader = downloaders[i];
      var series = downloaderSeries[downloader];
      if (!series) {
        var seriesData = [];
        if (stats.downloader_chart[downloader]) {
          seriesData = stats.downloader_chart[downloader];
          for (var j=seriesData.length-1; j>=0; j--) {
            seriesData[j][0] = seriesData[j][0] * 1000;
            seriesData[j][1] = seriesData[j][1] / (1024*1024*1024);
          }
        }
        seriesData.push([ new Date() * 1, stats.downloader_bytes[downloader]/(1024*1024*1024) ]);

        downloaderSeries[downloader] = series = chart.addSeries({'name':downloader,
                                                                 'marker':{'enabled':false},
                                                                 'shadow':false,
                                                                 'data':seriesData,
                                                                 stickyTracing: false
                                                                },
                                                                false, false);
      } else {
        series.addPoint([ new Date() * 1, stats.downloader_bytes[downloader]/(1024*1024*1024) ],
                        false, false, false);
      }

      var span = document.getElementById('legend-'+downloader);
      if (span) {
        span.style.color = series.color;
        span.style.visibility = series.visible ? 'visible' : 'hidden';
      }
    }

    if (lastRedrawn == null || new Date() - lastRedrawn > 30*1000) {
      lastRedrawn = new Date();
      chart.redraw();
    }
  }

  function handleDownloaderClick(evt) {
    var tr = evt.target;
    while (tr && tr.nodeName!='TR' && tr.parentNode) {
      tr = tr.parentNode;
    }
    if (tr && tr.nodeName=='TR' && tr.downloader) {
      var downloader = tr.downloader;
      if (downloaderSeries[downloader]) {
        var series = downloaderSeries[downloader];
        if (series.visible)
          series.hide();
        else
          series.show();

        var span = document.getElementById('legend-'+downloader);
        if (span) {
          span.style.visibility = series.visible ? 'visible' : 'hidden';
        }

        chart.series[0].hide();
        chart.series[0].show();
      }
    }
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
      stats.total_bytes += bytes;
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
    var socket = io.connect('http://'+trackerConfig.logHost+'/'+trackerConfig.logChannel);
    socket.on(trackerConfig.logChannel, function(data) {
      var msg = JSON.parse(data);
      if (msg.downloader && msg.username && msg.megabytes) {
        addLog(msg);
        if (!msg.is_duplicate) {
          updateStats(msg);
        }
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
    var maxMinTimestamp = 0;
    if (stats.users_done_chart.length > 0) {
      maxMinTimestamp = Math.max(maxMinTimestamp, stats.users_done_chart[0][0] * 1000);
    }
    for (var i in stats.downloader_chart) {
      if (stats.downloader_chart[i].length > 0) {
        maxMinTimestamp = Math.max(maxMinTimestamp, stats.downloader_chart[i][0][0] * 1000);
      }
    }
    if (maxMinTimestamp == 0) {
      maxMinTimestamp = null;
    }

    var seriesData = stats.users_done_chart;
    for (var j=seriesData.length-1; j>=0; j--) {
      seriesData[j][0] *= 1000;
    }

    // take the hourly rate based on a moving interval of 10 minutes
    var diffSeries = new DifferenceSeries(trackerConfig.movingAverageInterval * 60000, 60 * 60000);
    for (var j=0; j<seriesData.length; j++) {
      diffSeries.addPoint(seriesData[j]);
    }
    stats.users_done_rate = diffSeries;

    // count MB/s based on a moving interval of 10 minutes
    diffSeries = new DifferenceSeries(trackerConfig.movingAverageInterval * 60000, 1000);
    var perDownloaderData = [], perDownloaderIndex = [];
    for (var i in stats.downloader_chart) {
      perDownloaderData.push(stats.downloader_chart[i]);
      perDownloaderIndex.push(0);
    }
    var sumBytes = 0;
    while (perDownloaderData.length > 0) {
      var minTime = null, minTimeIdx = null;
      for (var j = perDownloaderData.length - 1; j>=0; j--) {
        var thisTime = perDownloaderData[j][perDownloaderIndex[j]][0];
        if (minTime == null || thisTime <= minTime) {
          minTime = thisTime;
          minTimeIdx = j;
        }
      }
      if (minTimeIdx != null) {
        if (perDownloaderIndex[minTimeIdx] > 0) {
          sumBytes -= perDownloaderData[minTimeIdx][perDownloaderIndex[minTimeIdx] - 1][1];
        }
        sumBytes += perDownloaderData[minTimeIdx][perDownloaderIndex[minTimeIdx]][1];
        diffSeries.addPoint([ minTime * 1000, sumBytes ]);
        perDownloaderIndex[minTimeIdx]++;
        if (perDownloaderIndex[minTimeIdx] >= perDownloaderData[minTimeIdx].length) {
          perDownloaderIndex.splice(minTimeIdx, 1);
          perDownloaderData.splice(minTimeIdx, 1);
        }
      }
    }
    stats.bytes_download_rate = diffSeries;

    chart = new Highcharts.StockChart({
      chart: {renderTo:'chart-container', zoomType:'x'},
      title:{text:null},
      legend:{enabled:false},
      credits:{enabled:false},
      rangeSelector: {
        buttons: [ {type:'day',  count:1,text: '1d'},
                   {type:'week', count:1,text: '1w'},
                   {type:'month',count:1,text: '1m'},
                   {type:'all',          text: 'all'} ]
      },
      xAxis:{type:'datetime'},
      yAxis:[ { min:0, maxPadding: 0,
                title:{text:'GB done'},
                labels:{align:'left',x:0,y:-2},
                height: 200 },
              { min:0, maxPadding: 0,
                title:{text:'users', style:{color:'#aaa'}},
                opposite:true,
                labels:{align:'right',x:0, y:-2},
                height: 200 },
              { min:0, maxPadding: -0.5,
                title:{text:'bytes/s', style:{color:'#000'}},
                labels:{align:'left',x:0,y:-2},
                height: 70, top: 260, offset: 0 },
              { min:0, maxPadding: -0.5,
                title:{text:'users/hour'},
                opposite:true,
                labels:{align:'right',x:0, y:-2},
                height: 70, top: 260, offset: 0 } ],
      series:[{ name:'users done',
                type: 'area',
                data: seriesData,
                color: '#aaa',
                fillColor: '#eee',
                shadow: false,
                marker: {enabled: false},
                yAxis: 1 },
              { name:'users/hour',
                type: 'spline',
                data: stats.users_done_rate.rateData,
                color: '#6D869F',
                shadow: false,
                marker: {enabled: false},
                yAxis: 3 },
              { name:'bytes/s',
                type: 'spline',
                data: stats.bytes_download_rate.rateData,
                color: '#000',
                shadow: false,
                marker: {enabled: false},
                yAxis: 2 }],
      tooltip: {
        crosshairs: false,
        shared: false,
        snap: 0
      }
    });

    stats.users_done_rate.series = chart.series[1];
    stats.bytes_download_rate.series = chart.series[2];

    $(document.body).bind('click', handleDownloaderClick);
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

