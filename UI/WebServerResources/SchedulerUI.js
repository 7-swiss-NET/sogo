var sortOrder = '';
var sortKey = '';
var listFilter = 'view_today';

var listOfSelection = null;
var selectedCalendarCell;

var hideCompletedTasks = 0;

var currentDay = '';
var currentView = "dayview";

var cachedDateSelectors = new Array();

var contactSelectorAction = 'calendars-contacts';

var eventsToDelete = new Array();
var ownersOfEventsToDelete = new Array();

function newEvent(sender, type) {
  var day = sender.getAttribute("day");
  if (!day)
    day = currentDay;

  var user = UserLogin;
  if (sender.parentNode.getAttribute("id") != "toolbar"
      && currentView == "multicolumndayview" && type == "event")
     user = sender.parentNode.parentNode.getAttribute("user");

  var hour = sender.getAttribute("hour");
  var urlstr = UserFolderURL + "../" + user + "/Calendar/new" + type;
  var params = new Array();
  if (day)
    params.push("day=" + day);
  if (hour)
    params.push("hm=" + hour);
  if (params.length > 0)
    urlstr += "?" + params.join("&");

  window.open(urlstr, "", "width=490,height=600,resizable=0");

  return false; /* stop following the link */
}

function _editEventId(id, owner) {
  var urlBase;
  if (owner)
    urlBase = UserFolderURL + "../" + owner + "/";
  urlBase += "Calendar/"

  var urlstr = urlBase + id + "/edit";

  var win = window.open(urlstr, "SOGo_edit_" + id,
                        "width=490,height=600,resizable=0");
  win.focus();
}

function editEvent() {
  if (listOfSelection) {
    var nodes = listOfSelection.getSelectedRows();

    for (var i = 0; i < nodes.length; i++)
      _editEventId(nodes[i].getAttribute("id"),
                   nodes[i].getAttribute("owner"));
  } else if (selectedCalendarCell) {
      _editEventId(selectedCalendarCell.getAttribute("aptCName"),
                   selectedCalendarCell.getAttribute("owner"));
  }

  return false; /* stop following the link */
}

function _batchDeleteEvents() {
  var events = eventsToDelete.shift();
  var owner = ownersOfEventsToDelete.shift();
  var urlstr = (UserFolderURL + "../" + owner + "/Calendar/batchDelete?ids="
                + events.join('/'));
  document.deleteEventAjaxRequest = triggerAjaxRequest(urlstr,
                                                       deleteEventCallback,
                                                       events);
}

function deleteEvent() {
  if (listOfSelection) {
    var nodes = listOfSelection.getSelectedRows();

    if (nodes.length > 0) {
      var label = "";
      if (listOfSelection == $("tasksList"))
        label = labels["taskDeleteConfirmation"].decodeEntities();
      else
        label = labels["appointmentDeleteConfirmation"].decodeEntities();
      
      if (confirm(label)) {
        if (document.deleteEventAjaxRequest) {
          document.deleteEventAjaxRequest.aborted = true;
          document.deleteEventAjaxRequest.abort();
        }
        var sortedNodes = new Array();
        var owners = new Array();

        for (var i = 0; i < nodes.length; i++) {
          var owner = nodes[i].getAttribute("owner");
          if (!sortedNodes[owner]) {
              sortedNodes[owner] = new Array();
              owners.push(owner);
          }
          sortedNodes[owner].push(nodes[i].getAttribute("id"));
        }
        for (var i = 0; i < owners.length; i++) {
          ownersOfEventsToDelete.push(owners[i]);
          eventsToDelete.push(sortedNodes[owners[i]]);
        }
        _batchDeleteEvents();
      }
    }
  }
  else if (selectedCalendarCell) {
     var label = labels["appointmentDeleteConfirmation"].decodeEntities();
     if (confirm(label)) {
        if (document.deleteEventAjaxRequest) {
           document.deleteEventAjaxRequest.aborted = true;
           document.deleteEventAjaxRequest.abort();
        }
        eventsToDelete.push([selectedCalendarCell.getAttribute("aptCName")]);
        ownersOfEventsToDelete.push(selectedCalendarCell.getAttribute("owner"));
        _batchDeleteEvents();
     }
  }
  else
    window.alert("no selection");

  return false;
}

function modifyEvent(sender, modification) {
  var currentLocation = '' + window.location;
  var arr = currentLocation.split("/");
  arr[arr.length-1] = modification;

  document.modifyEventAjaxRequest = triggerAjaxRequest(arr.join("/"),
                                                       modifyEventCallback,
                                                       modification);

  return false;
}

function closeInvitationWindow() {
  var closeDiv = document.createElement("div");
  closeDiv.addClassName("javascriptPopupBackground");
  var closePseudoWin = document.createElement("div");
  closePseudoWin.addClassName("javascriptMessagePseudoWindow");
  closePseudoWin.style.top = "0px;";
  closePseudoWin.style.left = "0px;";
  closePseudoWin.style.right = "0px;";
  closePseudoWin.appendChild(document.createTextNode(labels["closeThisWindowMessage"].decodeEntities()));
  document.body.appendChild(closeDiv);
  document.body.appendChild(closePseudoWin);
}

function modifyEventCallback(http) {
  if (http.readyState == 4) {
    if (http.status == 200) {
      log("closing window...?");
      if (queryParameters["mail-invitation"] == "yes")
        closeInvitationWindow();
      else {
        window.opener.setTimeout("refreshAppointmentsAndDisplay();", 100);
        window.setTimeout("window.close();", 100);
      }
    }
    else {
      log("showing alert...");
      window.alert(labels["eventPartStatModificationError"]);
    }
    document.modifyEventAjaxRequest = null;
  }
}

function deleteEventCallback(http) {
  if (http.readyState == 4
      && http.status == 200) {
    var nodes = http.callbackData;
    for (var i = 0; i < nodes.length; i++) {
      var node = $(nodes[i]);
      if (node)
        node.parentNode.removeChild(node);
    }
    if (eventsToDelete.length)
      _batchDeleteEvents();
    else {
      document.deleteEventAjaxRequest = null;
      refreshAppointments();
      refreshTasks();
      changeCalendarDisplay();
    }
  }
  else
    log ("ajax fuckage");
}

function editDoubleClickedEvent(node) {
  _editEventId(node.getAttribute("id"),
               node.getAttribute("owner"));
  
  return false;
}

function onSelectAll() {
  var list = $("appointmentsList");
  list.selectRowsMatchingClass("appointmentRow");

  return false;
}

function displayAppointment(event) {
  _editEventId(this.getAttribute("aptCName"),
               this.getAttribute("owner"));

  event.preventDefault();
  event.stopPropagation();
  event.cancelBubble = true;
  event.returnValue = false;
}

function onDaySelect(node) {
  var day = node.getAttribute("day");
  var needRefresh = (listFilter == 'view_selectedday'
                     && day != currentDay);

  var td = node.getParentWithTagName("td");
  var table = td.getParentWithTagName("table");

//   log ("table.selected: " + table.selected);

  if (document.selectedDate)
    document.selectedDate.deselect();

  td.select();
  document.selectedDate = td;

  changeCalendarDisplay( { "day": day } );
  if (needRefresh)
    refreshAppointments();

  return false;
}

function onDateSelectorGotoMonth(node) {
  var day = node.getAttribute("date");

  changeDateSelectorDisplay(day, true);

  return false;
}

function onCalendarGotoDay(node) {
  var day = node.getAttribute("date");

  changeDateSelectorDisplay(day);
  changeCalendarDisplay( { "day": day } );

  return false;
}

function gotoToday() {
  changeDateSelectorDisplay('');
  changeCalendarDisplay();

  return false;
}

function setDateSelectorContent(content) {
  var div = $("dateSelectorView");

  div.innerHTML = content;
  if (currentDay.length > 0)
    restoreCurrentDaySelection(div);
}

function dateSelectorCallback(http) {
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

function appointmentsListCallback(http) {
  var div = $("appointmentsListView");

  if (http.readyState == 4
      && http.status == 200) {
    document.appointmentsListAjaxRequest = null;
    div.innerHTML = http.responseText;
    var params = parseQueryParameters(http.callbackData);
    sortKey = params["sort"];
    sortOrder = params["desc"];
    var list = $("appointmentsList");
    list.addEventListener("selectionchange",
                          onAppointmentsSelectionChange, true);
    configureSortableTableHeaders();
  }
  else
    log ("ajax fuckage");
}

function tasksListCallback(http) {
  var div = $("tasksListView");

  if (http.readyState == 4
      && http.status == 200) {
    document.tasksListAjaxRequest = null;
    var list = $("tasksList");
    var scroll = list.scrollTop;
    div.innerHTML = http.responseText;
    list = $("tasksList");
    list.addEventListener("selectionchange",
                          onTasksSelectionChange, true);
    list.scrollTop = scroll;
    if (http.callbackData) {
      var selectedNodesId = http.callbackData;
      for (var i = 0; i < selectedNodesId.length; i++)
        $(selectedNodesId[i]).select();
    }
  }
  else
    log ("ajax fuckage");
}

function restoreCurrentDaySelection(div) {
  var elements = div.getElementsByTagName("a");
  var day = null;
  var i = 9;
  while (!day && i < elements.length)
    {
      day = elements[i].getAttribute("day");
      i++;
    }

  if (day
      && day.substr(0, 6) == currentDay.substr(0, 6)) {
      for (i = 0; i < elements.length; i++) {
        day = elements[i].getAttribute("day");
        if (day && day == currentDay) {
          var td = elements[i].getParentWithTagName("td");
          if (document.selectedDate)
            document.selectedDate.deselect();
          td.select();
          document.selectedDate = td;
        }
      }
    }
}

function changeDateSelectorDisplay(day, keepCurrentDay) {
  var url = ApplicationBaseURL + "dateselector";
  if (day)
    url += "?day=" + day;

  if (day != currentDay) {
    if (!keepCurrentDay)
      currentDay = day;

    log (backtrace());
    var month = day.substr(0, 6);
    if (cachedDateSelectors[month]) {
//       log ("restoring cached selector for month: " + month);
      setDateSelectorContent(cachedDateSelectors[month]);
    }
    else {
//       log ("loading selector for month: " + month);
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

function changeCalendarDisplay(time, newView) {
  var url = ApplicationBaseURL + ((newView) ? newView : currentView);

  selectedCalendarCell = null;

  var day = null;
  var hour = null;
  if (time) {
    day = time['day'];
    hour = time['hour'];
  }

  if (!day)
    day = currentDay;
  if (day)
    url += "?day=" + day;

//   if (newView)
//     log ("switching to view: " + newView);
//   log ("changeCalendarDisplay: " + url);

  if (document.dayDisplayAjaxRequest) {
//     log ("aborting day ajaxrq");
    document.dayDisplayAjaxRequest.aborted = true;
    document.dayDisplayAjaxRequest.abort();
  }
  document.dayDisplayAjaxRequest = triggerAjaxRequest(url,
                                                      calendarDisplayCallback,
                                                      { "view": newView,
                                                        "day": day,
                                                        "hour": hour });

  return false;
}

function _ensureView(view) {
  if (currentView != view)
    changeCalendarDisplay(null, view);

  return false;
}

function onDayOverview() {
  return _ensureView("dayview");
}

function onMulticolumnDayOverview() {
  return _ensureView("multicolumndayview");
}

function onWeekOverview() {
  return _ensureView("weekview");
}

function onMonthOverview() {
  return _ensureView("monthview");
}

function scrollDayView(hour) {
  var rowNumber;
  if (hour) {
    if (hour.length == 3)
      rowNumber = parseInt(hour.substr(0, 1));
    else {
      if (hour.substr(0, 1) == "0")
        rowNumber = parseInt(hour.substr(1, 1));
      else
        rowNumber = parseInt(hour.substr(0, 2));
    }
  } else
    rowNumber = 8;

  var daysView = $("daysView");
  var hours = daysView.childNodesWithTag("div")[0].childNodesWithTag("div");
  if (hours.length > 0)
    daysView.parentNode.scrollTop = hours[rowNumber + 1].offsetTop;
}

function onClickableCellsDblClick(event) {
  newEvent(this, 'event');

  event.cancelBubble = true;
  event.returnValue = false;
}

function calendarDisplayCallback(http) {
  var div = $("calendarView");

//   log ("calendardisplaycallback: " + div);
  if (http.readyState == 4
      && http.status == 200) {
    document.dayDisplayAjaxRequest = null;
    div.innerHTML = http.responseText;
    if (http.callbackData["view"])
      currentView = http.callbackData["view"];
    if (http.callbackData["day"])
      currentDay = http.callbackData["day"];
    var hour = null;
    if (http.callbackData["hour"])
      hour = http.callbackData["hour"];
    var contentView;
    if (currentView == "monthview")
      contentView = $("calendarContent");
    else {
      scrollDayView(hour);
//       log("cbtest1");
      contentView = $("daysView");
    }
    var appointments = document.getElementsByClassName("appointment", contentView);
    for (var i = 0; i < appointments.length; i++) {
      appointments[i].addEventListener("mousedown", listRowMouseDownHandler, true);
      appointments[i].addEventListener("click", onCalendarSelectAppointment, false);
      appointments[i].addEventListener("dblclick", displayAppointment, true);
    }
    var days = document.getElementsByClassName("day", contentView);
    if (currentView == "monthview")
      for (var i = 0; i < days.length; i++) {
        days[i].addEventListener("click", onCalendarSelectDay, true);
        days[i].addEventListener("dblclick", onClickableCellsDblClick, false);
      }
    else
      for (var i = 0; i < days.length; i++) {
        days[i].addEventListener("click", onCalendarSelectDay, false);
        var clickableCells = document.getElementsByClassName("clickableHourCell",
                                                             days[i]);
        for (var j = 0; j < clickableCells.length; j++)
          clickableCells[j].addEventListener("dblclick",
                                             onClickableCellsDblClick, false);
      }
//     log("cbtest1");
  }
  else
    log ("ajax fuckage");
}

function assignCalendar(name) {
   if (typeof(skycalendar) != "undefined") {
      var node = $(name);
      
      node.calendar = new skycalendar(node);
      node.calendar.setCalendarPage(ResourcesURL + "/skycalendar.html");
      var dateFormat = node.getAttribute("dateFormat");
      if (dateFormat)
	 node.calendar.setDateFormat(dateFormat);
   }
}

function popupCalendar(node) {
   var nodeId = node.getAttribute("inputId");
   var input = $(nodeId);
   input.calendar.popup();

   return false;
}

function onAppointmentContextMenu(event, element) {
  var topNode = $("appointmentsList");
//   log(topNode);

  var menu = $("appointmentsListMenu");

  menu.addEventListener("hideMenu", onAppointmentContextMenuHide, false);
  onMenuClick(event, "appointmentsListMenu");

  var topNode = $("appointmentsList");
  var selectedNodes = topNode.getSelectedRows();
  topNode.menuSelectedRows = selectedNodes;
  for (var i = 0; i < selectedNodes.length; i++)
    selectedNodes[i].deselect();

  topNode.menuSelectedEntry = element;
  element.select();
}

function onAppointmentContextMenuHide(event) {
  var topNode = $("appointmentsList");

  if (topNode.menuSelectedEntry) {
    topNode.menuSelectedEntry.deselect();
    topNode.menuSelectedEntry = null;
  }
  if (topNode.menuSelectedRows) {
    var nodeIds = topNode.menuSelectedRows;
    for (var i = 0; i < nodeIds.length; i++) {
      var node = $(nodeIds[i]);
      node.select();
    }
    topNode.menuSelectedRows = null;
  }
}

function onAppointmentsSelectionChange() {
  listOfSelection = this;
  this.removeClassName("_unfocused");
  $("tasksList").addClassName("_unfocused");
}

function onTasksSelectionChange() {
  listOfSelection = this;
  this.removeClassName("_unfocused");
  $("appointmentsList").addClassName("_unfocused");
}

function _loadAppointmentHref(href) {
  if (document.appointmentsListAjaxRequest) {
    document.appointmentsListAjaxRequest.aborted = true;
    document.appointmentsListAjaxRequest.abort();
  }
  var url = ApplicationBaseURL + href;
  document.appointmentsListAjaxRequest
    = triggerAjaxRequest(url, appointmentsListCallback, href);

  return false;
}

function _loadTasksHref(href) {
  if (document.tasksListAjaxRequest) {
    document.tasksListAjaxRequest.aborted = true;
    document.tasksListAjaxRequest.abort();
  }
  url = ApplicationBaseURL + href;

  var selectedIds = $("tasksList").getSelectedNodesId();
  document.tasksListAjaxRequest
    = triggerAjaxRequest(url, tasksListCallback, selectedIds);

  return false;
}

function onHeaderClick(event) {
//   log("onHeaderClick: " + this.link);
  _loadAppointmentHref(this.link);

  event.preventDefault();
}

function refreshAppointments() {
  return _loadAppointmentHref("aptlist?desc=" + sortOrder
                              + "&sort=" + sortKey
                              + "&day=" + currentDay
                              + "&filterpopup=" + listFilter);
}

function refreshTasks() {
  return _loadTasksHref("taskslist?hide-completed=" + hideCompletedTasks);
}

function refreshAppointmentsAndDisplay() {
  refreshAppointments();
  changeCalendarDisplay();
}

function onListFilterChange() {
  var node = $("filterpopup");

  listFilter = node.value;
//   log ("listFilter = " + listFilter);

  return refreshAppointments();
}

function onAppointmentClick(event) {
  var node = event.target.getParentWithTagName("tr");
  var day = node.getAttribute("day");
  var hour = node.getAttribute("hour");

  changeCalendarDisplay( { "day": day, "hour": hour} );
  changeDateSelectorDisplay(day);

  return onRowClick(event);
}

function selectMonthInMenu(menu, month) {
  var entries = menu.childNodes[1].childNodesWithTag("LI");
  for (i = 0; i < entries.length; i++) {
    var entry = entries[i];
    var entryMonth = entry.getAttribute("month");
    if (entryMonth == month)
      entry.addClassName("currentMonth");
    else
      entry.removeClassName("currentMonth");
  }
}

function selectYearInMenu(menu, month) {
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

function popupMonthMenu(event, menuId) {
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

function onMonthMenuItemClick(node) {
  var month = '' + node.getAttribute("month");
  var year = '' + $("yearLabel").innerHTML;
  
  changeDateSelectorDisplay(year+month+"01", true);

  return false;
}

function onYearMenuItemClick(node) {
  var month = '' + $("monthLabel").getAttribute("month");;
  var year = '' + node.innerHTML;

  changeDateSelectorDisplay(year+month+"01", true);

  return false;
}

function onSearchFormSubmit() {
  log ("search not implemented");

  return false;
}

function onCalendarSelectAppointment() {
  var list = $("appointmentsList");
  list.deselectAll();

  var aptCName = this.getAttribute("aptCName");
  if (selectedCalendarCell)
    selectedCalendarCell.deselect();
  this.select();
  selectedCalendarCell = this;
  var row = $(aptCName);
  if (row) {
    var div = row.parentNode.parentNode.parentNode;
    div.scrollTop = row.offsetTop - (div.offsetHeight / 2);
    row.select();
  }
}

function onCalendarSelectDay(event) {
  var day;
  if (currentView == "multicolumndayview")
     day = this.parentNode.getAttribute("day");
  else
     day = this.getAttribute("day");
  var needRefresh = (listFilter == 'view_selectedday'
                     && day != currentDay);

  if (currentView == 'weekview')
    changeWeekCalendarDisplayOfSelectedDay(this);
  else if (currentView == 'monthview')
    changeMonthCalendarDisplayOfSelectedDay(this);
  changeDateSelectorDisplay(day);

  if (listOfSelection) {
    listOfSelection.addClassName("_unfocused");
    listOfSelection = null;
  }

  if (needRefresh)
    refreshAppointments();
}

function changeWeekCalendarDisplayOfSelectedDay(node) {
  var days = document.getElementsByClassName("day", node.parentNode);

  for (var i = 0; i < days.length; i++)
    if (days[i] != node)
      days[i].removeClassName("selectedDay");

  node.addClassName("selectedDay");
}

function findMonthCalendarSelectedCell(daysContainer) {
   var found = false;
   var i = 0;

   while (!found && i < daysContainer.childNodes.length) {
      var currentNode = daysContainer.childNodes[i];
      if (currentNode instanceof HTMLDivElement
          && currentNode.hasClassName("selectedDay")) {
         daysContainer.selectedCell = currentNode;
         found = true;
      }
      else
         i++;
   }
}

function changeMonthCalendarDisplayOfSelectedDay(node) {
   var daysContainer = node.parentNode;
   if (!daysContainer.selectedCell)
      findMonthCalendarSelectedCell(daysContainer);
   
   if (daysContainer.selectedCell)
      daysContainer.selectedCell.removeClassName("selectedDay");
   daysContainer.selectedCell = node;
   node.addClassName("selectedDay");
}

function onHideCompletedTasks(node) {
  hideCompletedTasks = (node.checked ? 1 : 0);

  return refreshTasks();
}

function updateTaskStatus(node) {
  var taskId = node.parentNode.getAttribute("id");
  var taskOwner = node.parentNode.getAttribute("owner");
  var newStatus = (node.checked ? 1 : 0);
//   log ("update task status: " + taskId);

  var http = createHTTPClient();

  url = (UserFolderURL + "../" + taskOwner + "/Calendar/"
         + taskId + "/changeStatus?status=" + newStatus);

  if (http) {
//     log ("url: " + url);
    // TODO: add parameter to signal that we are only interested in OK
    http.url = url;
    http.open("GET", url, false /* not async */);
    http.send("");
    if (http.status == 200)
      refreshTasks();
  } else
    log ("no http client?");

  return false;
}

function updateCalendarStatus() {
  var list = new Array();

  var clist = $("calendarsList");
  var nodes = clist.childNodesWithTag("ul")[0].childNodesWithTag("li");
  for (var i = 0; i < nodes.length; i++) {
    var input = nodes[i].childNodesWithTag("input")[0];
    if (input.checked)
      list.push(nodes[i].getAttribute("uid"));
  }

  if (!list.length) {
    list.push(nodes[0].getAttribute("uid"));
    nodes[0].childNodesWithTag("input")[0].checked = true;
  }
//   ApplicationBaseURL = (UserFolderURL + "Groups/_custom_"
//                      + list.join(",") + "/Calendar/");

  updateCalendarsList();
  refreshAppointments();
  refreshTasks();
  changeCalendarDisplay();

  return false;
}

function calendarUidsList() {
  var list = "";

  var nodes = $("uixselector-calendarsList-display").childNodesWithTag("li");
  for (var i = 0; i < nodes.length; i++) {
    var currentNode = nodes[i];
    var input = currentNode.childNodesWithTag("input")[0];
    if (!input.checked)
      list += "-";
    list += currentNode.getAttribute("uid") + ",";
  }

  return list.substr(0, list.length - 1);
}

// function updateCalendarContacts(contacts)
// {
//   var list = contacts.split(",");

//   var clist = $("calendarsList");
//   var nodes = clist.childNodes[5].childNodes;
//   for (var i = 0; i < nodes.length; i++) {
//     var currentNode = nodes[i];
//     if (currentNode instanceof HTMLLIElement) {
//       var input = currentNode.childNodes[3];
//       if (!input.checked)
//         list += "-";
//       list += currentNode.getAttribute("uid") + ",";
//     }
//   }
// }

function inhibitMyCalendarEntry() {
  var clist = $("calendarsList");
  var nodes = clist.childNodes[5].childNodes;
  var done = false;

  var i = 0;
  while (!done && i < nodes.length) {
    var currentNode = nodes[i];
    if (currentNode instanceof HTMLLIElement) {
      var input = currentNode.childNodes[3];
      if (currentNode.getAttribute("uid") == UserLogin) {
        done = true;
//         currentNode.style.color = "#999;";
        currentNode.style.fontWeight = "bold;";
//         currentNode.setAttribute("onclick", "");
      }
    }
    i++;
  }
}

function userCalendarEntry(user, color) {
  var li = document.createElement("li");
  li.setAttribute("uid", user);
  li.addEventListener("mousedown", listRowMouseDownHandler, false);
  li.addEventListener("click", onRowClick, false);
  var colorBox = document.createElement("span");
  colorBox.addClassName("colorBox");
  if (color) {
    log("color:  " + color);
    colorBox.style.backgroundColor = color + ";";
  }
  li.appendChild(colorBox);
  var checkBox = document.createElement("input");
  checkBox.addClassName("checkBox");
  checkBox.type = "checkbox";
  checkBox.addEventListener("change", updateCalendarStatus, false);
  li.appendChild(checkBox);
  var text = document.createTextNode(" " + user);
  li.appendChild(text);

  return li;
}

function ensureSelfIfPresent() {
  var ul = $("uixselector-calendarsList-display");
  var list = ul.childNodesWithTag("li");
  var selfEntry = userCalendarEntry(UserLogin, indexColor(0));
  selfEntry.style.fontWeight = "bold;";
  if (list.length < 1) {
    ul.appendChild(selfEntry);
  } else if (list[0].getAttribute("uid") != UserLogin) {
    ul.insertBefore(selfEntry, list[0]);
  }
}

function updateCalendarsList(method) {
  ensureSelfIfPresent();
  var url = (ApplicationBaseURL + "updateCalendars?ids="
             + calendarUidsList());
  if (document.calendarsListAjaxRequest) {
    document.calendarsListAjaxRequest.aborted = true;
    document.calendarsListAjaxRequest.abort();
  }
  var http = createHTTPClient();
  if (http) {
    http.url = url;
    http.open("GET", url, false);
    http.send("");

    if (method == "removal")
      updateCalendarStatus();

    http = createHTTPClient();
    http.url = ApplicationBaseURL + "checkRights";
    http.open("GET", http.url, false /* not async */);
    http.send("");
    if (http.status == 200
        && http.responseText.length > 0) {
      rights = http.responseText.split(",");
      var list = $("uixselector-calendarsList-display").childNodesWithTag("li");
      for (var i = 0; i < list.length; i++) {
        var input = list[i].childNodesWithTag("input")[0];
        if (rights[i] == "1") {
          list[i].removeClassName("denied");
          input.disabled = false;
        }
        else {
          input.checked = false;
          input.disabled = true;
          list[i].addClassName("denied");
        }
      }
    }
  }
}

function addContact(tag, fullContactName, contactId, contactName, contactEmail) {
  var uids = $("uixselector-calendarsList-uidList");
//   log("addContact");
  if (contactId)
    {
      var re = new RegExp("(^|,)" + contactId + "($|,)");

      if (!re.test(uids.value))
        {
          if (uids.value.length > 0)
            uids.value += ',' + contactId;
          else
            uids.value = contactId;
          var names = $("uixselector-calendarsList-display");
          var listElems = names.childNodesWithTag("li");
          var colorDef = indexColor(listElems.length);
          names.appendChild(userCalendarEntry(contactId, colorDef));

          var styles = document.getElementsByTagName("style");
          styles[0].innerHTML += ('.ownerIs' + contactId + ' {'
                                  + ' background-color: '
                                  + colorDef
                                  + ' !important; }');
        }
    }

  return false;
}

function onChangeCalendar(list) {
   var form = document.forms.editform;
   log ("before: " + form.getAttribute("action"));
   var urlElems = form.getAttribute("action").split("/");
   urlElems[urlElems.length-4]
      = list.childNodesWithTag("option")[list.value].innerHTML;
   form.setAttribute("action", urlElems.join("/"));
   log ("after: " + form.getAttribute("action"));
}

function validateBrowseURL(input) {
  var button = $("browseURLBtn");

  if (input.value.length) {
    if (!button.enabled)
      enableAnchor(button);
  } else if (!button.disabled)
    disableAnchor(button);
}

function browseURL(anchor, event) {
  if (event.button == 0) {
    var input = $("url");
    var url = input.value;
    if (url.length)
      window.open(url, '_blank');
  }

  return false;
}

function initializeMenus() {
  var menus = new Array("monthListMenu", "yearListMenu",
                        "appointmentsListMenu", "calendarsMenu", "searchMenu");
  initMenusNamed(menus);

  $("calendarsList").attachMenu("calendarsMenu");

  var accessRightsMenuEntry = $("accessRightsMenuEntry");
  accessRightsMenuEntry.addEventListener("mouseup",
                                         onAccessRightsMenuEntryMouseUp,
                                         false);
}

function onAccessRightsMenuEntryMouseUp(event) {
  var folders = $("uixselector-calendarsList-display");
  var selected = folders.getSelectedNodes()[0];
  var uid = selected.getAttribute("uid");
  log("application base url: " + ApplicationBaseURL);
  if (uid == UserLogin)
    url = ApplicationBaseURL + "acls";
  else
    url = UserFolderURL + "../" + uid + "/Calendar/acls";

  openAclWindow(url, uid);
}

function configureDragHandles() {
  var handle = $("verticalDragHandle");
  if (handle) {
    handle.addInterface(SOGoDragHandlesInterface);
    handle.leftBlock=$("leftPanel");
    handle.rightBlock=$("rightPanel");
  }

  handle = $("rightDragHandle");
  if (handle) {
    handle.addInterface(SOGoDragHandlesInterface);
    handle.upperBlock=$("appointmentsListView");
    handle.lowerBlock=$("calendarView");
  }
}

function initCalendarContactsSelector() {
  var selector = $("calendarsList");
  inhibitMyCalendarEntry();
  updateCalendarStatus();
  selector.changeNotification = updateCalendarsList;

  var list = $("uixselector-calendarsList-display").childNodesWithTag("li");
  for (var i = 0; i < list.length; i++) {
    var input = list[i].childNodesWithTag("input")[0];
    input.addEventListener("change", updateCalendarStatus, false);
  }
}

function configureSearchField() {
   var searchValue = $("searchValue");

   searchValue.addEventListener("mousedown", onSearchMouseDown, false);
   searchValue.addEventListener("click", popupSearchMenu, false);
   searchValue.addEventListener("blur", onSearchBlur, false);
   searchValue.addEventListener("focus", onSearchFocus, false);
   searchValue.addEventListener("keydown", onSearchKeyDown, false);
}

function initCalendars() {
   if (!document.body.hasClassName("popup")) {
      initCalendarContactsSelector();
      configureSearchField();
   }
}

function onSchedulerBodyKeyUp(event) {
   if (event.which == 46) {
      window.alert("coucou");
      deleteEvent();
      event.cancelBubble = true;
   }
}

window.addEventListener("load", initCalendars, false);
// document.body.addEventListener("keyup", onSchedulerBodyKeyUp, false);
