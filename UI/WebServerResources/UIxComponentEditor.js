/* -*- Mode: java; tab-width: 2; c-tab-always-indent: t; indent-tabs-mode: t; c-basic-offset: 2 -*- */

function onPopupAttendeesWindow(event) {
  if (event)
    preventDefault(event);
  window.open(ApplicationBaseURL + "/editAttendees", null, 
							"width=803,height=573");

  return false;
}

function onSelectPrivacy(event) {
  if (event.button == 0 || (isSafari() && event.button == 1)) {
    var node = getTarget(event);
    if (node.tagName != 'BUTTON')
      node = $(node).up("button");
    popupToolbarMenu(node, "privacy-menu");
    Event.stop(event);
    //       preventDefault(event);
  }
}

function onPopupAttachWindow(event) {
  if (event)
    preventDefault(event);

  var attachInput = document.getElementById("attach");
  var newAttach = window.prompt(labels["Target:"], attachInput.value || "http://");
  if (newAttach != null) {
    var documentHref = $("documentHref");
    var documentLabel = $("documentLabel");
    if (documentHref.childNodes.length > 0) {
      documentHref.childNodes[0].nodeValue = newAttach;
      if (newAttach.length > 0)
				documentLabel.setStyle({ display: "block" });
      else
				documentLabel.setStyle({ display: "none" });
    }
    else {
      documentHref.appendChild(document.createTextNode(newAttach)); 
      if (newAttach.length > 0)
				documentLabel.setStyle({ display: "block" });
    }
    attachInput.value = newAttach;
  }
	onWindowResize(event);

  return false;
}

function onPopupDocumentWindow(event) {
  var documentUrl = $("attach");

  preventDefault(event);
  window.open(documentUrl.value, "SOGo_Document");

  return false;
}

function onMenuSetClassification(event) {
  event.cancelBubble = true;

  var classification = this.getAttribute("classification");
  if (this.parentNode.chosenNode)
    this.parentNode.chosenNode.removeClassName("_chosen");
  this.addClassName("_chosen");
  this.parentNode.chosenNode = this;

  var privacyInput = $("privacy");
  privacyInput.value = classification;
}

function onChangeCalendar(event) {
  var calendars = $("calendarFoldersList").value.split(",");
  var form = document.forms["editform"];
  var urlElems = form.getAttribute("action").split("?");
  var choice = calendars[this.value];
  var urlParam = "moveToCalendar=" + choice;
  if (urlElems.length == 1)
    urlElems.push(urlParam);
  else
    urlElems[2] = urlParam;

  while (urlElems.length > 2)
    urlElems.pop();

  form.setAttribute("action", urlElems.join("?"));
}

function initializeDocumentHref() {
  var documentHref = $("documentHref");
  var documentLabel = $("documentLabel");
  var documentUrl = $("attach");

  documentHref.observe("click", onPopupDocumentWindow, false);
  documentHref.setStyle({ textDecoration: "underline", color: "#00f" });
  if (documentUrl.value.length > 0) {
    documentHref.appendChild(document.createTextNode(documentUrl.value));
    documentLabel.setStyle({ display: "block" });
  }

  var changeUrlButton = $("changeAttachButton");
  changeUrlButton.observe("click", onPopupAttachWindow, false);
}

function initializePrivacyMenu() {
  var privacy = $("privacy").value.toUpperCase();
  var privacyMenu = $("privacy-menu").childNodesWithTag("ul")[0];
  var menuEntries = $(privacyMenu).childNodesWithTag("li");
  var chosenNode;
  if (privacy == "CONFIDENTIAL")
    chosenNode = menuEntries[1];
  else if (privacy == "PRIVATE")
    chosenNode = menuEntries[2];
  else
    chosenNode = menuEntries[0];
  privacyMenu.chosenNode = chosenNode;
  $(chosenNode).addClassName("_chosen");
}

function onComponentEditorLoad(event) {
  initializeDocumentHref();
  initializePrivacyMenu();
  var list = $("calendarList");
  list.observe("change", onChangeCalendar, false);
  list.fire("mousedown");

  var menuItems = $("itemPrivacyList").childNodesWithTag("li");
  for (var i = 0; i < menuItems.length; i++)
		menuItems[i].observe("mousedown",
												 onMenuSetClassification.bindAsEventListener(menuItems[i]),
												 false);

  $("repeatHref").observe("click", onPopupRecurrenceWindow);
  $("repeatList").observe("change", onPopupRecurrenceWindow);
	$("reminderHref").observe("click", onPopupReminderWindow);
	$("reminderList").observe("change", onPopupReminderWindow);
  $("summary").observe("keyup", onSummaryChange);

	Event.observe(window, "resize", onWindowResize);

  onPopupRecurrenceWindow(null);
	onPopupReminderWindow(null);
  onSummaryChange (null);

	var summary = $("summary");
	summary.focus();
	summary.selectText(0, summary.value.length);
}

function onSummaryChange (e) {
  document.title = $("summary").value;
}

function onWindowResize(event) {
	var document = $("documentLabel");
	var comment = $("commentArea");
	var area = comment.select("textarea").first();
	var offset = 6;
	var height;

	height = window.height() - comment.cumulativeOffset().top - offset;

	if (document.visible())
		height -= $("changeAttachButton").getHeight();
	
	area.setStyle({ height: (height - offset*2) + "px" });
	comment.setStyle({ height: (height - offset) + "px" });
	
	return true;
}

function onPopupRecurrenceWindow(event) {
  if (event)
    preventDefault(event);

  var repeatHref = $("repeatHref");

  if ($("repeatList").value == 7) {
    repeatHref.show();
    if (event)
      window.open(ApplicationBaseURL + "editRecurrence", null, 
									"width=500,height=400");
  }
  else
    repeatHref.hide();

  return false;
}

function onPopupReminderWindow(event) {
  if (event)
    preventDefault(event);

  var reminderHref = $("reminderHref");

  if ($("reminderList").value == 15) {
    reminderHref.show();
    if (event)
      window.open(ApplicationBaseURL + "editReminder", null, 
									"width=250,height=150");
  }
  else
    reminderHref.hide();

  return false;
}

document.observe("dom:loaded", onComponentEditorLoad);
