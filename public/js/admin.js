(function() {

  function addLineToMap(p) {
    var table = $(p.target).prev('table');
    var fieldName = table.attr('data-fieldname');
    var tbody = table.children('tbody');
    var nTrs = $(tbody).children('tr').length;
    var tr = $(document.createElement('tr'));
    tr.append('<td><input type="text" name="'+fieldName+'-'+nTrs+'-key" value="" /></td><td><input type="text" name="'+fieldName+'-'+nTrs+'-value" value="" /></td>');
    tbody.append(tr);
    tr.find('input').first().focus();
  }

  $('#tracker-config table.map').each(function(index, table) {
    var p = document.createElement('P');
    p.className = 'add-line-to-map';
    p.innerHTML = 'Add line';
    $(table).after(p);
    $(p).bind('click', addLineToMap);
  });

})();
