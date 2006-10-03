var sortOrder = '';
var sortKey = '';
var listFilter = 'view_today';

var currentDay = '';
var currentView = 'dayview';

var cachedDateSelectors = new Array();

function newEvent(sender) {
  var day = sender.getAttribute("day");
  if (!day)
    day = currentDay;

  var hour = sender.getAttribute("hour");
  var urlstr = (ApplicationBaseURL + "new"
                + "?day=" + day
                + "&hm=" + hour);

  window.open(urlstr, "",
	      "width=570,height=200,resizable=0,scrollbars=0,toolbar=0," +
	      "location=0,directories=0,status=0,menubar=0,copyhistory=0");

  return false; /* stop following the link */
}

function _editEventId(id) {
  var urlstr = ApplicationBaseURL + id + "/edit";

  var win = window.open(urlstr, "SOGo_edit_" + id,
                        "width=570,height=200,resizable=0,scrollbars=0,toolbar=0," +
                        "location=0,directories=0,status=0,menubar=0,copyhistory=0");
  win.focus();
}

function editEvent() {
  var list = $("appointmentsList");
  var nodes = list.getSelectedRowsId();

  if (nodes.length > 0)
    _editEventId(nodes[0]);

  return false; /* stop following the link */
}

function deleteEvent() {
  var list = $("appointmentsList");
  var nodes = list.getSelectedRowsId();

  if (nodes.length > 0) {
    if (confirm(labels["appointmentDeleteConfirmation"])) {
      var urlstr = ApplicationBaseURL + nodes[0] + "/delete";
      document.deleteEventAjaxRequest = triggerAjaxRequest(urlstr,
                                                           deleteEventCallback,
                                                           nodes[0]);
    }
  }

  return false;
}

function deleteEventCallback(http)
{
  if (http.readyState == 4
      && http.status == 200) {
    document.deleteEventAjaxRequest = null;
    var node = $(http.callbackData);
    log ("deleteEventCallback: " + node);
    node.parentNode.removeChild(node);
  }
  else
    log ("ajax fuckage");
}

function editDoubleClickedEvent(node)
{
  var id = node.getAttribute("id");
  _editEventId(id);
  
  return false;
}

function onSelectAll() {
  var list = $("appointmentsList");
  list.selectRowsMatchingClass("appointmentRow");

  return false;
}

function displayAppointment(event, sender) {
  _editEventId(sender.getAttribute("aptId"));

  event.cancelBubble = true;
  event.returnValue = false;
}

function onContactRefresh(node)
{
  var parentNode = node.parentNode;
  var contacts = '';
  var done = false;

  var currentNode = parentNode.firstChild;
  while (currentNode && !done)
    {
      if (currentNode.nodeType == 1
          && currentNode.getAttribute("type") == "hidden")
        {
          contacts = currentNode.value;
          done = true;
        }
      else
        currentNode = currentNode.nextSibling;
    }

  log ('contacts: ' + contacts);
  if (contacts.length > 0)
    window.location = ApplicationBaseURL + '/show?userUIDString=' + contacts;

  return false;
}

function onDaySelect(node)
{
  var day = node.getAttribute("day");

  var td = node.getParentWithTagName("td");
  var table = td.getParentWithTagName("table");

//   log ("table.selected: " + table.selected);

  if (document.selectedDate)
    deselectNode(document.selectedDate);

  selectNode(td);
  document.selectedDate = td;

  changeCalendarDisplay(day);
  if (listFilter == 'view_selectedday')
    refreshAppointments();

  return false;
}

function onDateSelectorGotoMonth(node)
{
  var day = node.getAttribute("date");

  changeDateSelectorDisplay(day, true);

  return false;
}

function onCalendarGotoDay(node)
{
  var day = node.getAttribute("date");

  changeDateSelectorDisplay(day);
  changeCalendarDisplay(day);

  return false;
}

function gotoToday()
{
  changeDateSelectorDisplay('');
  changeCalendarDisplay();

  return false;
}

function setDateSelectorContent(content)
{
  var div = $("dateSelectorView");

  div.innerHTML = content;
  if (currentDay.length > 0)
    restoreCurrentDaySelection(div);
}

function dateSelectorCallback(http)
{
  if (http.readyState == 4
      && http.status == 200) {
    document.dateSelectorAjaxRequest = null;
    var content = http.responseText;
    setDateSelectorContent(content);
    cachedDateSelectors[http.callbackData] = content;
  }
  else
    log ("ajax fuckage");
}

function appointmentsListCallback(http)
{
  var div = $("appointmentsListView");

  if (http.readyState == 4
      && http.status == 200) {
    document.dateSelectorAjaxRequest = null;
    div.innerHTML = http.responseText;
    var params = parseQueryParameters(http.callbackData);
    sortKey = params["sort"];
    sortOrder = params["desc"];
  }
  else
    log ("ajax fuckage");
}

function restoreCurrentDaySelection(div)
{
  var elements = div.getElementsByTagName("a");
  var day = null;
  var i = 7;
  while (!day && i < elements.length)
    {
      day = elements[i].getAttribute("day");
      i++;
    }

  if (day
      && day.substr(0, 6) == currentDay.substr(0, 6))
    {
      for (i = 0; i < elements.length; i++) {
        day = elements[i].getAttribute("day");
        if (day && day == currentDay) {
          var td = elements[i].getParentWithTagName("td");
          if (document.selectedDate)
            deselectNode(document.selectedDate);
          selectNode(td);
          document.selectedDate = td;
        }
      }
    }
}

function changeDateSelectorDisplay(day, keepCurrentDay)
{
  var url = ApplicationBaseURL + "dateselector";
  if (day)
    url += "?day=" + day;

  if (day != currentDay) {
    if (!keepCurrentDay)
      currentDay = day;

    var month = day.substr(0, 6);
    if (cachedDateSelectors[month]) {
      log ("restoring cached selector for month: " + month);
      setDateSelectorContent(cachedDateSelectors[month]);
    }
    else {
      log ("loading selector for month: " + month);
      if (document.dateSelectorAjaxRequest) {
        document.dateSelectorAjaxRequest.aborted = true;
        document.dateSelectorAjaxRequest.abort();
      }
      document.dateSelectorAjaxRequest
        = triggerAjaxRequest(url,
                             dateSelectorCallback,
                             month);
    }
  }
}

function changeCalendarDisplay(day, newView)
{
  var url = ApplicationBaseURL + ((newView) ? newView : currentView);

  if (!day)
    day = currentDay;
  if (day)
    url += "?day=" + day;

  if (newView)
    log ("switching to view: " + newView);
//   log ("changeCalendarDisplay: " + url);

  if (document.dayDisplayAjaxRequest) {
//     log ("aborting day ajaxrq");
    document.dayDisplayAjaxRequest.aborted = true;
    document.dayDisplayAjaxRequest.abort();
  }
  document.dayDisplayAjaxRequest = triggerAjaxRequest(url,
                                                      calendarDisplayCallback,
                                                      { "view": newView,
                                                        "day": day });

  return false;
}

function _ensureView(view) {
  if (currentView != view)
    changeCalendarDisplay(null, view);

  return false;
}

function onDayOverview()
{
  return _ensureView("dayview");
}

function onWeekOverview()
{
  return _ensureView("weekview");
}

function onMonthOverview()
{
  return _ensureView("monthview");
}

function scrollDayViewTo8()
{
  var calContent = $("calendarContent");
  var tables = calContent.getElementsByTagName("table");
  if (tables.length > 0) {
    var row = tables[0].rows[9];
    var cell = row.cells[1];

    calContent.scrollTop = cell.offsetTop;
  }
}

function calendarDisplayCallback(http)
{
  var div = $("calendarView");

//   log ("calendardisplaycallback: " + div);
  if (http.readyState == 4
      && http.status == 200) {
    document.dateSelectorAjaxRequest = null;
    div.innerHTML = http.responseText;
    if (http.callbackData["view"])
      currentView = http.callbackData["view"];
    if (http.callbackData["day"])
      currentDay = http.callbackData["day"];
    scrollDayViewTo8();
  }
  else
    log ("ajax fuckage");
}

function assignCalendar(name)
{
  var node = $(name);

  node.calendar = new skycalendar(node);
  node.calendar.setCalendarPage(ResourcesURL + "/skycalendar.html");
  var dateFormat = node.getAttribute("dateFormat");
  if (dateFormat)
    node.calendar.setDateFormat(dateFormat);
}

function popupCalendar(node)
{
  var nodeId = node.getAttribute("inputId");
  var input = $(nodeId);
  input.calendar.popup();

  return false;
}

function onAppointmentContextMenu(event, element)
{
  var topNode = $('appointmentsList');
  log(topNode);

  var menu = $('appointmentsListMenu');

  menu.addEventListener("hideMenu", onAppointmentContextMenuHide, false);
  onMenuClick(event, 'appointmentsListMenu');

  var topNode = $('appointmentsList');
  var selectedNodes = topNode.getSelectedRows();
  topNode.menuSelectedRows = selectedNodes;
  for (var i = 0; i < selectedNodes.length; i++)
    deselectNode (selectedNodes[i]);

  topNode.menuSelectedEntry = element;
  selectNode(element);
}

function onAppointmentContextMenuHide(event)
{
  var topNode = $('appointmentsList');

  if (topNode.menuSelectedEntry) {
    deselectNode(topNode.menuSelectedEntry);
    topNode.menuSelectedEntry = null;
  }
  if (topNode.menuSelectedRows) {
    var nodeIds = topNode.menuSelectedRows;
    for (var i = 0; i < nodeIds.length; i++) {
      var node = $(nodeIds[i]);
      selectNode (node);
    }
    topNode.menuSelectedRows = null;
  }
}

function onAppointmentsSelectionChange()
{
}

function _loadAppointmentHref(href) {
  if (document.appointmentsListAjaxRequest) {
    document.appointmentsListAjaxRequest.aborted = true;
    document.appointmentsListAjaxRequest.abort();
  }
  url = ApplicationBaseURL + href;

  document.appointmentsListAjaxRequest
    = triggerAjaxRequest(url, appointmentsListCallback, href);

  return false;
}

function onHeaderClick(node)
{
  return _loadAppointmentHref(node.getAttribute("href"));
}

function refreshAppointments() {
  return _loadAppointmentHref("aptlist?desc=" + sortOrder
                              + "&sort=" + sortKey
                              + "&day=" + currentDay
                              + "&filterpopup=" + listFilter);
}

function onListFilterChange() {
  var node = $("filterpopup");

  listFilter = node.value;
//   log ("listFilter = " + listFilter);

  return refreshAppointments();
}

function onAppointmentClick(event)
{
  var node = event.target.getParentWithTagName("tr");
  var day = node.getAttribute("day");

  changeCalendarDisplay(day);
  changeDateSelectorDisplay(day);

  return onRowClick(event);
}

function selectMonthInMenu(menu, month)
{
  var entries = menu.childNodes[1].childNodes;
  for (i = 0; i < entries.length; i++) {
    var entry = entries[i];
    if (entry instanceof HTMLLIElement) {
      var entryMonth = entry.getAttribute("month");
      if (entryMonth == month)
        entry.addClassName("currentMonth");
      else
        entry.removeClassName("currentMonth");
    }
  }
}

function selectYearInMenu(menu, month)
{
  var entries = menu.childNodes[1].childNodes;
  for (i = 0; i < entries.length; i++) {
    var entry = entries[i];
    if (entry instanceof HTMLLIElement) {
      var entryMonth = entry.innerHTML;
      if (entryMonth == month)
        entry.addClassName("currentMonth");
      else
        entry.removeClassName("currentMonth");
    }
  }
}

function popupMonthMenu(event, menuId)
{
  var node = event.target;

  if (event.button == 0) {
    event.cancelBubble = true;
    event.returnValue = false;

    if (document.currentPopupMenu)
      hideMenu(event, document.currentPopupMenu);

    var popup = $(menuId);
    var id = node.getAttribute("id");
    if (id == "monthLabel")
      selectMonthInMenu(popup, node.getAttribute("month"));
    else
      selectYearInMenu(popup, node.innerHTML);

    var diff = (popup.offsetWidth - node.offsetWidth) /2;

    popup.style.top = (node.offsetTop + 95) + "px";
    popup.style.left = (node.offsetLeft - diff) + "px";
    popup.style.visibility = "visible";

    bodyOnClick = "" + document.body.getAttribute("onclick");
    document.body.setAttribute("onclick", "onBodyClick('" + menuId + "');");
    document.currentPopupMenu = popup;
  }
}

function onMonthMenuItemClick(node)
{
  var month = '' + node.getAttribute("month");
  var year = '' + $("yearLabel").innerHTML;
  
  changeDateSelectorDisplay(year+month+"01", true);

  return false;
}

function onYearMenuItemClick(node)
{
  var month = '' + $("monthLabel").getAttribute("month");;
  var year = '' + node.innerHTML;

  changeDateSelectorDisplay(year+month+"01", true);

  return false;
}

function onSearchFormSubmit()
{
  log ("search not implemented");

  return false;
}

function onCalendarSelectAppointment(event, node)
{
  var list = $("appointmentsList");
  list.deselectAll();

  var aptId = node.getAttribute("aptId");
  var row = $(aptId);
  if (row) {
    log ("row: " + row);
    selectNode(row);
  }

  event.cancelBubble = false;
  event.returnValue = false;
}

function onCalendarSelectDay(event, node)
{
  var day = node.getAttribute("day");

  changeDateSelectorDisplay(day);

  event.cancelBubble = true;
  event.returnValue = false;
}
