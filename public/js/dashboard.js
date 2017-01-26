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
        span2.innerHTML = '&#8226;';
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

  function toggleShowAll() {
    var showAll = ((''+location.hash).match('show-all'));
    if (showAll) {
      location.hash = '#';
    } else {
      location.hash = '#show-all';
    }
    redrawStats();
    updateChart();
    return false;
  }

  function redrawStats() {
    var showAll = ((''+location.hash).match('show-all'));

    var div, table, tbody, tfoot, tr, td, span;

    var div = document.createElement('div');

    table = document.createElement('table');
    table.className = 'items-count';
    tbody = document.createElement('tbody');
    tr = document.createElement('tr');
    tr.appendChild(makeTD('text', 'items'));

    td = document.createElement('td');
    td.className = 'num';
    tr.appendChild(td);

    span = document.createElement('span');
    span.className = 'value';
    span.innerHTML = stats.counts.done;
    td.appendChild(span);
    span = document.createElement('span');
    span.className = 'unit';
    span.innerHTML = 'done';
    td.appendChild(span);

    if (stats.counts.out > 0) {
      td.appendChild(document.createTextNode(' + '));

      span = document.createElement('span');
      span.className = 'value';
      span.innerHTML = stats.counts.out;
      td.appendChild(span);
      span = document.createElement('span');
      span.className = 'unit';
      span.innerHTML = 'out';
      td.appendChild(span);
    }

    td.appendChild(document.createTextNode(' + '));

    span = document.createElement('span');
    span.className = 'value';
    span.innerHTML = stats.counts.todo;
    td.appendChild(span);
    span = document.createElement('span');
    span.className = 'unit';
    span.innerHTML = 'to do';
    td.appendChild(span);

    tbody.appendChild(tr);
    table.appendChild(tbody);
    div.appendChild(table);

    table = document.createElement('table');
    tbody = document.createElement('tbody');
    var domain_count = 0;
    for (var domain in stats.domain_bytes) {
      if (trackerConfig.domains[domain]) {
        domain_count += 1;
        tr = document.createElement('tr');
        tr.appendChild(makeTD('text', trackerConfig.domains[domain]));
        tr.appendChild(makeTD('num',
                              Math.round(stats.domain_bytes[domain]/(1024*1024*1024)),
                              'GB'));
        tr.appendChild(makeTD('num',
                              Math.round((stats.domain_bytes[domain]/stats.counts.done)/(1024*1024)),
                              'MB/u'));
        tbody.appendChild(tr);
      }
    }
    table.appendChild(tbody);

    if (domain_count > 1) {
      tfoot = document.createElement('tfoot');
      tr = document.createElement('tr');
      tr.appendChild(makeTD('text', 'total'));
      tr.appendChild(makeTD('num',
                            Math.round(stats.total_bytes/(1024*1024*1024)),
                            'GB'));
      tr.appendChild(makeTD('num',
                            Math.round((stats.total_bytes/stats.counts.done)/(1024*1024)),
                            'MB/u'));
      tfoot.appendChild(tr);
      table.appendChild(tfoot);
    }

    div.appendChild(table);

    var downloaders = stats.downloaders.sort(function(a, b) {
      return stats.downloader_bytes[b] - stats.downloader_bytes[a];
    });

    table = document.createElement('table');
    tbody = document.createElement('tbody');
    for (var i=0; i<downloaders.length && (showAll || i<trackerConfig.numberOfDownloaders); i++) {
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
                            'items'));
      tbody.appendChild(tr);
    }
    table.appendChild(tbody);
    div.appendChild(table);

    var a = document.createElement('a');
    a.innerHTML = showAll ? '&ndash; ' : '+ ';
    a.id = 'show-all';
    a.href = showAll ? '#' : '#show-all';
    a.onclick = toggleShowAll;
    span = document.createElement('span');
    span.innerHTML = showAll ? 'Show fewer' : 'Show all';
    a.appendChild(span);
    div.appendChild(a);

    var left = document.getElementById('left');
    left.parentNode.replaceChild(div, left);
    div.id = 'left';
  }

  var lastRedrawn = null;
  var downloaderSeries = {};
  function updateChart() {
    if (!chart) return;

    var downloaders = stats.downloaders.sort(function(a, b) {
      return stats.downloader_bytes[b] - stats.downloader_bytes[a];
    });

    chart.series[0].addPoint([ new Date() * 1, stats.counts.done ],
                             false, false, false);
    stats.items_done_rate.addPoint([ new Date() * 1, stats.counts.done ],
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
    stats.counts = msg.counts;
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
    if (msg.user_agent && msg.user_agent.match(/Warrior$/)) {
      tr.className = 'warrior';
    }
    var downloaderTd = makeTD('text', msg.downloader);
    var itemTextTd = makeTD('text', msg.item);
    var sizeText = msg.megabytes < 1 ? Math.round(msg.megabytes * 10) / 10 : Math.round(msg.megabytes);
    var sizeTd = makeTD('num',  sizeText, 'MB')
    downloaderTd.className = 'downloader';
    itemTextTd.title = msg.item;
    tr.appendChild(downloaderTd);
    tr.appendChild(itemTextTd);
    tr.appendChild(sizeTd);

    downloaderTd.title = '';

    if (msg.version) {
      downloaderTd.title = 'Version: '+msg.version;
    }
    if (msg.user_agent) {
      downloaderTd.title += ' | User Agent: '+msg.user_agent;
    }

    tbody.insertBefore(tr, tbody.firstChild);

    while (tbody.childNodes.length > trackerConfig.numberOfLogLines) {
      tbody.removeChild(tbody.childNodes[trackerConfig.numberOfLogLines]);
    }
  }

  function getLogHostURL() {
    if (document.location.protocol == 'http:') {
      return trackerConfig.logHost;
    } else {
      return trackerConfig.sslLogHost;
    }
  }

  function startLogClient() {
    var socket = io.connect(document.location.protocol+'//'+getLogHostURL()+'/'+trackerConfig.logChannel);
    socket.on("log_message", function(data) {
      var msg = JSON.parse(data);
      if (msg.downloader && msg.item && msg.megabytes) {
        addLog(msg);
        if (!msg.is_duplicate) {
          updateStats(msg);
        }
      }
    });
  }

  function initLog() {
    jQuery.getJSON(document.location.protocol+'//'+getLogHostURL()+'/recent/'+(trackerConfig.logChannel), function(messages) {
      for (var i=0; i<messages.length; i++) {
        var msg = messages[i];
        if (msg.downloader && msg.item && msg.megabytes) {
          addLog(msg);
        }
      }
      startLogClient();
    });
  }

  var chart = null;
  function buildChart() {
    var maxMinTimestamp = 0;
    if (stats.items_done_chart.length > 0) {
      maxMinTimestamp = Math.max(maxMinTimestamp, stats.items_done_chart[0][0] * 1000);
    }
    for (var i in stats.downloader_chart) {
      if (stats.downloader_chart[i].length > 0) {
        maxMinTimestamp = Math.max(maxMinTimestamp, stats.downloader_chart[i][0][0] * 1000);
      }
    }
    if (maxMinTimestamp == 0) {
      maxMinTimestamp = null;
    }

    var seriesData = stats.items_done_chart;
    for (var j=seriesData.length-1; j>=0; j--) {
      seriesData[j][0] *= 1000;
    }

    // take the hourly rate based on a moving interval of 10 minutes
    var diffSeries = new DifferenceSeries(trackerConfig.movingAverageInterval * 60000, 60 * 60000);
    for (var j=0; j<seriesData.length; j++) {
      diffSeries.addPoint(seriesData[j]);
    }
    stats.items_done_rate = diffSeries;

    // count MB/s based on a moving interval of 10 minutes
    diffSeries = new DifferenceSeries(trackerConfig.movingAverageInterval * 60000, 1000);
    var perDownloaderData = [], perDownloaderIndex = [];
    for (var i in stats.downloader_chart) {
      perDownloaderData.push(stats.downloader_chart[i]);
      perDownloaderIndex.push(0);
    }
    var sumBytes = 0;
    while (perDownloaderData.length > 0) {
      var minTime = null, minTimeIdx = null, j;
      for (j = perDownloaderData.length - 1; j>=0; j--) {
        var entry = perDownloaderData[j][perDownloaderIndex[j]];
        if (entry && (minTime == null || entry[0] <= minTime)) {
          minTime = entry[0];
          minTimeIdx = j;
        }
      }
      if (j < 0) break;
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
                title:{text:'items', style:{color:'#aaa'}},
                opposite:true,
                labels:{align:'right',x:0, y:-2},
                height: 200 },
              { min:0, maxPadding: -0.5,
                title:{text:'bytes/s', style:{color:'#000'}},
                labels:{align:'left',x:0,y:-2},
                height: 70, top: 260, offset: 0 },
              { min:0, maxPadding: -0.5,
                title:{text:'items/hour'},
                opposite:true,
                labels:{align:'right',x:0, y:-2},
                height: 70, top: 260, offset: 0 } ],
      series:[{ name:'items done',
                type: 'area',
                data: seriesData,
                color: '#aaa',
                fillColor: '#eee',
                shadow: false,
                marker: {enabled: false},
                yAxis: 1 },
              { name:'items/hour',
                type: 'spline',
                data: stats.items_done_rate.rateData,
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

    stats.items_done_rate.series = chart.series[1];
    stats.bytes_download_rate.series = chart.series[2];

    $(document.body).bind('click', handleDownloaderClick);
  }

  function refreshUpdateStatus() {
    if (!trackerConfig.updateStatusPath) return;

    jQuery.getJSON(trackerConfig.updateStatusPath, function(data) {
      if (data.current_version == null || data.current_version == '')
        return;

      var mustUpdate = [];
      for (var d in data.downloader_version) {
        if (data.downloader_version[d] < data.current_version) {
          mustUpdate.push(d);
        }
      }

      var p = document.getElementById("update-status");
      p.style.display = 'none';
      makeEmpty(p);

      if (mustUpdate.length > 0) {
        mustUpdate.sort();

        var sentence = data.current_version_update_message + ": " + mustUpdate.join(", ");
        p.appendChild(document.createTextNode(sentence));
        p.style.display = 'block';
      }
    });
  }

  var previousChartDataUrls = [];
  function handleCharts(newCharts) {
    if (!stats.downloader_chart) stats.downloader_chart = {};
    if (!stats.items_done_chart) stats.items_done_chart = [];
    if (!stats.items_done_chart) stats.items_done_chart = [];

    for (var d in newCharts.downloader_chart) {
      if (!stats.downloader_chart[d]) stats.downloader_chart[d] = [];
      stats.downloader_chart[d] = newCharts.downloader_chart[d].concat(stats.downloader_chart[d]);
    }
    stats.items_done_chart = newCharts.items_done_chart.concat(stats.items_done_chart);
    stats.bytes_done_chart = newCharts.bytes_done_chart.concat(stats.bytes_done_chart);

    if (newCharts.previous_chart_data_urls) {
      previousChartDataUrls.push.apply(previousChartDataUrls, newCharts.previous_chart_data_urls);
    }

    if (previousChartDataUrls.length > 0) {
      jQuery.getJSON(previousChartDataUrls.shift(), handleCharts);
    } else {
      buildChart();
      redrawStats();
      updateChart();
    }
  }

  var stats = null;
  jQuery.getJSON(trackerConfig.statsPath, function(newStats) {
    stats = newStats;

    redrawStats();

    initLog();

    if (trackerConfig.updateStatusPath) {
      refreshUpdateStatus();
      window.setInterval(function() { refreshUpdateStatus(); }, 60000);
    }

    jQuery.getJSON(trackerConfig.chartsPath, handleCharts);
  });

  $('#how-to-help-cue').click(function(e) {
    e.preventDefault();

    $('#how-to-help-cue').animate({height: "hide"});
    $('#how-to-help').animate({height: "show"});
  });

})(window.trackerConfig);

