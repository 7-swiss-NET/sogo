/* -*- Mode: java; tab-width: 2; c-tab-always-indent: t; indent-tabs-mode: t; c-basic-offset: 2 -*- */
/* JavaScript for SOGoContacts */

var cachedContacts = {};

var usersRightsWindowHeight = 200;
var usersRightsWindowWidth = 450;

var Contact = {
 currentAddressBook: null,
 currentContact: null
};

function validateEditorInput(sender) {
  var errortext = "";
  var field;
  
  field = document.pageform.subject;
  if (field.value == "")
    errortext = errortext + labels.error_missingsubject + "\n";

  if (!hasRecipients())
    errortext = errortext + labels.error_missingrecipients + "\n";
  
  if (errortext.length > 0) {
    alert(labels.error_validationfailed + ":\n"
					+ errortext);
    return false;
  }
  return true;
}

function openContactsFolder(contactsFolder, reload, idx) {
  if ((contactsFolder && contactsFolder != Contact.currentAddressBook)
      || reload) {
    Contact.currentAddressBook = contactsFolder;
    var url = URLForFolderID(Contact.currentAddressBook) +
      "/view?noframe=1";

    var searchValue = search["value"];
    if (searchValue && searchValue.length > 0)
      url += ("&search=" + search["criteria"]
							+ "&value=" + escape(searchValue.utf8encode()));
    var sortAttribute = sorting["attribute"];
    if (sortAttribute && sortAttribute.length > 0)
      url += ("&sort=" + sorting["attribute"]
							+ "&asc=" + sorting["ascending"]);

    var selection;
    if (idx) {
      selection = [idx];
    }
    else if (contactsFolder == Contact.currentAddressBook) {
      var contactsList = $("contactsList");
      if (contactsList)
				selection = contactsList.getSelectedRowsId();
			//        else
			//           window.alert("no contactsList");
    }
    else
      selection = null;

    if (document.contactsListAjaxRequest) {
      document.contactsListAjaxRequest.aborted = true;
      document.contactsListAjaxRequest.abort();
    }
    document.contactsListAjaxRequest
      = triggerAjaxRequest(url, contactsListCallback, selection);
  }
}

function openContactsFolderAtIndex(element) {
  var idx = element.getAttribute("idx");
  var url = URLForFolderID(Contact.currentAddressBook) + "/view?noframe=1&idx=" + idx;

  if (document.contactsListAjaxRequest) {
    document.contactsListAjaxRequest.aborted = true;
    document.contactsListAjaxRequest.abort();
  }
  document.contactsListAjaxRequest
    = triggerAjaxRequest(url, contactsListCallback);
}

function contactsListCallback(http) {
  if (http.readyState == 4) {
    if (http.status == 200) {
      document.contactsListAjaxRequest = null;

      var div = $("contactsListContent");
      var table = $("contactsList");
      if (table) {
				// Update table
				var data = http.responseText;
				var html = data.replace(/^(.*\n)*.*(<table(.*\n)*)$/, "$2");
				var tbody = table.tBodies[0];
				var tmp = document.createElement('div');
				$(tmp).update(html);
				table.replaceChild($(tmp).select("table tbody")[0], tbody);
         
				var rows = table.tBodies[0].rows;
				for (var i = 0; i < rows.length; i++) {
					var row = $(rows[i]);
					row.observe("mousedown", onRowClick);
					row.observe("dblclick", onContactRowDblClick);
					row.observe("selectstart", listRowMouseDownHandler);
					row.observe("contextmenu", onContactContextMenu);
				}
      }
      else {
				// Add table (doesn't happen .. yet)
				div.update(http.responseText);
				table = $("contactsList");
				configureSortableTableHeaders(table);
				TableKit.Resizable.init(table, {'trueResize' : true, 'keepWidth' : true});
      }
      
      if (sorting["attribute"] && sorting["attribute"].length > 0) {
				var sortHeader;
				if (sorting["attribute"] == "displayName")
					sortHeader = $("nameHeader");
				else if (sorting["attribute"] == "mail")
					sortHeader = $("mailHeader");
				else if (sorting["attribute"] == "screenName")
					sortHeader = $("screenNameHeader");
				else if (sorting["attribute"] == "org")
					sortHeader = $("orgHeader");
				else if (sorting["attribute"] == "phone")
					sortHeader = $("phoneHeader");
				else
					sortHeader = null;
         
				if (sortHeader) {
					var sortImages = $(table.tHead).select(".sortImage");
					$(sortImages).each(function(item) {
							item.remove();
						});
            
					var sortImage = createElement("img", "messageSortImage", "sortImage");
					sortHeader.insertBefore(sortImage, sortHeader.firstChild);
					if (sorting["ascending"])
						sortImage.src = ResourcesURL + "/title_sortdown_12x12.png";
					else
						sortImage.src = ResourcesURL + "/title_sortup_12x12.png";
				}
      }
      
      var selected = http.callbackData;
      if (selected) {
				for (var i = 0; i < selected.length; i++) {
					var row = $(selected[i]);
					if (row) {
						var rowPosition = row.rowIndex * row.getHeight();
						if (div.getHeight() < rowPosition)
							div.scrollTop = rowPosition; // scroll to selected contact
						row.selectElement();
					}
				}
      }
    }
    else {
      var table = $("contactsList");
      if (table) {
				var sortImages = $(table.tHead).select(".sortImage");
				$(sortImages).each(function(item) {
						item.remove();
					});
				var tBody = $(table.tBodies[0]);
				var length = tBody.rows.length;
				for (var i = length - 1; i > -1; i--)
					tBody.removeChild(tBody.rows[i]);
      }
    }
  }
  else
    log ("ajax problem 1: status = " + http.status);
}

function onAddressBooksContextMenu(event) {
  var menu = $("contactFoldersMenu");
  menu.observe("mousedown", onAddressBooksContextMenuHide);
  popupMenu(event, "contactFoldersMenu", this);

  var topNode = $("contactFolders");
  var selectedNodes = topNode.getSelectedRows();
  topNode.menuSelectedRows = selectedNodes;
  for (var i = 0; i < selectedNodes.length; i++)
    $(selectedNodes[i]).deselect();
  topNode.menuSelectedEntry = this;
  $(this).selectElement();
}

function onContactContextMenu(event) {
  var contactsList = $("contactsList");
  var menu = $("contactMenu");
  menu.observe("hideMenu", onContactContextMenuHide);
  if (contactsList)
    popupMenu(event, "contactMenu", contactsList.getSelectedRows());
}

function onContactContextMenuHide(event) {
  var topNode = $("contactsList");

  if (topNode.menuSelectedEntry) {
    $(topNode.menuSelectedEntry).deselect();
    topNode.menuSelectedEntry = null;
  }
  if (topNode.menuSelectedRows) {
    var nodes = topNode.menuSelectedRows;
    for (var i = 0; i < nodes.length; i++)
      $(nodes[i]).selectElement();
    topNode.menuSelectedRows = null;
  }
}

function onAddressBooksContextMenuHide(event) {
  var topNode = $("contactFolders");

  if (topNode.menuSelectedEntry) {
    topNode.menuSelectedEntry.deselect();
    topNode.menuSelectedEntry = null;
  }
  if (topNode.menuSelectedRows) {
    var nodes = topNode.menuSelectedRows;
    for (var i = 0; i < nodes.length; i++)
      nodes[i].selectElement();
    topNode.menuSelectedRows = null;
  }
}

function onFolderMenuHide(event) {
  var topNode = $('d');

  if (topNode.menuSelectedEntry) {
    topNode.menuSelectedEntry.deselect();
    topNode.menuSelectedEntry = null;
  }
  if (topNode.selectedEntry)
    topNode.selectedEntry.selectElement();
}

function _onContactMenuAction(folderItem, action, refresh) {
  var selectedFolders = $("contactFolders").getSelectedNodes();
  var folderId = $(folderItem).readAttribute("folderId").substring(1);
  if (Object.isArray(document.menuTarget) && selectedFolders.length > 0) {
    var selectedFolderId = $(selectedFolders[0]).readAttribute("id");
    var contactIds = $(document.menuTarget).collect(function(row) {
				return row.getAttribute("id");
      });

    var url = ApplicationBaseURL + selectedFolderId + "/" + action + "?folder=" + folderId + "&uid="
      + contactIds.join("&uid=");
    
    if (refresh)
      triggerAjaxRequest(url, actionContactCallback, selectedFolderId);
    else
      triggerAjaxRequest(url, actionContactCallback);
  }
}

function onContactMenuCopy(event) {
  _onContactMenuAction(this, "copy", false);
}

function onContactMenuMove(event) {
  _onContactMenuAction(this, "move", true);
}

function actionContactCallback(http) {
  if (http.readyState == 4)
    if (isHttpStatus204(http.status)) {
      var refreshFolderId = http.callbackData;
      if (refreshFolderId)
				openContactsFolder(refreshFolderId, true);
    }
    else {
      var html = new Element("div").update(http.responseText);
      var error = html.select("p").first().firstChild.nodeValue.trim();
      log("actionContactCallback failed: error " + http.status + " (" + error + ")");
      if (parseInt(http.status) == 403)
				window.alert(labels["You don't have the required privileges to perform the operation."]);
      else if (error)
				window.alert(labels[error]);
      refreshCurrentFolder();
    }
}

function loadContact(idx) {
  if (document.contactAjaxRequest) {
    document.contactAjaxRequest.aborted = true;
    document.contactAjaxRequest.abort();
  }

  if (cachedContacts[Contact.currentAddressBook + "/" + idx]) {
    var div = $('contactView');
    Contact.currentContact = idx;
    div.innerHTML = cachedContacts[Contact.currentAddressBook + "/" + idx];
  }
  else {
    var url = (URLForFolderID(Contact.currentAddressBook)
							 + "/" + idx + "/view?noframe=1");
    document.contactAjaxRequest
      = triggerAjaxRequest(url, contactLoadCallback, idx);
  }
}

function contactLoadCallback(http) {
  var div = $('contactView');

  if (http.readyState == 4
      && http.status == 200) {
    document.contactAjaxRequest = null;
    var content = http.responseText;
    cachedContacts[Contact.currentAddressBook + "/" + http.callbackData] = content;
    Contact.currentContact = http.callbackData;
    div.innerHTML = content;
  }
  else {
    log ("ajax problem 2: " + http.status);
    refreshCurrentFolder();
  }
}

var rowSelectionCount = 0;

validateControls();

function showElement(e, shouldShow) {
  e.style.display = shouldShow ? "" : "none";
}

function enableElement(e, shouldEnable) {
  if(!e)
    return;
  if(shouldEnable) {
    if(e.hasAttribute("disabled"))
      e.removeAttribute("disabled");
  }
  else {
    e.setAttribute("disabled", "1");
  }
}

function validateControls() {
  var e = $("moveto");
  this.enableElement(e, rowSelectionCount > 0);
}

function moveTo(uri) {
  alert("MoveTo: " + uri);
}

/* contact menu entries */
function onContactRowDblClick(event) {
  var contactId = this.getAttribute('contactid');

  openContactWindow(URLForFolderID(Contact.currentAddressBook)
										+ "/" + contactId + "/edit", contactId);

  return false;
}

function onContactSelectionChange(event) {
  var rows = this.getSelectedRowsId();
  
  if (rows.length == 1) {
    var node = $(rows[0]);
    loadContact(node.getAttribute('contactid'));
  }
  else if (rows.length > 1) {
    $('contactView').update();
    Contact.currentContact = null;
  }
}

function onMenuEditContact(event) {
  onToolbarEditSelectedContacts(event);
}

function onMenuWriteToContact(event) {
  onToolbarWriteToSelectedContacts(event);

  if (document.body.hasClassName("popup"))
    window.close();
}

function onMenuAIMContact(event) {
  var contactRow = $(document.menuTarget.getAttribute('id'));
  var aimCell = contactRow.down('td', 2);

  window.location.href = "aim:goim?ScreenName=" + aimCell.firstChild.nodeValue;
}

function onMenuDeleteContact(event) {
  onToolbarDeleteSelectedContacts(event);
}

function onToolbarEditSelectedContacts(event) {
  var contactsList = $('contactsList');
  var rows = contactsList.getSelectedRowsId();

  if (rows.length == 0) {
    window.alert(labels["Please select a contact."]);
    return false;
  }

  for (var i = 0; i < rows.length; i++) {
    openContactWindow(URLForFolderID(Contact.currentAddressBook)
											+ "/" + rows[i] + "/edit", rows[i]);
  }

  return false;
}

function onToolbarWriteToSelectedContacts(event) {
  var contactsList = $('contactsList');
  var rows = contactsList.getSelectedRowsId();
  var rowsWithEmail = 0;

  if (rows.length == 0) {
    openMailComposeWindow(ApplicationBaseURL + "Mail/compose");
    return false;
  }

  openMailComposeWindow(ApplicationBaseURL + "../Mail/compose"
												+ "?folder=" + Contact.currentAddressBook.substring(1)
												+ "&uid=" + rows.join("&uid="));

  if (document.body.hasClassName("popup"))
    window.close();
  
  return false;
}

function onToolbarDeleteSelectedContacts(event) {
  var contactsList = $('contactsList');
  var rows = contactsList.getSelectedRowsId();

  if (rows.length) {
    var label = labels["Are you sure you want to delete the selected contacts?"];
    if (window.confirm(label)) {
      for (var i = 0; i < rows.length; i++) {
        delete cachedContacts[Contact.currentAddressBook + "/" + rows[i]];
        var urlstr = (URLForFolderID(Contact.currentAddressBook) + "/"
                      + rows[i] + "/delete");
        triggerAjaxRequest(urlstr, onContactDeleteEventCallback,
                           rows[i]);
      }
    }
  }
  else {
    window.alert(labels["Please select a contact."]);
  }

  return false;
}

function onContactDeleteEventCallback(http) {
  if (http.readyState == 4) {
    if (isHttpStatus204(http.status)) {
      var row = $(http.callbackData);
      row.parentNode.removeChild(row);
      if (Contact.currentContact == http.callbackData)
				$("contactView").update();
    }
    else if (parseInt(http.status) == 403) {
      var row = $(http.callbackData);
      var displayName = row.down("TD.displayName").firstChild.nodeValue.trim();
      window.alert(labels["You cannot delete the card of \"%{0}\"."].formatted(displayName));
    }
  }
}

function newEmailTo(sender) {
  var mailto = sanitizeMailTo(sender.parentNode.parentNode.menuTarget.innerHTML);

  if (mailto.length > 0)
    openMailComposeWindow("compose?mailto=" + mailto);

  return false; /* stop following the link */
}

function onHeaderClick(event) {
  var headerId = this.getAttribute("id");
  var newSortAttribute;
  if (headerId == "nameHeader")
    newSortAttribute = "displayName";
  else if (headerId == "mailHeader")
    newSortAttribute = "mail";
  else if (headerId == "screenNameHeader")
    newSortAttribute = "screenName";
  else if (headerId == "orgHeader")
    newSortAttribute = "org";
  else if (headerId == "phoneHeader")
    newSortAttribute = "phone";

  if (sorting["attribute"] == newSortAttribute)
    sorting["ascending"] = !sorting["ascending"];
  else {
    sorting["attribute"] = newSortAttribute;
    sorting["ascending"] = true;
  }

  refreshCurrentFolder();

  Event.stop(event);
}

function newContact(sender) {
  openContactWindow(URLForFolderID(Contact.currentAddressBook) + "/newcontact");

  return false; /* stop following the link */
}

function onFolderSelectionChange(event) {
  var folderList = $("contactFolders");
  var nodes = folderList.getSelectedNodes();

  if (event) {
    var node = getTarget(event);
    if (node.tagName == 'UL')
      return;
  }

  $("contactView").update();
  Contact.currentContact = null;

  if (nodes[0].hasClassName("denied")) {
    var div = $("contactsListContent");
    div.update();
  }
  else {
    search = {};
    sorting = {};
    $("searchValue").value = "";
    initCriteria();
    openContactsFolder(nodes[0].getAttribute("id"));
  }
}

function refreshCurrentFolder() {
  openContactsFolder(Contact.currentAddressBook, true);
}

function onConfirmContactSelection(event) {
  var tag = this.getAttribute("name");
  var folderLi = $(Contact.currentAddressBook);
  var currentAddressBookName = folderLi.innerHTML;
  var selectorList = null;
  var initialValues = null;
	
  var contactsList = $("contactsList");
  var rows = contactsList.getSelectedRows();
  for (i = 0; i < rows.length; i++) {
    var cid = rows[i].getAttribute("contactid");
    var cname = '' + rows[i].getAttribute("contactname");
    var email = '' + rows[i].cells[1].innerHTML;
		
    window.opener.addContact(tag, currentAddressBookName + '/' + cname,
														 cid, cname, email);
  }

  preventDefault(event);
}

function refreshContacts(contactId) {
  openContactsFolder(Contact.currentAddressBook, true, contactId);
  delete cachedContacts[Contact.currentAddressBook + "/" + contactId];
  loadContact(contactId);

  return false;
}

function onAddressBookNew(event) {
  createFolder(window.prompt(labels["Name of the Address Book"], ""),
							 appendAddressBook);
  preventDefault(event);
}

function appendAddressBook(name, folder) {
  var owner;
  var result = true;

  if (folder) {
    owner = getSubscribedFolderOwner(folder);
    folder = accessToSubscribedFolder(folder);
  }
  else
    folder = "/" + name;

  if (!owner)
    owner = UserLogin;

  if ($(folder))
    result = false;
  else {
    var contactFolders = $("contactFolders");
    var items = contactFolders.childNodesWithTag("li");
    var li = document.createElement("li");
    li = Element.extend(li);

    // Add the calendar to the proper place
    var i = getListIndexForFolder(items, owner, name);
    if (i != items.length) // User is subscribed to other calendars of the same owner
      contactFolders.insertBefore(li, items[i]);
    else 
      contactFolders.appendChild(li);

    li.setAttribute("id", folder);
    li.setAttribute("owner", owner);
    li.addClassName("local");
    li.appendChild(document.createTextNode(name
																					 .replace("&lt;", "<", "g")
																					 .replace("&gt;", ">", "g")));
    setEventsOnAddressBook(li);
    updateAddressBooksMenus();
  }

  return result;
}

function newUserFolderCallback(folderData) {
  var folder = $(folderData["folder"]);
  if (!folder)
    appendAddressBook(folderData["folderName"], folderData["folder"]);
}

function onAddressBookAdd(event) {
  openUserFolderSelector(newUserFolderCallback, "contact");

  preventDefault(event);
}

function onFolderUnsubscribeCB(folderId) {
  var node = $(folderId);
  node.parentNode.removeChild(node);
  var personal = $("/personal");
  personal.selectElement();
  onFolderSelectionChange();
}

function onAddressBookRemove(event) {
  var selector = $("contactFolders");
  var nodes = selector.getSelectedNodes();
  if (nodes.length > 0) {
    var node = $(nodes[0]);
    node.deselect();
    var owner = node.getAttribute("owner");
    if (owner == "nobody") {
			var label = labels["You cannot remove nor unsubscribe from a public addressbook."];
			window.alert(label);
    }
    else if (owner == UserLogin) {
      var folderIdElements = node.getAttribute("id").split(":");
      var abId = folderIdElements[0].substr(1);
      deletePersonalAddressBook(abId);
      var personal = $("/personal");
      personal.selectElement();
      onFolderSelectionChange();
    }
    else {
			var folderId = node.getAttribute("id");
			unsubscribeFromFolder(folderId, owner, onFolderUnsubscribeCB, folderId);
    }
  }

  preventDefault(event);
}

function deletePersonalAddressBook(folderId) {
	if (folderId == "personal") {
		var label = labels["You cannot remove nor unsubscribe from your personal addressbook."];
		window.alert(label);
	}
	else {
		var label
			= labels["Are you sure you want to delete the selected address book?"];
		if (window.confirm(label)) {
			if (document.deletePersonalABAjaxRequest) {
				document.deletePersonalABAjaxRequest.aborted = true;
				document.deletePersonalABAjaxRequest.abort();
			}
			var url = ApplicationBaseURL + folderId + "/deleteFolder";
			document.deletePersonalABAjaxRequest
				= triggerAjaxRequest(url, deletePersonalAddressBookCallback,
														 folderId);
		}
	}
}

function deletePersonalAddressBookCallback(http) {
  if (http.readyState == 4) {
    if (isHttpStatus204(http.status)) {
      var ul = $("contactFolders");
	
      var children = ul.childNodesWithTag("li");
      var i = 0;
      var done = false;
      while (!done && i < children.length) {
				var currentFolderId = children[i].getAttribute("id").substr(1);
				if (currentFolderId == http.callbackData) {
					ul.removeChild(children[i]);
					done = true;
				}
				else
					i++;
      }
    }
    document.deletePersonalABAjaxRequest = null;
  }
  else
    log ("ajax problem 5: " + http.status);
}

function configureDragHandles() {
  var handle = $("dragHandle");
  if (handle) {
    handle.addInterface(SOGoDragHandlesInterface);
    handle.leftBlock=$("contactFoldersList");
    handle.rightBlock=$("rightPanel");
    handle.leftMargin = 100;
  }

  handle = $("rightDragHandle");
  if (handle) {
    handle.addInterface(SOGoDragHandlesInterface);
    handle.upperBlock=$("contactsListContent");
    handle.lowerBlock=$("contactView");
  }
}

function lookupDeniedFolders() {
  var list = $("contactFolders").childNodesWithTag("li");
  for (var i = 0; i < list.length; i++) {
    var folderID = list[i].getAttribute("id");
    var url = URLForFolderID(folderID) + "/canAccessContent";
    triggerAjaxRequest(url, deniedFoldersLookupCallback, folderID);
  }
}

function deniedFoldersLookupCallback(http) {
  if (http.readyState == 4) {
    var denied = ! isHttpStatus204(http.status);
    var entry = $(http.callbackData);
    if (denied)
      entry.addClassName("denied");
    else
      entry.removeClassName("denied");
  }
}

function configureAbToolbar() {
  var toolbar = $("abToolbar");
  if (toolbar) {
    var links = toolbar.childNodesWithTag("a");
    $(links[0]).observe("click", onAddressBookNew);
    $(links[1]).observe("click", onAddressBookAdd);
    $(links[2]).observe("click", onAddressBookRemove);
  }
}

function configureAddressBooks() {
  var contactFolders = $("contactFolders");
  if (contactFolders) {
    contactFolders.observe("mousedown", listRowMouseDownHandler);
    contactFolders.observe("click", onFolderSelectionChange);
    var lis = contactFolders.childNodesWithTag("li");
    for (var i = 0; i < lis.length; i++)
      setEventsOnAddressBook(lis[i]);
    
    lookupDeniedFolders();
    
    var personalFolder = $("/personal");
    personalFolder.selectElement();
    openContactsFolder("/personal");
  }
}

function onAddressBookMenuPrepareVisibility() {
  var selectedFolder = $("contactFolders").getSelectedNodes()[0];
  if (selectedFolder) {
    var selectedFolderId = selectedFolder.readAttribute("id");
    $(this).select("li").each(function(menuEntry) {
				if (menuEntry.readAttribute("folderId") == selectedFolderId)
					menuEntry.addClassName("disabled");
				else
					menuEntry.removeClassName("disabled");
      });
  }
}

function updateAddressBooksMenus() {
  var contactFoldersList = $("contactFolders");
  if (contactFoldersList) {
    var pageContent = $("pageContent");
    var contactFolders = contactFoldersList.select("li");
    var contactActions = new Hash({ move: onContactMenuMove,
																		copy: onContactMenuCopy });
    var actions = contactActions.keys();
    for (var j = 0; j < actions.size(); j++) {
      var key = actions[j];
			var callbacks = new Array();
			var menuId = key + "ContactMenu";
			var menuDIV = $(menuId);
			if (menuDIV)
				menuDIV.parentNode.removeChild(menuDIV);
	
			menuDIV = document.createElement("div");
			pageContent.appendChild(menuDIV);
	
			var menu = document.createElement("ul");
			menuDIV.appendChild(menu);
	
			$(menuDIV).addClassName("menu");
			menuDIV.setAttribute("id", menuId);
	
			var submenuIds = new Array();
			for (var i = 0; i < contactFolders.length; i++) {
				if (contactFolders[i].hasClassName("local")) {
					var menuEntry = new Element("li",
																			{ folderId: contactFolders[i].readAttribute("id"),
																				owner: contactFolders[i].readAttribute("owner") }
																			).update(contactFolders[i].innerHTML);
					menu.appendChild(menuEntry);
					callbacks.push(contactActions.get(key));
				}
			}
			menuDIV.prepareVisibility = onAddressBookMenuPrepareVisibility;
			initMenu(menuDIV, callbacks);
		}
  }
}
  
function setEventsOnAddressBook(folder) {
  var node = $(folder);

  node.observe("mousedown", listRowMouseDownHandler);
  node.observe("click", onRowClick);
  node.observe("dblclick", onAddressBookModify);
  node.observe("contextmenu", onAddressBooksContextMenu);
}

function onAddressBookModify(event) {
  var folders = $("contactFolders");
  var selected = folders.getSelectedNodes()[0];

  if (UserLogin == selected.getAttribute("owner")) {
    var currentName = selected.innerHTML;
    var newName = window.prompt(labels["Address Book Name"],
																currentName);
    if (newName && newName.length > 0
				&& newName != currentName) {
      var url = (URLForFolderID(selected.getAttribute("id"))
								 + "/renameFolder?name=" + escape(newName.utf8encode()));
      triggerAjaxRequest(url, folderRenameCallback,
												 {node: selected, name: newName});
    }
  } else
    window.alert(clabels["Unable to rename that folder!"]);
}

function folderRenameCallback(http) {
  if (http.readyState == 4) {
    if (isHttpStatus204(http.status)) {
      var dict = http.callbackData;
      dict["node"].innerHTML = dict["name"];
    }
  }
}

function onMenuSharing(event) {
  if ($(this).hasClassName("disabled"))
    return;

  var folders = $("contactFolders");
  var selected = folders.getSelectedNodes()[0];
  var owner = selected.getAttribute("owner");
  if (owner == "nobody")
    window.alert(clabels["The user rights cannot be"
												 + " edited for this object!"]);
  else {
    var title = this.innerHTML;
    var url = URLForFolderID(selected.getAttribute("id"));

    openAclWindow(url + "/acls", title);
  }
}

function onAddressBooksMenuPrepareVisibility() {
  var folders = $("contactFolders");
  var selected = folders.getSelectedNodes();

  if (selected.length > 0) {
    var folderOwner = selected[0].getAttribute("owner");

    var menu = $("contactFoldersMenu").down("ul");;
    var listElements = menu.childNodesWithTag("li");
    var modifyOption = $(listElements[0]);
    var removeOption = $(listElements[5]);
    var sharingOption = $(listElements[listElements.length - 1]);

    // Disable the "Sharing" and "Modify" options when address book
    // is not owned by user
    if (folderOwner == UserLogin || IsSuperUser) {
      modifyOption.removeClassName("disabled");
      sharingOption.removeClassName("disabled");
    }
    else {
      modifyOption.addClassName("disabled");
      sharingOption.addClassName("disabled");
    }

    // disable the "remove" option when address book is public, otherwise
    // enable it
    if (folderOwner == "nobody")
      removeOption.addClassName("disabled");
    else
      removeOption.removeClassName("disabled");
  }
}

function onContactMenuPrepareVisibility() {
  var contactRows = document.menuTarget;
  var selectedFolder = $("contactFolders").getSelectedNodes()[0];
  var options = { write: false,
                  aim: false };

  var elements = $(this).down("ul").childElements();
  var writeOption = elements[2];
  var aimOption = elements[3];
  var deleteOption = elements[5];
  var moveOption = elements[7];

  $A(contactRows).each(function(contactRow) {
      var emailCell = contactRow.down('td', 1);
      options.write |= (emailCell.firstChild != null);
      var aimCell = contactRow.down('td', 2);
      options.aim |= (aimCell.firstChild != null);
    });

  if (options.write)
    writeOption.removeClassName("disabled");
  else
    writeOption.addClassName("disabled");
  if (options.aim)
    aimOption.removeClassName("disabled");
  else
    aimOption.addClassName("disabled");

  if ($(selectedFolder).hasClassName("remote")) {
    // Remote address books are always read-only
    deleteOption.addClassName("disabled");
    moveOption.addClassName("disabled");
  }
  else {
    deleteOption.removeClassName("disabled");
    moveOption.removeClassName("disabled");
  }
}

function getMenus() {
  var menus = {};
  menus["contactFoldersMenu"] = new Array(onAddressBookModify, "-", newContact,
																					null, "-", onAddressBookRemove, "-",
																					onMenuSharing);
  menus["contactMenu"] = new Array(onMenuEditContact, "-",
																	 onMenuWriteToContact, onMenuAIMContact,
																	 "-", onMenuDeleteContact, "-",
																	 "moveContactMenu", "copyContactMenu");
  menus["searchMenu"] = new Array(setSearchCriteria);
   
  var contactFoldersMenu = $("contactFoldersMenu");
  if (contactFoldersMenu)
    contactFoldersMenu.prepareVisibility = onAddressBooksMenuPrepareVisibility;
  var contactMenu = $("contactMenu");
  if (contactMenu)
    contactMenu.prepareVisibility = onContactMenuPrepareVisibility;
   
  return menus;
}

function configureSelectionButtons() {
  var container = $("contactSelectionButtons");
  if (container) {
    var buttons = container.select("input");
    for (var i = 0; i < buttons.length; i++)
      $(buttons[i]).observe("click", onConfirmContactSelection);
  }
}

function onWindowResize(event) {
  var handle = $("dragHandle");
  if (handle)
		handle.adjust();
  handle = $("rightDragHandle");
  if (handle)
		handle.adjust();
}

function initContacts(event) {
  if (document.body.hasClassName("popup"))
    configureSelectionButtons();
  configureAbToolbar();
  configureAddressBooks();
  updateAddressBooksMenus();
  //     initDnd();

  var table = $("contactsList");
  if (table) {
    // Initialize contacts table
    table.multiselect = true;
    table.observe("mousedown", onContactSelectionChange);
    configureSortableTableHeaders(table);
    TableKit.Resizable.init(table, {'trueResize' : true, 'keepWidth' : true});
  }
	
	Event.observe(window, "resize", onWindowResize);
	onWindowResize(null);

  // Default sort options
  sorting["attribute"] = "displayName";
  sorting["ascending"] = true;
}

FastInit.addOnLoad(initContacts);
