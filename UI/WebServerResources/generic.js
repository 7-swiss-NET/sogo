/* -*- Mode: java; tab-width: 2; c-tab-always-indent: t; indent-tabs-mode: t; c-basic-offset: 2 -*- */

/*
	Copyright (C) 2005 SKYRIX Software AG

	This file is part of OpenGroupware.org.

	OGo is free software; you can redistribute it and/or modify it under
	the terms of the GNU Lesser General Public License as published by the
	Free Software Foundation; either version 2, or (at your option) any
	later version.

	OGo is distributed in the hope that it will be useful, but WITHOUT ANY
	WARRANTY; without even the implied warranty of MERCHANTABILITY or
	FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
	License for more details.

	You should have received a copy of the GNU Lesser General Public
	License along with OGo; see the file COPYING.  If not, write to the
	Free Software Foundation, 59 Temple Place - Suite 330, Boston, MA
	02111-1307, USA.
*/
/* some generic JavaScript code for SOGo */

/* generic stuff */

var logConsole;
var logWindow = null;

var queryParameters;

var menus = new Array();
var search = {};
var sorting = {};

var lastClickedRow = -1;

// logArea = null;
var allDocumentElements = null;

// Ajax requests counts
var activeAjaxRequests = 0;
var removeFolderRequestCount = 0;

/* a W3C compliant document.all */
function getAllScopeElements(scope) {
	var elements = new Array();

	for (var i = 0; i < scope.childNodes.length; i++)
		if (typeof(scope.childNodes[i]) == "object"
				&& scope.childNodes[i].tagName
				&& scope.childNodes[i].tagName != '')
			{
				elements.push(scope.childNodes[i]);
				var childElements = getAllElements(scope.childNodes[i]);
				if (childElements.length > 0)
					elements.push(childElements);
			}

	return elements;
}

function getAllElements(scope) {
	var elements;

	if (scope == null)
		scope = document;

	if (scope == document
			&& allDocumentElements != null)
		elements = allDocumentElements;
	else
		{
			elements = getAllScopeElements(scope);
			if (scope == document)
				allDocumentElements = elements;
		}

	return elements;
}

function createElement(tagName, id, classes,
											 attributes, htmlAttributes,
											 parentNode) {
	var newElement = $(document.createElement(tagName));
	if (id)
		newElement.setAttribute("id", id);
	if (classes) {
		if (typeof(classes) == "string")
			newElement.addClassName(classes);
		else
			for (var i = 0; i < classes.length; i++)
				newElement.addClassName(classes[i]);
	}
	if (attributes)
		for (var i in attributes)
			newElement[i] = attributes[i];
	if (htmlAttributes)
		for (var i in htmlAttributes)
			newElement.setAttribute(i, htmlAttributes[i]);
	if (parentNode)
		parentNode.appendChild(newElement);

	return $(newElement);
}

function ml_stripActionInURL(url) {
	if (url[url.length - 1] != '/') {
		var i;

		i = url.lastIndexOf("/");
		if (i != -1) url = url.substring(0, i);
	}
	if (url[url.length - 1] != '/') // ensure trailing slash
		url = url + "/";
	return url;
}

function URLForFolderID(folderID) {
	var folderInfos = folderID.split(":");
	var url;
	if (folderInfos.length > 1) {
		url = UserFolderURL + "../" + encodeURI(folderInfos[0]);
		if (!(folderInfos[0].endsWith('/')
					|| folderInfos[1].startsWith('/')))
			url += '/';
		url += folderInfos[1];
	}
	else
		url = ApplicationBaseURL + encodeURI(folderInfos[0]);

	if (url[url.length-1] == '/')
		url = url.substr(0, url.length-1);

	return url;
}

function extractEmailAddress(mailTo) {
	var email = "";

	var emailre
		= /(([a-zA-Z0-9\._-]+)*[a-zA-Z0-9_-]+@([a-zA-Z0-9\._-]+)*[a-zA-Z0-9_-]+)/;
	if (emailre.test(mailTo)) {
		emailre.exec(mailTo);
		email = RegExp.$1;
	}

	return email;
}

function extractEmailName(mailTo) {
	var emailName = "";

	var tmpMailTo = mailTo.replace("&lt;", "<");
	tmpMailTo = tmpMailTo.replace("&gt;", ">");

	var emailNamere = /([ 	]+)?(.+)\ </;
	if (emailNamere.test(tmpMailTo)) {
		emailNamere.exec(tmpMailTo);
		emailName = RegExp.$2;
	}

	return emailName;
}

function extractSubject(mailTo) {
	var subject = "";

	var subjectre = /\?subject=([^&]+)/;
	if (subjectre.test(mailTo)) {
		subjectre.exec(mailTo);
		subject = RegExp.$1;
	}

	return subject;
}

function sanitizeMailTo(dirtyMailTo) {
	var emailName = extractEmailName(dirtyMailTo);
	var email = extractEmailAddress(dirtyMailTo);

	var mailto = "";
	if (emailName && emailName.length > 0)
		mailto = emailName + ' <' + email + '>';
	else
		mailto = email;

	return mailto;
}

function sanitizeWindowName(dirtyWindowName) {
	// IE is picky about the characters used for the window name.
	return dirtyWindowName.replace(/[\s\.\/\-\@]/g, "_");
}

function openUserFolderSelector(callback, type) {
	var urlstr = ApplicationBaseURL;
	if (! urlstr.endsWith('/'))
		urlstr += '/';
	urlstr += ("../../" + UserLogin + "/Contacts/userFolders");
	var w = window.open(urlstr, "_blank",
											"width=322,height=250,resizable=1,scrollbars=0,location=0");
	w.opener = window;
	window.userFolderCallback = callback;
	window.userFolderType = type;
	w.focus();
}

function openContactWindow(url, wId) {
	if (!wId)
		wId = "_blank";
	else {
		wId = sanitizeWindowName(wId);
	}

	var w = window.open(url, wId,
											"width=450,height=600,resizable=0,location=0");
	w.focus();

	return w;
}

function openMailComposeWindow(url, wId) {
	var parentWindow = this;

	if (!wId)
		wId = "_blank";
	else {
		wId = sanitizeWindowName(wId);
	}

	if (document.body.hasClassName("popup"))
		parentWindow = window.opener;

	var w = parentWindow.open(url, wId,
														"width=680,height=520,resizable=1,scrollbars=1,toolbar=0,"
														+ "location=0,directories=0,status=0,menubar=0"
														+ ",copyhistory=0");

	w.focus();

	return w;
}

function openMailTo(senderMailTo) {
	var addresses = senderMailTo.split(",");
	var sanitizedAddresses = new Array();
	var subject = extractSubject(senderMailTo);
	for (var i = 0; i < addresses.length; i++) {
		var sanitizedAddress = sanitizeMailTo(addresses[i]);
		if (sanitizedAddress.length > 0)
			sanitizedAddresses.push(sanitizedAddress);
	}

	var mailto = sanitizedAddresses.join(",");

	if (mailto.length > 0)
		openMailComposeWindow(ApplicationBaseURL
													+ "../Mail/compose?mailto=" + encodeURI(mailto)
													+ ((subject.length > 0)?"?subject=" + encodeURI(subject):""));

	return false; /* stop following the link */
}

function deleteDraft(url) {
	/* this is called by UIxMailEditor with window.opener */
	new Ajax.Request(url, {
		asynchronous: false,
				method: 'post',
				onFailure: function(transport) {
				log("draftDeleteCallback: problem during ajax request: " + transport.status);
			}
	});
}

function createHTTPClient() {
	// http://developer.apple.com/internet/webcontent/xmlhttpreq.html
	if (typeof XMLHttpRequest != "undefined")
		return new XMLHttpRequest();

	try { return new ActiveXObject("Msxml2.XMLHTTP"); } 
	catch (e) { }
	try { return new ActiveXObject("Microsoft.XMLHTTP"); } 
	catch (e) { }

	return null;
}

function appendDifferentiator(url) {
	var url_nocache = url;
	var position = url.indexOf('?', 0);
	if (position < 0)
		url_nocache += '?';
	else
		url_nocache += '&';
	url_nocache += 'differentiator=' + Math.floor(Math.random()*50000);

	return url_nocache;
}

function onAjaxRequestStateChange(http) {
	try {
		if (http.readyState == 4
				&& activeAjaxRequests > 0) {
			if (!http.aborted)
				http.callback(http);
			activeAjaxRequests--;
			checkAjaxRequestsState();
			http.onreadystatechange = Prototype.emptyFunction;
			http.callback = Prototype.emptyFunction;
			http.callbackData = null;
		}
	}
	catch(e) {
		activeAjaxRequests--;
		checkAjaxRequestsState();
		http.onreadystatechange = Prototype.emptyFunction;
		http.callback = Prototype.emptyFunction;
		http.callbackData = null;
		log("AJAX Request, Caught Exception: " + e.name);
		log(e.message);
		if (e.fileName) {
			if (e.lineNumber)
				log("at " + e.fileName + ": " + e.lineNumber);
			else
				log("in " + e.fileName);
		}
		log(backtrace());
		log("request url was '" + http.url + "'");
	}
}

/* taken from Lightning */
function getContrastingTextColor(bgColor) {
	var calcColor = bgColor.substring(1);
	var red = parseInt(calcColor.substring(0, 2), 16);
	var green = parseInt(calcColor.substring(2, 4), 16);
	var blue = parseInt(calcColor.substring(4, 6), 16);

	// Calculate the brightness (Y) value using the YUV color system.
	var brightness = (0.299 * red) + (0.587 * green) + (0.114 * blue);

	// Consider all colors with less than 56% brightness as dark colors and
	// use white as the foreground color, otherwise use black.
	return ((brightness < 144)
					? "white"
					: "black");
}

function triggerAjaxRequest(url, callback, userdata, content, headers) {
	var http = createHTTPClient();

	activeAjaxRequests++;
	document.animTimer = setTimeout("checkAjaxRequestsState();", 250);
	//url = appendDifferentiator(url);

	if (http) {
		http.open("POST", url, true);
		http.url = url;
		http.callback = callback;
		http.callbackData = userdata;
		http.onreadystatechange = function() { onAjaxRequestStateChange(http) };
		//       = function() {
		// //       log ("state changed (" + http.readyState + "): " + url);
		//     };
		var hasContentLength = false;
		if (headers) {
			for (var i in headers) {
				if (i.toLowerCase() == "content-length")
					hasContentLength = true;
				http.setRequestHeader(i, headers[i]);
			}
		}
		if (!hasContentLength) {
			var cLength = "0";
			if (content)
				cLength = "" + content.length;
			http.setRequestHeader("Content-Length", "" + cLength);
		}
		http.send(content ? content : "");
	}
	else {
		log("triggerAjaxRequest: error creating HTTP Client!");
	}

	return http;
}

function startAnimation(parent, nextNode) {
	var anim = $("progressIndicator");
	if (!anim) {
		anim = createElement("img", "progressIndicator", null,
												 {src: ResourcesURL + "/busy.gif"});
		anim.setStyle({ visibility: "hidden" });
		if (nextNode)
			parent.insertBefore(anim, nextNode);
		else
			parent.appendChild(anim);
		anim.setStyle({ visibility: "visible" });
	}

	return anim;
}

function checkAjaxRequestsState() {
	var progressImage = $("progressIndicator");
	if (activeAjaxRequests > 0
			&& !progressImage) {
		var toolbar = $("toolbar");
		if (toolbar)
			startAnimation(toolbar);
	}
	else if (!activeAjaxRequests
					 && progressImage)
		progressImage.parentNode.removeChild(progressImage);
}

function isMac() {
	return (navigator.platform.indexOf('Mac') > -1);
}

function isWindows() {
	return (navigator.platform.indexOf('Win') > -1);
}

function isSafari3() {
	return (navigator.appVersion.indexOf("Version") > -1);
}

function isSafari() {
	//var agt = navigator.userAgent.toLowerCase();
	//var is_safari = ((agt.indexOf('safari')!=-1)&&(agt.indexOf('mac')!=-1))?true:false;

	return (navigator.vendor == "Apple Computer, Inc.") || (navigator.userAgent.toLowerCase().indexOf('konqueror') != -1);
}

function isHttpStatus204(status) {
	return (status == 204 ||                                  // Firefox
					(isSafari() && typeof(status) == 'undefined') ||  // Safari
					status == 1223);                                  // IE
}

function getTarget(event) {
	event = event || window.event;
	if (event.target)
		return event.target; // W3C DOM
	else
		return event.srcElement; // IE
}

function preventDefault(event) {
	if (event)
		if (event.preventDefault)
			event.preventDefault(); // W3C DOM
		else
			event.returnValue = false; // IE
}

function resetSelection(win) {
	var t = "";
	if (win && win.getSelection) {
		t = win.getSelection().toString();
		win.getSelection().removeAllRanges();
	}
	return t;
}

function refreshOpener() {
	if (window.opener && !window.opener.closed) {
		window.opener.location.reload();
	}
}

/* query string */

function parseQueryString() {
	var queryArray, queryDict
		var key, value, s, idx;
	queryDict.length = 0;

	queryDict  = new Array();
	queryArray = location.search.substr(1).split('&');
	for (var i in queryArray) {
		if (!queryArray[i]) continue ;
		s   = queryArray[i];
		idx = s.indexOf("=");
		if (idx == -1) {
			key   = s;
			value = "";
		}
		else {
			key   = s.substr(0, idx);
			value = unescape(s.substr(idx + 1));
		}

		if (typeof queryDict[key] == 'undefined')
			queryDict.length++;

		queryDict[key] = value;
	}
	return queryDict;
}

function generateQueryString(queryDict) {
	var s = "";
	for (var key in queryDict) {
		if (s.length == 0)
			s = "?";
		else
			s = s + "&";
		s = s + key + "=" + escape(queryDict[key]);
	}
	return s;
}

/* selection mechanism */

function deselectAll(parent) {
	for (var i = 0; i < parent.childNodes.length; i++) {
		var node = parent.childNodes.item(i);
		if (node.nodeType == 1)
			$(node).deselect();
	}
}

function isNodeSelected(node) {
	return $(node).hasClassName('_selected');
}

function acceptMultiSelect(node) {
	var response = false;
	var attribute = node.getAttribute('multiselect');
	if (attribute && attribute.length > 0) {
		log("node '" + node.getAttribute("id")
				+ "' is still using old-stylemultiselect!");
		response = (attribute.toLowerCase() == 'yes');
	}
	else
		response = node.multiselect;

	return response;
}

function onRowClick(event) {
	var node = getTarget(event);
	var rowIndex = null;

	if (node.tagName != 'TD' && node.tagName != 'LI')
		node = this;

	if (node.tagName == 'TD') {
		node = node.parentNode; // select TR
	}
	if (node.tagName == 'TR') {
		rowIndex = node.rowIndex - $(node).up('table').down('thead').getElementsByTagName('tr').length;
	}
	else if (node.tagName == 'LI') {
		// Find index of clicked row
		var list = node.parentNode;
		var items = list.childNodesWithTag("li");
		for (var i = 0; i < items.length; i++) {
			if (items[i] == node) {
				rowIndex = i;
				break;
			}
		}
	}

	var initialSelection = $(node.parentNode).getSelectedNodes();
	var isLeftClick = true;
	if (isMac() && isSafari())
		if (event.ctrlKey == 1)
			isLeftClick = false; // Control-click is equivalent to right-click under Mac OS X
		else if (event.metaKey == 1) // Command-click
			isLeftClick = true;
		else
			isLeftClick = Event.isLeftClick(event);
	else
		isLeftClick = Event.isLeftClick(event);

	if (initialSelection.length > 0 
			&& initialSelection.indexOf(node) >= 0
			&& !isLeftClick)
		// Ignore non primary-click (ie right-click) inside current selection
		return true;

	if ((event.shiftKey == 1 || isMac() && event.metaKey == 1 || isWindows() && event.ctrlKey == 1)
			&& (lastClickedRow >= 0)
			&& (acceptMultiSelect(node.parentNode)
					|| acceptMultiSelect(node.parentNode.parentNode))) {
		if (event.shiftKey) {
			$(node.parentNode).selectRange(lastClickedRow, rowIndex);
		} else if (isNodeSelected(node)) {
			$(node).deselect();
			rowIndex = null;
		} else {
			$(node).selectElement();
		}
		// At this point, should empty content of 3-pane view
	} else {
		// Single line selection
		$(node.parentNode).deselectAll();
		$(node).selectElement();

		if (initialSelection != $(node.parentNode).getSelectedNodes()) {
			// Selection has changed; fire mousedown event
			var parentNode = node.parentNode;
			if (parentNode.tagName == 'TBODY')
				parentNode = parentNode.parentNode;
			parentNode.fire("mousedown");
		}
	}
	if (rowIndex)
		lastClickedRow = rowIndex;

	return true;
}

/* popup menus */

function popupMenu(event, menuId, target) {
	document.menuTarget = target;

	if (document.currentPopupMenu)
		hideMenu(document.currentPopupMenu);

	var popup = $(menuId);

	var deltaX = 0;
	var deltaY = 0;

	var pageContent = $("pageContent");
	if (popup.parentNode.tagName != "BODY") {
		var offset = pageContent.cascadeLeftOffset();
		deltaX = -($(popup.parentNode).cascadeLeftOffset() - offset);
		offset = pageContent.cascadeTopOffset();
		deltaY = -($(popup.parentNode).cascadeTopOffset() - offset);
	}

	var menuTop = Event.pointerY(event) + deltaY;
	var menuLeft = Event.pointerX(event) + deltaX;
	var heightDiff = (window.height()
										- (menuTop + popup.offsetHeight));
	if (heightDiff < 0)
		menuTop += heightDiff;

	var leftDiff = (window.width()
									- (menuLeft + popup.offsetWidth));
	if (leftDiff < 0)
		menuLeft -= popup.offsetWidth;

	if (popup.prepareVisibility)
		popup.prepareVisibility();

	popup.setStyle({ top: menuTop + "px",
				left: menuLeft + "px",
				visibility: "visible" });

	document.currentPopupMenu = popup;

	$(document.body).observe("click", onBodyClickMenuHandler);

	Event.stop(event);
}

function getParentMenu(node) {
	var currentNode, menuNode;

	menuNode = null;
	currentNode = node;
	var menure = new RegExp("(^|\s+)menu(\s+|$)", "i");

	while (menuNode == null
				 && currentNode)
		if (menure.test(currentNode.className))
			menuNode = currentNode;
		else
			currentNode = currentNode.parentNode;

	return menuNode;
}

function onBodyClickMenuHandler(event) {
	hideMenu(document.currentPopupMenu);
	document.body.stopObserving("click", onBodyClickMenuHandler);
	document.body.stopObserving("mouseup", onBodyClickMenuHandler);
	document.currentPopupMenu = null;

	if (event)
		preventDefault(event);
}

function onMenuClickHandler(event) {
	if (!this.hasClassName("disabled"))
		this.menuCallback.apply(this, [event]);
}

function hideMenu(menuNode) {
	var onHide;

	if (!menuNode)
		return;

	if (menuNode.submenu) {
		hideMenu(menuNode.submenu);
		menuNode.submenu = null;
	}

	menuNode.setStyle({ visibility: "hidden" });
	if (menuNode.parentMenuItem) {
		menuNode.parentMenuItem.stopObserving("mouseover",onMouseEnteredSubmenu);
		menuNode.stopObserving("mouseover", onMouseEnteredSubmenu);
		menuNode.parentMenuItem.stopObserving("mouseout", onMouseLeftSubmenu);
		menuNode.stopObserving("mouseout", onMouseLeftSubmenu);
		menuNode.parentMenu.stopObserving("mouseover", onMouseEnteredParentMenu);
		$(menuNode.parentMenuItem).removeClassName("submenu-selected");
		menuNode.parentMenuItem.mouseInside = false;
		menuNode.parentMenuItem = null;
		menuNode.parentMenu.submenuItem = null;
		menuNode.parentMenu.submenu = null;
		menuNode.parentMenu = null;
	}

	$(menuNode).fire("mousedown");
}

function onMenuEntryClick(event) {
	var node = event.target;

	id = getParentMenu(node).menuTarget;

	return false;
}

function parseQueryParameters(url) {
	var parameters = new Array();

	var params = url.split("?")[1];
	if (params) {
		var pairs = params.split("&");
		for (var i = 0; i < pairs.length; i++) {
			var pair = pairs[i].split("=");
			parameters[pair[0]] = pair[1];
		}
	}

	return parameters;
}

function initLogConsole() {
	var logConsole = $("logConsole");
	if (logConsole) {
		logConsole.highlighted = false;
		logConsole.observe("dblclick", onLogDblClick, false);
		logConsole.update();
		Event.observe(window, "keydown", onBodyKeyDown);
	}
}

function onBodyKeyDown(event) {
	if (event.keyCode == Event.KEY_ESC) {
		toggleLogConsole();
		preventDefault(event);
	}
}

function onLogDblClick(event) {
	var logConsole = $("logConsole");
	logConsole.innerHTML = "";
}

function toggleLogConsole(event) {
	var logConsole = $("logConsole");
	var display = '' + logConsole.style.display;
	if (display.length == 0) {
		logConsole.setStyle({ display: 'block' });
	} else {
		logConsole.setStyle({ display: '' });
	}
	if (event)
		preventDefault(event);
}

function log(message) {
	if (!logWindow) {
		logWindow = window;
		while (logWindow.opener)
			logWindow = logWindow.opener;
	}
	var logConsole = logWindow.document.getElementById("logConsole");
	if (logConsole) {
		logConsole.highlighted = !logConsole.highlighted;
		if (message == '\c') {
			logConsole.innerHTML = "";
			return;
		}
		var logMessage = message.replace("<", "&lt;", "g");
		logMessage = logMessage.replace(" ", "&nbsp;", "g");
		logMessage = logMessage.replace("\r\n", "<br />\n", "g");
		logMessage = logMessage.replace("\n", "<br />\n", "g");
		logMessage += '<br />' + "\n";
		if (logConsole.highlighted)
			logMessage = '<div class="highlighted">' + logMessage + '</div>';
		logConsole.innerHTML += logMessage;
	}
}

function backtrace() {
	var func = backtrace.caller;
	var str = "backtrace:\n";

	while (func)
		{
			if (func.name)
				{
					str += "  " + func.name;
					if (this)
						str += " (" + this + ")";
				}
			else
				str += "[anonymous]\n";

			str += "\n";
			func = func.caller;
		}
	str += "--\n";

	return str;
}

function popupSubmenu(event) {
	if (this.submenu && this.submenu != "" && !$(this).hasClassName("disabled")) {
		var submenuNode = $(this.submenu);
		var parentNode = getParentMenu(this);
		if (parentNode.submenu)
			hideMenu(parentNode.submenu);
		submenuNode.parentMenuItem = this;
		submenuNode.parentMenu = parentNode;
		parentNode.submenuItem = this;
		parentNode.submenu = submenuNode;

		if (submenuNode.prepareVisibility)
			submenuNode.prepareVisibility();

		var menuTop = (parentNode.offsetTop - 1
									 + this.offsetTop);

		if (window.height()
				< (menuTop + submenuNode.offsetHeight))
			if (submenuNode.offsetHeight < window.height())
				menuTop = window.height() - submenuNode.offsetHeight;
			else
				menuTop = 0;

		var menuLeft = (parentNode.offsetLeft + parentNode.offsetWidth - 3);
		if (window.width()
				< (menuLeft + submenuNode.offsetWidth))
			menuLeft = parentNode.offsetLeft - submenuNode.offsetWidth + 3;

		this.mouseInside = true;
		this.observe("mouseover", onMouseEnteredSubmenu);
		submenuNode.observe("mouseover", onMouseEnteredSubmenu);
		this.observe("mouseout", onMouseLeftSubmenu);
		submenuNode.observe("mouseout", onMouseLeftSubmenu);
		parentNode.observe("mouseover", onMouseEnteredParentMenu);
		$(this).addClassName("submenu-selected");
		submenuNode.setStyle({ top: menuTop + "px",
					left: menuLeft + "px",
					visibility: "visible" });
		preventDefault(event);
	}
}

function onMouseEnteredParentMenu(event) {
	if (this.submenuItem && !this.submenuItem.mouseInside)
		hideMenu(this.submenu);
}

function onMouseEnteredSubmenu(event) {
	$(this).mouseInside = true;
}

function onMouseLeftSubmenu(event) {
	$(this).mouseInside = false;
}

/* search field */
function popupSearchMenu(event) {
	var menuId = this.getAttribute("menuid");
	var offset = Position.cumulativeOffset(this);

	relX = Event.pointerX(event) - offset[0];
	relY = Event.pointerY(event) - offset[1];

	if (event.button == 0
			&& relX < 24) {
		event.cancelBubble = true;
		event.returnValue = false;

		if (document.currentPopupMenu)
			hideMenu(document.currentPopupMenu);

		var popup = $(menuId);
		offset = Position.positionedOffset(this);
		popup.setStyle({ top: this.offsetHeight + "px",
					left: (offset[0] + 3) + "px",
					visibility: "visible" });

		document.currentPopupMenu = popup;
		$(document.body).observe("click", onBodyClickMenuHandler);
	}
}

function setSearchCriteria(event) {
	var searchValue = $("searchValue");
	var searchCriteria = $("searchCriteria");

	if (searchValue.ghostPhrase == searchValue.value)
		searchValue.value = this.innerHTML;

	searchValue.ghostPhrase = this.innerHTML;
	searchCriteria.value = this.getAttribute('id');

	if (this.parentNode.chosenNode)
		this.parentNode.chosenNode.removeClassName("_chosen");
	this.addClassName("_chosen");

	if (this.parentNode.chosenNode != this) {
		searchValue.lastSearch = "";
		this.parentNode.chosenNode = this;

		onSearchFormSubmit();
	}
}

function checkSearchValue(event) {
	var searchValue = $("searchValue");

	if (searchValue.value == searchValue.ghostPhrase)
		searchValue.value = "";
}

function configureSearchField() {
	var searchValue = $("searchValue");

	if (searchValue) {
		searchValue.observe("click", popupSearchMenu);
		searchValue.observe("blur", onSearchBlur);
		searchValue.observe("focus", onSearchFocus);
		searchValue.observe("keydown", onSearchKeyDown);
		searchValue.observe("mousedown", onSearchMouseDown);
	}
}

function onSearchMouseDown(event) {
	var superNode = this.parentNode.parentNode.parentNode;
	relX = (Event.pointerX(event) - superNode.offsetLeft - this.offsetLeft);
	relY = (Event.pointerY(event) - superNode.offsetTop - this.offsetTop);

	if (relX < 24)
		Event.stop(event);
}

function onSearchFocus() {
	ghostPhrase = this.ghostPhrase;
	if (this.value == ghostPhrase) {
		this.value = "";
		this.setAttribute("modified", "");
	} else {
		this.selectElement();
	}

	this.setStyle({ color: "#000" });
}

function onSearchBlur(event) {
	if (!this.value || this.value.strip().length == 0) {
		this.setAttribute("modified", "");
		this.setStyle({ color: "#aaa" });
		this.value = this.ghostPhrase;
		search["value"] = "";
		if (this.lastSearch != "") {
			this.lastSearch = "";
			refreshCurrentFolder();
		}
	} else if (this.value == this.ghostPhrase) {
		this.setAttribute("modified", "");
		this.setStyle({ color: "#aaa" });
	} else {
		this.setAttribute("modified", "yes");
		this.setStyle({ color: "#000" });
	}
}

function onSearchKeyDown(event) {
	if (this.timer)
		clearTimeout(this.timer);

	if (event.keyCode == 13) {
		onSearchFormSubmit();
		preventDefault(event);
	}
	else if (event.keyCode == 8
					 || event.keyCode >31)
		this.timer = setTimeout("onSearchFormSubmit()", 1000);
}

function onSearchFormSubmit(event) {
	var searchValue = $("searchValue");
	var searchCriteria = $("searchCriteria");

	if (searchValue.value != searchValue.ghostPhrase
			&& (searchValue.value != searchValue.lastSearch
					|| searchValue.value.strip().length > 0)) {
		search["criteria"] = searchCriteria.value;
		search["value"] = searchValue.value;
		searchValue.lastSearch = searchValue.value;
		refreshCurrentFolder();
	}
}

function initCriteria() {
	var searchCriteria = $("searchCriteria");
	var searchValue = $("searchValue");
	var searchOptions = $("searchOptions");

	if (searchValue) {
		var firstOption = searchOptions.down("li");
		if (firstOption) {
			searchCriteria.value = firstOption.getAttribute('id');
			searchValue.ghostPhrase = firstOption.innerHTML;
			searchValue.lastSearch = "";
			if (searchValue.value == '') {
				searchValue.value = firstOption.innerHTML;
				searchValue.setAttribute("modified", "");
				searchValue.setStyle({ color: "#aaa" });
			}
			// Set the checkmark to the first option
			if (searchOptions.chosenNode)
				searchOptions.chosenNode.removeClassName("_chosen");
			firstOption.addClassName("_chosen");
			searchOptions.chosenNode = firstOption;
		}
		searchValue.blur();
	}
}

/* toolbar buttons */
function popupToolbarMenu(node, menuId) {
	if (document.currentPopupMenu)
		hideMenu(document.currentPopupMenu);

	var popup = $(menuId);

	if (popup.prepareVisibility)
		popup.prepareVisibility();

	var offset = $(node).cumulativeOffset();
	var top = offset.top + node.offsetHeight;
	popup.setStyle({ top: top + "px",
				left: offset.left + "px",
				visibility: "visible" });

	document.currentPopupMenu = popup;
	$(document.body).observe("mouseup", onBodyClickMenuHandler);
}

/* contact selector */

function folderSubscriptionCallback(http) {
	if (http.readyState == 4) {
		if (isHttpStatus204(http.status)) {
			if (http.callbackData)
				http.callbackData["method"](http.callbackData["data"]);
		}
		else
			window.alert(clabels["Unable to subscribe to that folder!"]);
		document.subscriptionAjaxRequest = null;
	}
	else
		log ("folderSubscriptionCallback Ajax error");
}

function subscribeToFolder(refreshCallback, refreshCallbackData) {
	var folderData = refreshCallbackData["folder"].split(":");
	var username = folderData[0];
	var folderPath = folderData[1];
	if (username != UserLogin) {
		var url = (UserFolderURL + "../" + username
							 + folderPath + "/subscribe");
		if (document.subscriptionAjaxRequest) {
			document.subscriptionAjaxRequest.aborted = true;
			document.subscriptionAjaxRequest.abort();
		}

		var rfCbData = { method: refreshCallback, data: refreshCallbackData };
		document.subscriptionAjaxRequest = triggerAjaxRequest(url,
																													folderSubscriptionCallback,
																													rfCbData);
	}
	else
		refreshCallbackData["window"].alert(clabels["You cannot subscribe to a folder that you own!"]);
}

function folderUnsubscriptionCallback(http) {
	if (http.readyState == 4) {
		removeFolderRequestCount--;
		if (isHttpStatus204(http.status)) {
			if (http.callbackData)
				http.callbackData["method"](http.callbackData["data"]);
		}
		else
			window.alert(clabels["Unable to unsubscribe from that folder!"]);
	}
}

function unsubscribeFromFolder(folder, owner, refreshCallback,
															 refreshCallbackData) {
	if (document.body.hasClassName("popup")) {
		window.opener.unsubscribeFromFolder(folder, refreshCallback,
																				refreshCallbackData);
	}
	else {
		if (owner.startsWith('/'))
			owner = owner.substring(1);
		if (owner != UserLogin) {
			var url = (ApplicationBaseURL + folder + "/unsubscribe");
			removeFolderRequestCount++;
			var rfCbData = { method: refreshCallback, data: refreshCallbackData };
			triggerAjaxRequest(url, folderUnsubscriptionCallback, rfCbData);
		}
		else
			window.alert(clabels["You cannot unsubscribe from a folder that you own!"]);
	}
}

function accessToSubscribedFolder(serverFolder) {
	var folder;

	var parts = serverFolder.split(":");
	if (parts.length > 1) {
		var paths = parts[1].split("/");
		folder = "/" + parts[0].asCSSIdentifier() + "_" + paths[2];
	}
	else
		folder = serverFolder;

	return folder;
}

function getSubscribedFolderOwner(serverFolder) {
	var owner;

	var parts = serverFolder.split(":");
	if (parts.length > 1) {
		owner = parts[0];
	}

	return owner;
}

function getListIndexForFolder(items, owner, folderName) {
	var i;
	var previousOwner = null;

	for (var i = 0; i < items.length; i++) {
		var currentFolderName = items[i].lastChild.nodeValue.strip();
		var currentOwner = items[i].readAttribute('owner');
		if (currentOwner == owner) {
			previousOwner = currentOwner;
			if (currentFolderName > folderName)
				break;
		}
		else if (previousOwner || 
						 (currentOwner != UserLogin && currentOwner > owner))
			break;
		else if (currentOwner == "nobody")
			break;
	}

	return i;
}

function listRowMouseDownHandler(event) {
	preventDefault(event);
}

/* tabs */
function initTabs() {
	var containers = document.getElementsByClassName("tabsContainer");
	for (var x = 0; x < containers.length; x++) {
		var container = containers[x];
		var list = container.childNodesWithTag("ul");

		if (list.length > 0) {
			var firstTab = null;
			var nodes = $(list[0]).childNodesWithTag("li");
			for (var i = 0; i < nodes.length; i++) {
				var currentNode = $(nodes[i]);
				if (!firstTab)
					firstTab = currentNode;
				currentNode.observe("mousedown", onTabMouseDown);
				currentNode.observe("click", onTabClick);
				//$(currentNode.getAttribute("target")).hide();
			}

			firstTab.addClassName("first");
			firstTab.addClassName("active");
			container.activeTab = firstTab;

			var target = $(firstTab.getAttribute("target"));
			target.addClassName("active");
		}
		//target.show();
	}
}

function initMenus() {
	var menus = getMenus();
	if (menus) {
		for (var menuID in menus) {
			var menuDIV = $(menuID);
			if (menuDIV)
				initMenu(menuDIV, menus[menuID]);
		}
	}
}

function initMenu(menuDIV, callbacks) {
	var uls = menuDIV.childNodesWithTag("ul");
	for (var i = 0; i < uls.length; i++) {
		var lis = $(uls[i]).childNodesWithTag("li");
		for (var j = 0; j < lis.length; j++) {
			var node = $(lis[j]);
			node.observe("mousedown", listRowMouseDownHandler, false);
			var callback;
			if (i > 0)
				callback = callbacks[i+j+1];
			else
				callback = callbacks[i+j];
			if (callback) {
				if (typeof(callback) == "string") {
					if (callback == "-")
						node.addClassName("separator");
					else {
						node.submenu = callback;
						node.addClassName("submenu");
						node.observe("mouseover", popupSubmenu);
					}
				}
				else {
					node.observe("mouseup", onBodyClickMenuHandler);
					node.menuCallback = callback;
					node.observe("click", onMenuClickHandler);
				}
			}
			else
				node.addClassName("disabled");
		}
	}
}

function onTabMouseDown(event) {
	event.stopPropagation();
	event.preventDefault();
}

function openExternalLink(anchor) {
	return false;
}

function openAclWindow(url) {
	var w = window.open(url, "aclWindow",
											"width=420,height=300,resizable=1,scrollbars=1,toolbar=0,"
											+ "location=0,directories=0,status=0,menubar=0"
											+ ",copyhistory=0");
	w.opener = window;
	w.focus();

	return w;
}

function getUsersRightsWindowHeight() {
	return usersRightsWindowHeight;
}

function getUsersRightsWindowWidth() {
	return usersRightsWindowWidth;
}

function getTopWindow() {
	var topWindow = null;
	var currentWindow = window;
	while (!topWindow) {
		if (currentWindow.document.body.hasClassName("popup")
				&& currentWindow.opener)
			currentWindow = currentWindow.opener;
		else
			topWindow = currentWindow;
	}

	return topWindow;
}

function onTabClick(event) {
	var container = this.parentNode.parentNode;
	var content = $(this.getAttribute("target"));
	var oldContent = $(container.activeTab.getAttribute("target"));

	oldContent.removeClassName("active");
	container.activeTab.removeClassName("active"); // previous LI
	container.activeTab = this;
	container.activeTab.addClassName("active"); // current LI
	content.addClassName("active");

	// Prototype alternative

	//oldContent.removeClassName("active");
	//container.activeTab.removeClassName("active"); // previous LI
	//container.activeTab = node;
	//container.activeTab.addClassName("active"); // current LI

	//container.activeTab.hide();
	//oldContent.hide();
	//content.show();

	//container.activeTab = node;
	//container.activeTab.show();
}

function enableAnchor(anchor) {
	var classStr = '' + anchor.getAttribute("class");
	var position = classStr.indexOf("_disabled", 0);
	if (position > -1) {
		var disabledHref = anchor.getAttribute("disabled-href");
		if (disabledHref)
			anchor.setAttribute("href", disabledHref);
		var disabledOnclick = anchor.getAttribute("disabled-onclick");
		if (disabledOnclick)
			anchor.setAttribute("onclick", disabledOnclick);
		anchor.removeClassName("_disabled");
		anchor.setAttribute("disabled-href", null);
		anchor.setAttribute("disabled-onclick", null);
		anchor.disabled = 0;
		anchor.enabled = 1;
	}
}

function disableAnchor(anchor) {
	var classStr = '' + anchor.getAttribute("class");
	var position = classStr.indexOf("_disabled", 0);
	if (position < 0) {
		var href = anchor.getAttribute("href");
		if (href)
			anchor.setAttribute("disabled-href", href);
		var onclick = anchor.getAttribute("onclick");
		if (onclick)
			anchor.setAttribute("disabled-onclick", onclick);
		anchor.addClassName("_disabled");
		anchor.setAttribute("href", "#");
		anchor.setAttribute("onclick", "return false;");
		anchor.disabled = 1;
		anchor.enabled = 0;
	}
}

function d2h(d) {
	var hD = "0123456789abcdef";
	var h = hD.substr(d & 15, 1);

	while (d > 15) {
		d >>= 4;
		h = hD.substr(d & 15, 1) + h;
	}

	return h;
}

function indexColor(number) {
	var color;

	if (number == 0)
		color = "#ccf";
	else {
		var colorTable = new Array(1, 1, 1);

		var currentValue = number;
		var index = 0;
		while (currentValue) {
			if (currentValue & 1)
				colorTable[index]++;
			if (index == 3)
				index = 0;
			currentValue >>= 1;
			index++;
		}

		color = ("#"
						 + d2h((256 / colorTable[2]) - 1)
						 + d2h((256 / colorTable[1]) - 1)
						 + d2h((256 / colorTable[0]) - 1));
	}

	return color;
}

function reloadPreferences() {
	var url = UserFolderURL + "jsonDefaults";
	var http = createHTTPClient();
	http.open("GET", url, false);
	http.send("");

	if (http.status == 200) {
		if (http.responseText.length > 0) {
			UserDefaults = http.responseText.evalJSON(true);
			if (!UserDefaults)
				UserDefaults = {};
		}
		else
			UserDefaults = {};
	}

	url = UserFolderURL + "jsonSettings";
	http.open("GET", url, false);
	http.send("");
	if (http.status == 200) {
		if (http.responseText.length > 0)
			UserSettings = http.responseText.evalJSON(true);
		else
			UserSettings = {};
	}
}

function onLoadHandler(event) {
	queryParameters = parseQueryParameters('' + window.location);
	if (!$(document.body).hasClassName("popup")) {
		initLogConsole();
	}
	initCriteria();
	configureSearchField();
	initMenus();
	initTabs();
	configureDragHandles();
	configureLinkBanner();
	var progressImage = $("progressIndicator");
	if (progressImage)
		progressImage.parentNode.removeChild(progressImage);
	$(document.body).observe("contextmenu", onBodyClickContextMenu);

	onFinalLoadHandler();
}

function onBodyClickContextMenu(event) {
	if (!(event.target
				&& (event.target.tagName == "INPUT"
						|| event.target.tagName == "TEXTAREA")))
		preventDefault(event);
}

function configureSortableTableHeaders(table) {
	var headers = $(table).getElementsByClassName("sortableTableHeader");
	for (var i = 0; i < headers.length; i++) {
		var header = $(headers[i]);
		header.stopObserving("click", onHeaderClick);
		header.observe("click", onHeaderClick);
	}
}

function onLinkBannerClick() {
	activeAjaxRequests++;
	checkAjaxRequestsState();
}

function onPreferencesClick(event) {
	var urlstr = UserFolderURL + "preferences";
	var w = window.open(urlstr, "_blank",
											"width=440,height=250,resizable=0,scrollbars=0,location=0");
	w.opener = window;
	w.focus();

	preventDefault(event);
}

function configureLinkBanner() {
	var linkBanner = $("linkBanner");
	if (linkBanner) {
		var moduleLinks = [ "calendar", "contacts", "mail" ];
		for (var i = 0; i < moduleLinks.length; i++) {
			var link = $(moduleLinks[i] + "BannerLink");
			if (link) {
				link.observe("mousedown", listRowMouseDownHandler);
				link.observe("click", onLinkBannerClick);
			}
		}
		link = $("preferencesBannerLink");
		if (link) {
			link.observe("mousedown", listRowMouseDownHandler);
			link.observe("click", onPreferencesClick);
		}
		link = $("consoleBannerLink");
		if (link) {
			link.observe("mousedown", listRowMouseDownHandler);
			link.observe("click", toggleLogConsole);
		}
	}
}

/* folder creation */
function createFolder(name, okCB, notOkCB) {
	if (name) {
		if (document.newFolderAjaxRequest) {
			document.newFolderAjaxRequest.aborted = true;
			document.newFolderAjaxRequest.abort();
		}
		var url = ApplicationBaseURL + "/createFolder?name=" + name;
		document.newFolderAjaxRequest
			= triggerAjaxRequest(url, createFolderCallback,
													 {name: name,
														okCB: okCB,
														notOkCB: notOkCB});
	}
}

function createFolderCallback(http) {
	if (http.readyState == 4) {
		var data = http.callbackData;
		if (http.status == 201) {
			if (data.okCB)
				data.okCB(data.name, "/" + http.responseText, UserLogin);
		}
		else {
			if (data.notOkCB)
				data.notOkCB(name);
			else
				log("ajax problem:" + http.status);
		}
	}
}

function onFinalLoadHandler(event) {
	var safetyNet = $("javascriptSafetyNet");
	if (safetyNet)
		safetyNet.parentNode.removeChild(safetyNet);
}

function parent$(element) {
	return this.opener.document.getElementById(element);
}

/* stubs */
function refreshCurrentFolder() {
}

function configureDragHandles() {
}

function getMenus() {
}

function onHeaderClick(event) {
	window.alert("generic headerClick");
}

document.observe("dom:loaded", onLoadHandler);
