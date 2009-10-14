/* -*- Mode: java; indent-tabs-mode: nil; c-basic-offset: 4 -*- */

/* JavaScript for SOGoMail */
var accounts = {};
var mailboxTree;
var mailAccounts;
if (typeof textMailAccounts != 'undefined') {
    if (textMailAccounts.length > 0)
        mailAccounts = textMailAccounts.evalJSON(true);
    else
        mailAccounts = new Array();
}
 
var defaultColumnsOrder;
if (typeof textDefaultColumnsOrder != 'undefined') {
    if (textDefaultColumnsOrder.length > 0)
        defaultColumnsOrder = textDefaultColumnsOrder.evalJSON(true);
    else
        defaultColumnsOrder = new Array();
}

var Mailer = {
    currentMailbox: null,
    currentMailboxType: "",
    currentMessages: {},
    maxCachedMessages: 20,
    cachedMessages: new Array(),
    foldersStateTimer: false,
    popups: new Array(),
    quotas: null
};

var usersRightsWindowHeight = 320;
var usersRightsWindowWidth = 400;

var pageContent;

var deleteMessageRequestCount = 0;

var messageCheckTimer;

/* We need to override this method since it is adapted to GCS-based folder
   references, which we do not use here */
function URLForFolderID(folderID) {
    var url = ApplicationBaseURL + encodeURI(folderID);

    if (url[url.length-1] == '/')
        url = url.substr(0, url.length-1);

    return url;
}

/* mail list */

function openMessageWindow(msguid, url) {
    var wId = '';
    if (msguid) {
        wId += "SOGo_msg" + msguid;
        markMailReadInWindow(window, msguid);
    }
    var msgWin = openMailComposeWindow(url, wId);
    msgWin.messageUID = msguid;
    msgWin.focus();
    Mailer.popups.push(msgWin);

    return false;
}

function onMessageDoubleClick(event) {
    var action;

    if (Mailer.currentMailboxType == "draft")
        action = "edit";
    else
        action = "popupview";

    return openMessageWindowsForSelection(action, true);
}

function toggleMailSelect(sender) {
    var row;
    row = $(sender.name);
    row.className = sender.checked ? "tableview_selected" : "tableview";
}

function openAddressbook(sender) {
    var urlstr;

    urlstr = ApplicationBaseURL + "../Contacts/?popup=YES";
    var w = window.open(urlstr, "Addressbook",
                        "width=640,height=400,resizable=1,scrollbars=1,toolbar=0,"
                        + "location=no,directories=0,status=0,menubar=0,copyhistory=0");
    w.focus();

    return false;
}

function onMenuSharing(event) {
    var folderID = document.menuTarget.getAttribute("dataname");
    var type = document.menuTarget.getAttribute("datatype");

    if (type == "additional")
        window.alert(clabels["The user rights cannot be"
                             + " edited for this object!"]);
    else {
        var urlstr = URLForFolderID(folderID) + "/acls";
        openAclWindow(urlstr);
    }
}

/* mail list DOM changes */

function flagMailInWindow (win, msguid, flagged) {
    var row = win.$("row_" + msguid);

    if (row) {
        var col = row.select("TD.messageFlag").first();
        var img = col.select("img").first();
        if (flagged) {
            img.setAttribute("src", ResourcesURL + "/flag.png");
            img.addClassName("messageIsFlagged");
        }
        else {
            img.setAttribute("src", ResourcesURL + "/dot.png");
            img.removeClassName ("messageIsFlagged");
        }
    }
}

function markMailInWindow(win, msguid, markread) {
    var row = win.$("row_" + msguid);
    var subjectCell = win.$("div_" + msguid);
    var unseenCount = 0;

    if (row && subjectCell) {
        if (markread) {
            if (row.hasClassName("mailer_unreadmail")) {
                row.removeClassName("mailer_unreadmail");
                subjectCell.addClassName("mailer_readmailsubject");
                var img = win.$("unreaddiv_" + msguid);
                if (img) {
                    img.removeClassName("mailerUnreadIcon");
                    img.addClassName("mailerReadIcon");
                    img.setAttribute("id", "readdiv_" + msguid);
                    img.setAttribute("src", ResourcesURL + "/dot.png");
                    var title = img.getAttribute("title-markunread");
                    if (title)
                        img.setAttribute("title", title);
                }
                unseenCount = -1;
            }
        }
        else {
            if (!row.hasClassName("mailer_unreadmail")) {
                row.addClassName("mailer_unreadmail");
                subjectCell.removeClassName('mailer_readmailsubject');
                var img = win.$("readdiv_" + msguid);
                if (img) {
                    img.removeClassName("mailerReadIcon");
                    img.addClassName("mailerUnreadIcon");
                    img.setAttribute("id", "unreaddiv_" + msguid);
                    img.setAttribute("src", ResourcesURL + "/icon_unread.gif");
                    var title = img.getAttribute("title-markread");
                    if (title)
                        img.setAttribute("title", title);
                }
                unseenCount = 1;
            }
        }
    }

    if (unseenCount != 0) {
        /* Update unseen count only if it's the inbox */
        for (var i = 0; i < mailboxTree.aNodes.length; i++)
            if (mailboxTree.aNodes[i].datatype == "inbox") break;
        if (i != mailboxTree.aNodes.length && Mailer.currentMailbox == mailboxTree.aNodes[i].dataname)
            updateStatusFolders(unseenCount, true);
    }

    return (unseenCount != 0);
}

function markMailReadInWindow(win, msguid) {
    /* this is called by UIxMailView with window.opener */
    return markMailInWindow(win, msguid, true);
}

/* mail list reply */

function openMessageWindowsForSelection(action, firstOnly) {
    if ($(document.body).hasClassName("popup")) {
        var url = window.location.href;
        var parts = url.split("/");
        parts[parts.length-1] = action;
        window.location.href = parts.join("/");
    }
    else {
        var messageList = $("messageList");
        var rows = messageList.getSelectedRowsId();
        if (rows.length > 0) {
            for (var i = 0; i < rows.length; i++) {
                openMessageWindow(Mailer.currentMailbox + "/" + rows[i].substr(4),
                                  ApplicationBaseURL + encodeURI(Mailer.currentMailbox)
                                  + "/" + rows[i].substr(4)
                                  + "/" + action);
                if (firstOnly)
                    break;
            }
        } else {
            window.alert(getLabel("Please select a message."));
        }
    }

    return false;
}

function mailListMarkMessage(event) {
    var msguid = this.id.split('_')[1];
    var action;
    var markread;
    if ($(this).hasClassName('mailerUnreadIcon')) {
        action = 'markMessageRead';
        markread = true;
    }
    else {
        action = 'markMessageUnread';
        markread = false;
    }
    var url = ApplicationBaseURL + encodeURI(Mailer.currentMailbox) + "/" 
      + msguid + "/" + action;

    var data = { "window": window, "msguid": msguid, "markread": markread };
    triggerAjaxRequest(url, mailListMarkMessageCallback, data);

    preventDefault(event);
    return false;
}

function mailListMarkMessageCallback(http) {
    if (isHttpStatus204(http.status)) {
        var data = http.callbackData;
        markMailInWindow(data["window"], data["msguid"], data["markread"]);
    }
    else {
        alert("Message Mark Failed (" + http.status + "): " + http.statusText);
        window.location.reload();
    }
}


function mailListFlagMessageToggle (e) {
    var msguid = this.ancestors ().first ().id.split ("_")[1];
    var img = this.childElements ().first ();

    var action = "markMessageFlagged";
    var flagged = true;
    if (img.hasClassName ("messageIsFlagged")) {
        action = "markMessageUnflagged";
        flagged = false;
    }
        
    var url = ApplicationBaseURL + encodeURI(Mailer.currentMailbox) + "/" 
      + msguid + "/" + action;
    var data = { "window": window, "msguid": msguid, "flagged": flagged };

    triggerAjaxRequest(url, mailListFlagMessageToggleCallback, data);
}
function mailListFlagMessageToggleCallback (http) {
    if (isHttpStatus204(http.status)) {
        var data = http.callbackData;
        flagMailInWindow(data["window"], data["msguid"], data["flagged"]);
    }
    else {
        alert("Message Mark Failed (" + http.status + "): " + http.statusText);
        window.location.reload();
    }
}

/* maillist row highlight */

var oldMaillistHighlight = null; // to remember deleted/selected style

function ml_highlight(sender) {
    oldMaillistHighlight = sender.className;
    if (oldMaillistHighlight == "tableview_highlight")
        oldMaillistHighlight = null;
    sender.className = "tableview_highlight";
}

function ml_lowlight(sender) {
    if (oldMaillistHighlight) {
        sender.className = oldMaillistHighlight;
        oldMaillistHighlight = null;
    }
    else
        sender.className = "tableview";
}


function onUnload(event) {
    var url = ApplicationBaseURL + encodeURI(Mailer.currentMailbox) + "/expunge";
	
    new Ajax.Request(url, {
            asynchronous: false,
                method: 'get',
                onFailure: function(transport) {
                log("Can't expunge current folder: " + transport.status);
            }
    });

    return true;
}

function onDocumentKeydown(event) {
    var target = Event.element(event);
    if (target.tagName != "INPUT")
        if (event.keyCode == Event.KEY_DELETE ||
            event.keyCode == Event.KEY_BACKSPACE && isMac()) {
            deleteSelectedMessages();
            Event.stop(event);
        }
        else if (event.keyCode == Event.KEY_DOWN ||
                 event.keyCode == Event.KEY_UP) {
            if (Mailer.currentMessages[Mailer.currentMailbox]) {
                var row = $("row_" + Mailer.currentMessages[Mailer.currentMailbox]);
                var nextRow;
                if (event.keyCode == Event.KEY_DOWN)
                    nextRow = row.next("tr");
                else
                    nextRow = row.previous("tr");
                if (nextRow) {
                    Mailer.currentMessages[Mailer.currentMailbox] = nextRow.getAttribute("id").substr(4);
                    row.up().deselectAll();
					
                    // Adjust the scollbar
                    var viewPort = $("mailboxContent");
                    var divDimensions = viewPort.getDimensions();
                    var rowScrollOffset = nextRow.cumulativeScrollOffset();
                    var rowPosition = nextRow.positionedOffset();
                    var divBottom = divDimensions.height + rowScrollOffset.top;
                    var rowBottom = rowPosition.top + nextRow.getHeight();

                    if (divBottom < rowBottom)
                        viewPort.scrollTop += rowBottom - divBottom;
                    else if (rowScrollOffset.top > rowPosition.top)
                        viewPort.scrollTop -= rowScrollOffset.top - rowPosition.top;
					
                    // Select and load the next message
                    nextRow.selectElement();
                    loadMessage(Mailer.currentMessages[Mailer.currentMailbox]);
                }
                Event.stop(event);
            }
        }
}

/* bulk delete of messages */

function deleteSelectedMessages(sender) {
    var messageList = $("messageList").down("TBODY");
    var rows = messageList.getSelectedNodes();
    var uids = new Array(); // message IDs
    var paths = new Array(); // row IDs

    if (rows.length > 0) {
        for (var i = 0; i < rows.length; i++) {
            var uid = rows[i].readAttribute("id").substr(4);
            var path = Mailer.currentMailbox + "/" + uid;
            deleteMessageRequestCount++;
            rows[i].hide();
            uids.push(uid);
            paths.push(path);
        }
        var url = ApplicationBaseURL + encodeURI(Mailer.currentMailbox) + "/batchDelete";
        var parameters = "uid=" + uids.join(",");
        var data = { "id": uids, "mailbox": Mailer.currentMailbox, "path": paths };
        triggerAjaxRequest(url, deleteSelectedMessagesCallback, data, parameters,
                           { "Content-type": "application/x-www-form-urlencoded" });
    }
    else
        window.alert(getLabel("Please select a message."));
   
    return false;
}

function deleteSelectedMessagesCallback(http) {
    if (isHttpStatus204(http.status)) {
        var data = http.callbackData;
        for (var i = 0; i < data["path"].length; i++) {
            deleteCachedMessage(data["path"][i]);
            deleteMessageRequestCount--;
            if (Mailer.currentMailbox == data["mailbox"]) {
                var div = $('messageContent');
                if (Mailer.currentMessages[Mailer.currentMailbox] == data["id"][i]) {
                    div.update();
                    Mailer.currentMessages[Mailer.currentMailbox] = null;	
                }
                var row = $("row_" + data["id"][i]);
                if (deleteMessageRequestCount == 0) {
                    var nextRow = row.next("tr");
                    if (!nextRow)
                        nextRow = row.previous("tr");
                    //	row.addClassName("deleted"); // when we'll offer "mark as deleted"
                    if (nextRow) {
                        Mailer.currentMessages[Mailer.currentMailbox] = nextRow.getAttribute("id").substr(4);
                        nextRow.selectElement();
                        loadMessage(Mailer.currentMessages[Mailer.currentMailbox]);
                    }
                    else {
                        div.update();
                    }
                    refreshCurrentFolder();
                }
                row.parentNode.removeChild(row);
            }
        }
    }
    else
        log ("deleteSelectedMessagesCallback: problem during ajax request " + http.status);
}

function onMenuDeleteMessage(event) {
    deleteSelectedMessages();
    preventDefault(event);
}

function deleteMessage(url, id, mailbox, messageId) {
    var data = { "id": new Array(id), "mailbox": mailbox, "path": new Array(messageId) };
    var parameters = "uid=" + id;
    deleteMessageRequestCount++;
    triggerAjaxRequest(url, deleteSelectedMessagesCallback, data, parameters,
                       { "Content-type": "application/x-www-form-urlencoded" });
}

function deleteMessageWithDelay(url, id, mailbox, messageId) {
    /* this is called by UIxMailPopupView with window.opener */
    var row = $("row_" + id);
    if (row) row.hide();
    setTimeout("deleteMessage('" +
               url + "', '" +
               id + "', '" +
               mailbox + "', '" +
               messageId + "')",
               50);
}

function onPrintCurrentMessage(event) {
    var rowIds = $("messageList").getSelectedRowsId();
    if (rowIds.length == 0) {
        window.alert(getLabel("Please select a message to print."));
    }
    else if (rowIds.length > 1) {
        window.alert(getLabel("Please select only one message to print."));
    }
    else
        window.print();

    preventDefault(event);
}

function onMailboxTreeItemClick(event) {
    var topNode = $("mailboxTree");
    var mailbox = this.parentNode.getAttribute("dataname");
    if (topNode.selectedEntry)
        topNode.selectedEntry.deselect();
    this.selectElement();
    topNode.selectedEntry = this;

    search = {};
    sorting = {};
    $("searchValue").value = "";
    initCriteria();

    Mailer.currentMailboxType = this.parentNode.getAttribute("datatype");
    if (Mailer.currentMailboxType == "account" || Mailer.currentMailboxType == "additional") {
        Mailer.currentMailbox = mailbox;
        $("messageContent").update();
        var table = $("messageList");
        var head = table.tHead;
        var body = table.tBodies[0];
        if (body.deselectAll) body.deselectAll ();
        for (var i = body.rows.length; i > 0; i--)
            body.deleteRow(i-1);
        if (head.rows[1])
            head.rows[1].firstChild.update();
    }
    else
        openMailbox(mailbox);
   
    Event.stop(event);
}

function onMailboxMenuMove(event) {
    var targetMailbox;
    var messageList = $("messageList").down("TBODY");
    var rows = messageList.getSelectedNodes();
    var uids = new Array(); // message IDs
    var paths = new Array(); // row IDs
    
    Mailer.currentMessages[Mailer.currentMailbox] = null;
    $('messageContent').update();

    if (this.tagName == 'LI') // from contextual menu
        targetMailbox = this.mailbox.fullName();
    else // from DnD
        targetMailbox = this.readAttribute("dataname");

    for (var i = 0; i < rows.length; i++) {
        var uid = rows[i].readAttribute("id").substr(4);
        var path = Mailer.currentMailbox + "/" + uid;
        rows[i].hide();
        uids.push(uid);
        paths.push(path);
        // Remove references to closed popups
        for (var j = Mailer.popups.length - 1; j > -1; j--)
            if (!Mailer.popups[j].open || Mailer.popups[j].closed)
                Mailer.popups.splice(j,1);
        // Close message popup if opened
        for (var j = 0; j < Mailer.popups.length; j++)
            if (Mailer.popups[j].messageUID == path) {
                Mailer.popups[j].close();
                Mailer.popups.splice(j,1);
                break;
            }
    }
    var url = ApplicationBaseURL + encodeURI(Mailer.currentMailbox) + "/moveMessages";
    var parameters = "uid=" + uids.join(",") + "&folder=" + targetMailbox;
    var data = { "id": uids, "mailbox": Mailer.currentMailbox, "path": paths, "folder": targetMailbox, "refresh": true };
    triggerAjaxRequest(url, folderRefreshCallback, data, parameters,
                       { "Content-type": "application/x-www-form-urlencoded" });

    return false;
}

function onMailboxMenuCopy(event) {
    var targetMailbox;
    var messageList = $("messageList").down("TBODY");
    var rows = messageList.getSelectedNodes();
    var uids = new Array(); // message IDs
    var paths = new Array(); // row IDs

    if (this.tagName == 'LI') // from contextual menu
        targetMailbox = this.mailbox.fullName();
    else // from DnD
        targetMailbox = this.readAttribute("dataname");
	
    for (var i = 0; i < rows.length; i++) {
        var uid = rows[i].readAttribute("id").substr(4);
        var path = Mailer.currentMailbox + "/" + uid;
        uids.push(uid);
        paths.push(path);
    }
    var url = ApplicationBaseURL + encodeURI(Mailer.currentMailbox) + "/copyMessages";
    var parameters = "uid=" + uids.join(",") + "&folder=" + targetMailbox;
    var data = { "id": uids, "mailbox": Mailer.currentMailbox, "path": paths, "folder": targetMailbox, "refresh": false };
    triggerAjaxRequest(url, folderRefreshCallback, data, parameters,
                       { "Content-type": "application/x-www-form-urlencoded" });

    return false;
}

function refreshMailbox() {
    var topWindow = getTopWindow();
    if (topWindow)
        topWindow.refreshCurrentFolder();

    return false;
}

function onComposeMessage() {
    var topWindow = getTopWindow();
    if (topWindow)
        topWindow.composeNewMessage();

    return false;
}

function composeNewMessage() {
    var account = Mailer.currentMailbox.split("/")[1];
    var url = ApplicationBaseURL + "/" + encodeURI(account) + "/compose";
    openMailComposeWindow(url);
}

function openMailbox(mailbox, reload, idx, updateStatus) {
    if (mailbox != Mailer.currentMailbox || reload) {
        Mailer.currentMailbox = mailbox;
        var url = ApplicationBaseURL + encodeURI(mailbox) + "/view?noframe=1";
    
        if (!reload || idx) {
            var messageContent = $("messageContent");
            messageContent.update();
            lastClickedRow = -1; // from generic.js
        }

        var currentMessage;

        if (!idx) {
            currentMessage = Mailer.currentMessages[mailbox];
            if (currentMessage) {
                url += '&pageforuid=' + currentMessage;
                if (!reload)
                    loadMessage(currentMessage);
            }
        }

        var searchValue = search["value"];
        if (searchValue && searchValue.length > 0)
            url += ("&search=" + search["criteria"]
                    + "&value=" + escape(searchValue.utf8encode()));
        var sortAttribute = sorting["attribute"];
        if (sortAttribute && sortAttribute.length > 0)
            url += ("&sort=" + sorting["attribute"]
                    + "&asc=" + sorting["ascending"]);
        if (idx)
            url += "&idx=" + idx;

        if (document.messageListAjaxRequest) {
            document.messageListAjaxRequest.aborted = true;
            document.messageListAjaxRequest.abort();
        }

        var mailboxContent = $("mailboxContent");
        if (mailboxContent.getStyle('visibility') == "hidden") {
            mailboxContent.setStyle({ visibility: "visible" });
            var rightDragHandle = $("rightDragHandle");
            rightDragHandle.setStyle({ visibility: "visible" });
            messageContent.setStyle({ top: (rightDragHandle.offsetTop
                                            + rightDragHandle.offsetHeight
                                            + 'px') });
        }
        document.messageListAjaxRequest
            = triggerAjaxRequest(url, messageListCallback,
                                 currentMessage);

        if (updateStatus != false)
            getStatusFolders();
    }
}

function openMailboxAtIndex(event) {
    openMailbox(Mailer.currentMailbox, true, this.getAttribute("idx"));

    Event.stop(event);
}

function messageListCallback(http) {
    var div = $('mailboxContent');
    var table = $('messageList');

    var columnsOrder = UserSettings["SOGoMailListViewColumnsOrder"];
    if ( typeof(columnsOrder) == "undefined" ) {
        columnsOrder = defaultColumnsOrder;
    }
    var addrIndex = 3;
    for(var i=0; i<columnsOrder.length; i++) {
        if (columnsOrder[i] == "From" || columnsOrder[i] == "To") {
            addrIndex = i;
        }
    }

    if (http.status == 200) {
        document.messageListAjaxRequest = null;

        if (table) {
            // Update table
            var thead = table.tHead;
            var addressHeaderCell = thead.rows[0].cells[addrIndex];
            var tbody = table.tBodies[0];
            var tmp = document.createElement('div');
            $(tmp).update(http.responseText);

            var newRows = tmp.firstChild.tHead.rows;
            thead.rows[1].parentNode.replaceChild(newRows[1], thead.rows[1]);
            addressHeaderCell.replaceChild(newRows[0].cells[addrIndex].lastChild,
                                           addressHeaderCell.lastChild);
            addressHeaderCell.setAttribute("id", newRows[0].cells[addrIndex].getAttribute("id"));
            table.replaceChild(tmp.firstChild.tBodies[0], tbody);
            configureMessageListEvents(table);
         }
        else {
            // Add table
            div.update(http.responseText);
            table = $("messageList");
            configureMessageListEvents(table);
            TableKit.Resizable.init(table, {'trueResize' : true, 'keepWidth' : true});
            configureDraggables();
        }
        configureMessageListBodyEvents(table);

        var selected = http.callbackData;
        if (selected) {
            var row = $("row_" + selected);
            if (row) {
                row.selectElement();
                lastClickedRow = row.rowIndex - $(row).up('table').down('thead').getElementsByTagName('tr').length;  
                var rowPosition = row.rowIndex * row.getHeight();
                if (rowPosition < div.scrollTop 
                    || rowPosition > div.scrollTop + div.getHeight ())
                  div.scrollTop = rowPosition; // scroll to selected message
            }
            else
                $("messageContent").update();
        }
        else
            div.scrollTop = 0;
    
        if (sorting["attribute"] && sorting["attribute"].length > 0) {
            var sortHeader = $(sorting["attribute"] + "Header");
      
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
    }
    else {
        var data = http.responseText;
        var msg = data.replace(/^(.*\n)*.*<p>((.*\n)*.*)<\/p>(.*\n)*.*$/, "$2");
        log("messageListCallback: problem during ajax request (readyState = " + http.readyState + ", status = " + http.status + ", response = " + msg + ")");
    }
    initFlagIcons ();
}

function getStatusFolders() {
    var account = Mailer.currentMailbox.split("/")[1];
    var url = ApplicationBaseURL + encodeURI(account) + '/statusFolders';
    if (document.statusFoldersAjaxRequest) {
        document.statusFoldersAjaxRequest.aborted = true;
        document.statusFoldersAjaxRequest.abort();
    }
    document.statusFoldersAjaxRequest = triggerAjaxRequest(url, statusFoldersCallback);
}

function statusFoldersCallback(http) {
    var div = $('mailboxContent');
    var table = $('messageList');
  
    if (http.status == 200) {
        document.statusFoldersAjaxRequest = null;
        var data = http.responseText.evalJSON(true);
        updateStatusFolders(data.unseen, false);
    }
}

function updateStatusFolders(count, isDelta) {
    var span = $("unseenCount");
    var counter = null;
  
    if (span)
        counter = span.select("SPAN").first();

    if (counter && span) {
        if (typeof count == "undefined")
            count = parseInt(counter.innerHTML);
        else if (isDelta)
            count += parseInt(counter.innerHTML);
        counter.update(count);
  	if (count > 0) {
            span.setStyle({ display: "inline" });
            span.up("SPAN").addClassName("unseen");
  	}
        else {
            span.setStyle({ display: "none" });
            span.up("SPAN").removeClassName("unseen");
        }
    }
}

function onMessageContextMenu(event) {
    var menu = $('messageListMenu');
    var topNode = $('messageList');
    var selectedNodes = topNode.getSelectedRows();

    menu.observe("hideMenu", onMessageContextMenuHide);
  
    if (selectedNodes.length > 1)
        popupMenu(event, "messagesListMenu", selectedNodes);
    else
        popupMenu(event, "messageListMenu", this);    
}

function onMessageContextMenuHide(event) {
    var topNode = $('messageList');

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

function onFolderMenuClick(event) {
    var onhide, menuName;

    var menutype = this.parentNode.getAttribute("datatype");
    if (menutype) {
        if (menutype == "inbox") {
            menuName = "inboxIconMenu";
        } else if (menutype == "account") {
            menuName = "accountIconMenu";
        } else if (menutype == "trash") {
            menuName = "trashIconMenu";
        } else {
            menuName = "mailboxIconMenu";
        }
    } else {
        menuName = "mailboxIconMenu";
    }

    var menu = $(menuName);
    menu.observe("hideMenu", onFolderMenuHide);
    popupMenu(event, menuName, this.parentNode);

    var topNode = $("mailboxTree");
    if (topNode.selectedEntry)
        topNode.selectedEntry.deselect();
    if (topNode.menuSelectedEntry)
        topNode.menuSelectedEntry.deselect();
    topNode.menuSelectedEntry = this;
    this.selectElement();

    preventDefault(event);
}

function onFolderMenuHide(event) {
    var topNode = $("mailboxTree");

    if (topNode.menuSelectedEntry) {
        topNode.menuSelectedEntry.deselect();
        topNode.menuSelectedEntry = null;
    }
    if (topNode.selectedEntry)
        topNode.selectedEntry.selectElement();
}

function deleteCachedMessage(messageId) {
    var done = false;
    var counter = 0;

    while (counter < Mailer.cachedMessages.length
           && !done)
        if (Mailer.cachedMessages[counter]
            && Mailer.cachedMessages[counter]['idx'] == messageId) {
            Mailer.cachedMessages.splice(counter, 1);
            done = true;
        }
        else
            counter++;
}

function getCachedMessage(idx) {
    var message = null;
    var counter = 0;

    while (counter < Mailer.cachedMessages.length
           && message == null)
        if (Mailer.cachedMessages[counter]
            && Mailer.cachedMessages[counter]['idx'] == Mailer.currentMailbox + '/' + idx)
            message = Mailer.cachedMessages[counter];
        else
            counter++;

    return message;
}

function storeCachedMessage(cachedMessage) {
    var oldest = -1;
    var timeOldest = -1;
    var counter = 0;

    if (Mailer.cachedMessages.length < Mailer.maxCachedMessages)
        oldest = Mailer.cachedMessages.length;
    else {
        while (Mailer.cachedMessages[counter]) {
            if (oldest == -1
                || Mailer.cachedMessages[counter]['time'] < timeOldest) {
                oldest = counter;
                timeOldest = Mailer.cachedMessages[counter]['time'];
            }
            counter++;
        }

        if (oldest == -1)
            oldest = 0;
    }

    Mailer.cachedMessages[oldest] = cachedMessage;
}

function onMessageSelectionChange() {
    var rows = this.getSelectedRowsId();

    if (rows.length == 1) {
        var idx = rows[0].substr(4);
        if (Mailer.currentMessages[Mailer.currentMailbox] != idx) {
            Mailer.currentMessages[Mailer.currentMailbox] = idx;
            loadMessage(idx);
        }
    }
    else if (rows.length > 1)
        $('messageContent').update();
}

function loadMessage(idx) {
    if (document.messageAjaxRequest) {
        document.messageAjaxRequest.aborted = true;
        document.messageAjaxRequest.abort();
    }

    var div = $('messageContent');
    var cachedMessage = getCachedMessage(idx);
    var row = $("row_" + idx);
    var seenStateChanged = row && row.hasClassName('mailer_unreadmail');
    if (cachedMessage == null) {
        var url = (ApplicationBaseURL + encodeURI(Mailer.currentMailbox) + "/"
                   + idx + "/view?noframe=1");
        div.update();
        document.messageAjaxRequest = triggerAjaxRequest(url, messageCallback, idx);
        markMailInWindow(window, idx, true);
    }
    else {
        div.update(cachedMessage['text']);
        cachedMessage['time'] = (new Date()).getTime();
        document.messageAjaxRequest = null;
        configureLinksInMessage();
        resizeMailContent();
        if (seenStateChanged) {
            // Mark message as read on server
            var img = row.select("IMG.mailerUnreadIcon").first();
            var fcnMarkRead = mailListMarkMessage.bind(img);
            fcnMarkRead();
        }
    }

    configureLoadImagesButton();
    configureSignatureFlagImage();
}

function configureLoadImagesButton() {
    // We show/hide the "Load Images" button
    var loadImagesButton = $("loadImagesButton");
    var content = $("messageContent");
    var hiddenImgs = [];
    var imgs = content.select("IMG");
    $(imgs).each(function(img) {
            var unsafeSrc = img.getAttribute("unsafe-src");
            if (unsafeSrc && unsafeSrc.length > 0) {
                hiddenImgs.push(img);
            }
        });
    content.hiddenImgs = hiddenImgs;

    if (typeof(loadImagesButton) == "undefined" ||
        loadImagesButton == null ) {
        return;
    }
    if (hiddenImgs.length == 0) {
        loadImagesButton.setStyle({ display: 'none' });
    }
}

function configureSignatureFlagImage() {
    var signedPart = $("signedMessage");
    if (signedPart) {
        var loadImagesButton = $("loadImagesButton");
        var parentNode = loadImagesButton.parentNode;
        var valid = parseInt(signedPart.getAttribute("valid"));
        var flagImage;

        if (valid)
          flagImage = "signature-ok.png";
        else
          flagImage = "signature-not-ok.png";

        var error = signedPart.getAttribute("error");
        var newImg = createElement("img", "signedImage", null, null,
                                   { src: ResourcesURL + "/" + flagImage });

        var msgDiv = $("signatureFlagMessage");
        if (msgDiv && error) {
            // First line in a h1, others each in a p
            var formattedMessage = "<h1>" + error.replace(/\n/, "</h1><p>");
            formattedMessage = formattedMessage.replace(/\n/g, "</p><p>") + "</p>";
            msgDiv.innerHTML = "<div>" + formattedMessage + "</div>";
            newImg.observe("mouseover", showSignatureMessage);
            newImg.observe("mouseout", hideSignatureMessage);
        }
        loadImagesButton.parentNode.insertBefore(newImg, loadImagesButton.nextSibling);
    }
}

function showSignatureMessage () {
    var div = $("signatureFlagMessage");
    if (div) {
        var node = $("signedImage");
        var cellPosition = node.cumulativeOffset();
        var divDimensions = div.getDimensions();
        var left = cellPosition[0] - divDimensions['width'];
        var top = cellPosition[1];
        div.style.top = (top + 5) + "px";
        div.style.left = (left + 5) + "px";
        div.style.display = "block";
    }
}
function hideSignatureMessage () {
    var div = $("signatureFlagMessage");
    if (div)
      div.style.display = "none";
}

function configureLinksInMessage() {
    var messageDiv = $('messageContent');
    var mailContentDiv = document.getElementsByClassName('mailer_mailcontent',
                                                         messageDiv)[0];
    if (!$(document.body).hasClassName("popup"))
        mailContentDiv.observe("contextmenu", onMessageContentMenu);

    var anchors = messageDiv.getElementsByTagName('a');
    for (var i = 0; i < anchors.length; i++)
        if (anchors[i].href.substring(0,7) == "mailto:") {
            $(anchors[i]).observe("click", onEmailTo);
            $(anchors[i]).observe("contextmenu", onEmailAddressClick);
        }
        else
            $(anchors[i]).observe("click", onMessageAnchorClick);

    var attachments = messageDiv.select ("DIV.linked_attachment_body");
    for (var i = 0; i < attachments.length; i++)
        $(attachments[i]).observe("contextmenu", onAttachmentClick);

    var images = messageDiv.select("IMG.mailer_imagecontent");
    for (var i = 0; i < images.length; i++)
        $(images[i]).observe("contextmenu", onImageClick);

    var editDraftButton = $("editDraftButton");
    if (editDraftButton)
        editDraftButton.observe("click",
                                onMessageEditDraft.bindAsEventListener(editDraftButton));

    var loadImagesButton = $("loadImagesButton");
    if (loadImagesButton)
        $(loadImagesButton).observe("click", onMessageLoadImages);

    configureiCalLinksInMessage();
}

function configureiCalLinksInMessage() {
    var buttons = { "iCalendarAccept": "accept",
                    "iCalendarDecline": "decline",
                    "iCalendarTentative": "tentative",
                    "iCalendarUpdateUserStatus": "updateUserStatus",
                    "iCalendarAddToCalendar": "addToCalendar",
                    "iCalendarDeleteFromCalendar": "deleteFromCalendar" };

    for (var key in buttons) {
        var button = $(key);
        if (button) {
            button.action = buttons[key];
            button.observe("click",
                           onICalendarButtonClick.bindAsEventListener(button));
        }
    }

    var button = $("iCalendarDelegate");
    if (button) {
        button.observe("click", onICalendarDelegate);
        var delegatedTo = $("delegatedTo");
        delegatedTo.addInterface(SOGoAutoCompletionInterface);
        delegatedTo.uidField = "c_mail";
        delegatedTo.excludeGroups = true;
        
        var editDelegate = $("editDelegate");
        if (editDelegate)
            // The user delegates the invitation
            editDelegate.observe("click", function(event) {
                    $("delegateEditor").show();
                    $("delegatedTo").focus();
                    this.hide();
                });

        var delegatedToLink = $("delegatedToLink");
        if (delegatedToLink) {
            // The user already delegated the invitation and wants
            // to change the delegated attendee
            delegatedToLink.stopObserving("click");
            delegatedToLink.observe("click", function(event) {
                    $("delegatedTo").show();
                    $("iCalendarDelegate").show();
                    $("delegatedTo").focus();
                    this.hide();
                    Event.stop(event);
                });
        }
    }
}

function onICalendarDelegate(event) {
    var link = $("iCalendarAttachment").value;
    if (link) {
        var currentMsg;
        if ($(document.body).hasClassName("popup"))
            currentMsg = mailboxName + "/" + messageName;
        else
            currentMsg = Mailer.currentMailbox + "/"
                + Mailer.currentMessages[Mailer.currentMailbox];
        delegateInvitation(link, ICalendarButtonCallback, currentMsg);
    }
}

function onICalendarButtonClick(event) {
    var link = $("iCalendarAttachment").value;
    if (link) {
        var urlstr = link + "/" + this.action;
        var currentMsg;
        currentMsg = Mailer.currentMailbox + "/"
            + Mailer.currentMessages[Mailer.currentMailbox];
        triggerAjaxRequest(urlstr, ICalendarButtonCallback, currentMsg);
    }
    else
        log("no link");
}

function ICalendarButtonCallback(http) {
    if ($(document.body).hasClassName("popup")) {
        if (window.opener && window.opener.open && !window.opener.closed)
            window.opener.ICalendarButtonCallback(http);
        else
            window.location.reload();
    }
    else {
        if (isHttpStatus204(http.status)) {
            var oldMsg = http.callbackData;
            var msg = Mailer.currentMailbox + "/" + Mailer.currentMessages[Mailer.currentMailbox];
            deleteCachedMessage(oldMsg);
            if (oldMsg == msg) {
                loadMessage(Mailer.currentMessages[Mailer.currentMailbox]);
            }
            for (var i = 0; i < Mailer.popups.length; i++) {
                if (Mailer.popups[i].messageUID == oldMsg) {
                    Mailer.popups[i].location.reload();
                    break;
                }
            }
        }
        else if (http.status == 403) {
            var data = http.responseText;
            var msg = data.replace(/^(.*\n)*.*<p>((.*\n)*.*)<\/p>(.*\n)*.*$/, "$2");
            window.alert(clabels[msg]?clabels[msg]:msg);
        }
        else
            window.alert("received code: " + http.status + "\nerror: " + http.responseText);
    }
}

function resizeMailContent() {
    var headerTable = document.getElementsByClassName('mailer_fieldtable')[0];
    var contentDiv = document.getElementsByClassName('mailer_mailcontent')[0];
  
    contentDiv.setStyle({ 'top':
                (Element.getHeight(headerTable) + headerTable.offsetTop) + 'px' });

    // Show expand buttons if necessary
    var spans = $$("TABLE TR.mailer_fieldrow TD.mailer_fieldvalue SPAN");
    spans.each(function(span) {
            var row = span.up("TR");
            if (span.getWidth() > row.getWidth()) {
                var cell = row.select("TD.mailer_fieldname").first();
                var link = cell.down("img");
                link.show();
                link.observe("click", toggleDisplayHeader);
            }
        });
}

function toggleDisplayHeader(event) {
    var row = this.up("TR");
    var span = row.down("SPAN");
   
    if (this.hasClassName("collapse")) {
        this.writeAttribute("src", ResourcesURL + '/minus.png');
        this.writeAttribute("class", "expand");
        span.writeAttribute("class", "expand");
    }
    else {
        this.writeAttribute("src", ResourcesURL + '/plus.png');
        this.writeAttribute("class", "collapse");
        span.writeAttribute("class", "collapse");
    }
    resizeMailContent();

    preventDefault(event);
    return false;
}

function onMessageContentMenu(event) {
    var element = getTarget(event);
    if ((element.tagName == 'A' && element.href.substring(0,7) == "mailto:")
        || element.tagName == 'IMG')
        // Don't show the default contextual menu; let the click propagate to 
        // other observers
        return true;
    popupMenu(event, 'messageContentMenu', this);
}

function onMessageEditDraft(event) {
    return openMessageWindowsForSelection("edit", true);
}

function onMessageLoadImages(event) {
    var content = $("messageContent");
    $(content.hiddenImgs).each(function(img) {
            var unSafeSrc = img.getAttribute("unsafe-src");
            log ("unsafesrc: " + unSafeSrc);
            img.src = img.getAttribute("unsafe-src");
        });

    content.hiddenImgs = null;
    var loadImagesButton = $("loadImagesButton");
    loadImagesButton.setStyle({ display: 'none' });

    Event.stop(event);
}

function onEmailAddressClick(event) {
    popupMenu(event, 'addressMenu', this);
    preventDefault(event);
    return false;
}

function onMessageAnchorClick(event) {
    window.open(this.href);
    preventDefault(event);
}

function onImageClick(event) {
    popupMenu(event, 'imageMenu', this);
    preventDefault(event);
    return false;
}

function onAttachmentClick (event) {
    popupMenu (event, 'attachmentMenu', this);
    preventDefault (event);
    return false;
}

function messageCallback(http) {
    var div = $('messageContent');

    if (http.status == 200) {
        document.messageAjaxRequest = null;
        div.update(http.responseText);
        configureLinksInMessage();
        resizeMailContent();
        configureLoadImagesButton();
        configureSignatureFlagImage();
		
        if (http.callbackData) {
            var cachedMessage = new Array();
            cachedMessage['idx'] = Mailer.currentMailbox + '/' + http.callbackData;
            cachedMessage['time'] = (new Date()).getTime();
            cachedMessage['text'] = http.responseText;
            if (cachedMessage['text'].length < 30000)
                storeCachedMessage(cachedMessage);
        }
    }
    else if (http.status == 404) {
        alert (getLabel("The message you have selected doesn't exist anymore."));
        window.location.reload ();
    }
    else
        log("messageCallback: problem during ajax request: " + http.status);
}

function processMailboxMenuAction(mailbox) {
    var currentNode, upperNode;
    var mailboxName;
    var action;

    mailboxName = mailbox.getAttribute('mailboxname');
    currentNode = mailbox;
    upperNode = null;

    while (currentNode
           && !currentNode.hasAttribute('mailboxaction'))
        currentNode = currentNode.parentNode.parentNode.parentMenuItem;

    if (currentNode)
        {
            action = currentNode.getAttribute('mailboxaction');
            //       var rows  = collectSelectedRows();
            //       var rString = rows.join(', ');
            //       alert("performing '" + action + "' on " + rString
            //             + " to " + mailboxName);
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

/* message menu entries */
function onMenuOpenMessage(event) {
    return openMessageWindowsForSelection('popupview');
}

function onMenuReplyToSender(event) {
    return openMessageWindowsForSelection('reply');
}

function onMenuReplyToAll(event) {
    return openMessageWindowsForSelection('replyall');
}

function onMenuForwardMessage(event) {
    return openMessageWindowsForSelection('forward');
}

function onMenuViewMessageSource(event) {
    var messageList = $("messageList");
    var rows = messageList.getSelectedRowsId();

    if (rows.length > 0) {
        var url = (ApplicationBaseURL + encodeURI(Mailer.currentMailbox) + "/"
                   + rows[0].substr(4) + "/viewsource");
        openMailComposeWindow(url);
    }

    preventDefault(event);
}

function saveImage(event) {
    var img = document.menuTarget;
    var url = img.getAttribute("src");
    var urlAsAttachment = url.replace(/(\/[^\/]*)$/,"/asAttachment$1");

    window.location.href = urlAsAttachment;
}

function saveAttachment(event) {
    var div = document.menuTarget;
    var link = div.select ("a").first ();
    var url = link.getAttribute("href");
    var urlAsAttachment = url.replace(/(\/[^\/]*)$/,"/asAttachment$1");

    window.location.href = urlAsAttachment;
}

/* contacts */
function newContactFromEmail(event) {
    var mailto = document.menuTarget.innerHTML;

    var email = extractEmailAddress(mailto);
    var c_name = extractEmailName(mailto);
    if (email.length > 0) {
        var url = (UserFolderURL + "Contacts/personal/newcontact?contactEmail="
                   + encodeURI(email));
        if (c_name)
            url += "&contactFN=" + c_name;
        openContactWindow(url);
    }

    return false; /* stop following the link */
}

function onEmailTo(event) {
    openMailTo(this.innerHTML.strip());
    Event.stop(event);
    return false;
}

function newEmailTo(sender) {
    return openMailTo(document.menuTarget.innerHTML);
}

function expandUpperTree(node) {
    var currentNode = node.parentNode;

    while (currentNode.className != "dtree") {
        if (currentNode.className == 'clip') {
            var id = currentNode.getAttribute("id");
            var number = parseInt(id.substr(2));
            if (number > 0) {
                var cn = mailboxTree.aNodes[number];
                mailboxTree.nodeStatus(1, number, cn._ls);
            }
        }
        currentNode = currentNode.parentNode;
    }
}

function onHeaderClick(event) {
    if (TableKit.Resizable._onHandle)
        return;
  
    var headerId = this.getAttribute("id");
    var newSortAttribute;
    if (headerId == "subjectHeader")
        newSortAttribute = "subject";
    else if (headerId == "fromHeader")
        newSortAttribute = "from";
    else if (headerId == "toHeader")
        newSortAttribute = "to";
    else if (headerId == "dateHeader")
        newSortAttribute = "date";
    else if (headerId == "sizeHeader")
        newSortAttribute = "size";
    else
        newSortAttribute = "arrival";

    if (sorting["attribute"] == newSortAttribute)
        sorting["ascending"] = !sorting["ascending"];
    else {
        sorting["attribute"] = newSortAttribute;
        sorting["ascending"] = true;
    }
    refreshCurrentFolder();
  
    Event.stop(event);
}

function refreshCurrentFolder() {
    openMailbox(Mailer.currentMailbox, true);
}

/* a model for a futur refactoring of the sortable table headers mechanism */
function configureMessageListEvents(table) {
    if (table) {
        table.multiselect = true;
        // Each body row can load a message
        table.observe("mousedown", onMessageSelectionChange);
        // Sortable columns
        configureSortableTableHeaders(table);
    }
}

function configureMessageListBodyEvents(table) {
    if (table) {
        // Page navigation
        var cell = table.tHead.rows[1].cells[0];
        if ($(cell).hasClassName("tbtv_navcell")) {
            var anchors = $(cell).childNodesWithTag("a");
            for (var i = 0; i < anchors.length; i++)
                $(anchors[i]).observe("click", openMailboxAtIndex);
        }
      
        rows = table.tBodies[0].rows;
        for (var i = 0; i < rows.length; i++) {
            var row = $(rows[i]);
            row.observe("mousedown", onRowClick);
            row.observe("selectstart", listRowMouseDownHandler);
            row.observe("contextmenu", onMessageContextMenu);
         
            //row.dndTypes = function() { return new Array("mailRow"); };
            //row.dndGhost = messageListGhost;
            //row.dndDataForType = messageListData;
            //document.DNDManager.registerSource(row);
            // Correspondances index <> nom de la colonne
            // 0 => Invisible
            // 1 => Attachment
            // 2 => Subject
            // 3 => From
            // 4 => Unread
            // 5 => Date
            // 6 => Priority
            var columnsOrder = UserSettings["SOGoMailListViewColumnsOrder"];
            if ( typeof(columnsOrder) == "undefined" ) {
                columnsOrder = defaultColumnsOrder;
            }
            for (var j = 0; j < row.cells.length; j++) {
                var cell = $(row.cells[j]);
                var cellType = columnsOrder[j];
                cell.observe("mousedown", listRowMouseDownHandler);
                if (cellType == "Subject" || cellType == "From" || cellType == "To" || cellType == "Date")
                    cell.observe("dblclick", onMessageDoubleClick.bindAsEventListener(cell));
                else if (cellType == "Unread") {
                    var img = $(cell.childNodesWithTag("img")[0]);
                    if (img)
                      img.observe("click", mailListMarkMessage.bindAsEventListener(img));
                }
            }
        }
    }
}

function configureDragHandles() {
    var handle = $("verticalDragHandle");
    if (handle) {
        handle.addInterface(SOGoDragHandlesInterface);
        handle.leftMargin = 50;
        handle.leftBlock=$("leftPanel");
        handle.rightBlock=$("rightPanel");
    }

    handle = $("rightDragHandle");
    if (handle) {
        handle.addInterface(SOGoDragHandlesInterface);
        handle.upperBlock=$("mailboxContent");
        handle.lowerBlock=$("messageContent");
    }
}

function onWindowResize(event) {
    var handle = $("verticalDragHandle");
    if (handle)
        handle.adjust();
    handle = $("rightDragHandle");
    if (handle)
        handle.adjust();
}

/* dnd */
function initDnd() {
    //   log("MailerUI initDnd");

    var tree = $("mailboxTree");
    if (tree) {
        var images = tree.getElementsByTagName("img");
        for (var i = 0; i < images.length; i++) {
            if (images[i].id[0] == 'j') {
                images[i].dndAcceptType = mailboxSpanAcceptType;
                images[i].dndEnter = plusSignEnter;
                images[i].dndExit = plusSignExit;
                document.DNDManager.registerDestination(images[i]);
            }
        }
        var nodes = document.getElementsByClassName("nodeName", tree);
        for (var i = 0; i < nodes.length; i++) {
            nodes[i].dndAcceptType = mailboxSpanAcceptType;
            nodes[i].dndEnter = mailboxSpanEnter;
            nodes[i].dndExit = mailboxSpanExit;
            nodes[i].dndDrop = mailboxSpanDrop;
            document.DNDManager.registerDestination(nodes[i]);
        }
    }
}

/* stub */

function refreshContacts() {
}

function openInbox(node) {
    var done = false;
    openMailbox(node.parentNode.getAttribute("dataname"), null, null, false);
    var tree = $("mailboxTree");
    tree.selectedEntry = node;
    node.selectElement();
    mailboxTree.o(1);
}

function initFlagIcons () {
    var icons = $$("TABLE#messageList TBODY TR.mailer_listcell_regular TD.messageFlag");
    for (var i = 0; i < icons.length; i++)
      icons[i].onclick = mailListFlagMessageToggle;
}

function initMailer(event) {
    if (!$(document.body).hasClassName("popup")) {
        //initDnd();
        initMailboxTree();
        initMessageCheckTimer();
		
        if (Prototype.Browser.Gecko)
            Event.observe(document, "keypress", onDocumentKeydown); // for FF2
        else
            Event.observe(document, "keydown", onDocumentKeydown);

        /* Perform an expunge when leaving the webmail */
        if (isSafari()) {
            $('calendarBannerLink').observe("click", onUnload);
            $('contactsBannerLink').observe("click", onUnload);
            $('logoff').observe("click", onUnload);
        }
        else
            Event.observe(window, "beforeunload", onUnload);
    }
  
    onWindowResize.defer();
    Event.observe(window, "resize", onWindowResize);

    // Default sort options
    sorting["attribute"] = "date";
    sorting["ascending"] = false;
}

function initMessageCheckTimer() {
    var messageCheck = UserDefaults["MessageCheck"];
    if (messageCheck && messageCheck != "manually") {
        var interval;
        if (messageCheck == "once_per_hour")
            interval = 3600;
        else if (messageCheck == "every_minute")
            interval = 60;
        else {
            interval = parseInt(messageCheck.substr(6)) * 60;
        }
        messageCheckTimer = window.setInterval(onMessageCheckCallback,
                                               interval * 1000);
    }
}

function onMessageCheckCallback(event) {
    refreshMailbox();
}

function initMailboxTree() {
    var node = $("mailboxTree");
    if (node)
        node.parentNode.removeChild(node);
    mailboxTree = new dTree("mailboxTree");
    mailboxTree.config.hideRoot = true;
    mailboxTree.icon.root = ResourcesURL + "/tbtv_account_17x17.gif";
    mailboxTree.icon.folder = ResourcesURL + "/tbtv_leaf_corner_17x17.png";
    mailboxTree.icon.folderOpen	= ResourcesURL + "/tbtv_leaf_corner_17x17.png";
    mailboxTree.icon.node = ResourcesURL + "/tbtv_leaf_corner_17x17.png";
    mailboxTree.icon.line = ResourcesURL + "/tbtv_line_17x17.gif";
    mailboxTree.icon.join = ResourcesURL + "/tbtv_junction_17x17.gif";
    mailboxTree.icon.joinBottom	= ResourcesURL + "/tbtv_corner_17x17.gif";
    mailboxTree.icon.plus = ResourcesURL + "/tbtv_plus_17x17.gif";
    mailboxTree.icon.plusBottom	= ResourcesURL + "/tbtv_corner_plus_17x17.gif";
    mailboxTree.icon.minus = ResourcesURL + "/tbtv_minus_17x17.gif";
    mailboxTree.icon.minusBottom = ResourcesURL + "/tbtv_corner_minus_17x17.gif";
    mailboxTree.icon.nlPlus = ResourcesURL + "/tbtv_corner_plus_17x17.gif";
    mailboxTree.icon.nlMinus = ResourcesURL + "/tbtv_corner_minus_17x17.gif";
    mailboxTree.icon.empty = ResourcesURL + "/empty.gif";
    mailboxTree.preload ();

    mailboxTree.add(0, -1, '');

    mailboxTree.pendingRequests = mailAccounts.length;
    activeAjaxRequests += mailAccounts.length;
    for (var i = 0; i < mailAccounts.length; i++) {
        var url = ApplicationBaseURL + encodeURI(mailAccounts[i][0]) + "/mailboxes";
        triggerAjaxRequest(url, onLoadMailboxesCallback, mailAccounts[i]);
    }
}

function updateMailboxTreeInPage() {
    var treeContent = $("folderTreeContent");
    //treeContent.update(mailboxTree.toString ());
    treeContent.appendChild(mailboxTree.domObject ());

    var inboxFound = false;
    var tree = $("mailboxTree");
    var nodes = document.getElementsByClassName("node", tree);
    for (i = 0; i < nodes.length; i++) {
        nodes[i].observe("click",
                         onMailboxTreeItemClick.bindAsEventListener(nodes[i]));
        nodes[i].observe("contextmenu",
                         onFolderMenuClick.bindAsEventListener(nodes[i]));
        if (!inboxFound
            && nodes[i].parentNode.getAttribute("datatype") == "inbox") {
            Mailer.currentMailboxType = "inbox";
            openInbox(nodes[i]);
            inboxFound = true;
        }
    }
    if (Mailer.quotas && parseInt(Mailer.quotas.maxQuota) > 0) {
        var quotaDiv = $("quotaIndicator");
        if (quotaDiv) {
            treeContent.removeChild(quotaDiv);
        }
        // Build quota indicator, show values in MB
        var percents = (Math.round(Mailer.quotas.usedSpace * 10000
                                   / Mailer.quotas.maxQuota)
                        / 100);
        var level = (percents > 85)? "alert" : (percents > 70)? "warn" : "ok";
        var format = getLabel("quotasFormat");
        var text = format.formatted(percents,
                                    Math.round(Mailer.quotas.maxQuota/10.24)/100);
        quotaDiv = new Element('div', { 'id': 'quotaIndicator',
                                        'class': 'quota',
                                        'info': text });
        var levelDiv = new Element('div', { 'class': 'level' });
        var valueDiv = new Element('div', { 'class': 'value ' + level, 'style': 'width: ' + ((percents > 100)?100:percents) + '%' });
        var marksDiv = new Element('div', { 'class': 'marks' });
        var textP = new Element('p').update(text);
        marksDiv.insert(new Element('div'));
        marksDiv.insert(new Element('div'));
        marksDiv.insert(new Element('div'));
        levelDiv.insert(valueDiv);
        levelDiv.insert(marksDiv);
        levelDiv.insert(textP);
        quotaDiv.insert(levelDiv);
        treeContent.insertBefore(quotaDiv, tree);
    }
}

function mailboxMenuNode(type, name) {
    var newNode = document.createElement("li");
    var icon = MailerUIdTreeExtension.folderIcons[type];
    if (!icon)
        icon = "tbtv_leaf_corner_17x17.png";
    var image = document.createElement("img");
    image.src = ResourcesURL + "/" + icon;
    newNode.appendChild(image);
    var displayName = MailerUIdTreeExtension.folderNames[type];
    if (!displayName)
        displayName = name;
    newNode.appendChild(document.createTextNode(" " + displayName));

    return newNode;
}

function generateMenuForMailbox(mailbox, prefix, callback) {
    var menuDIV = document.createElement("div");
    $(menuDIV).addClassName("menu");
    var menuID = prefix + "Submenu";
    var previousMenuDIV = $(menuID);
    if (previousMenuDIV)
        previousMenuDIV.parentNode.removeChild(previousMenuDIV);
    menuDIV.setAttribute("id", menuID);
    var menu = document.createElement("ul");
    menu.style.cssFloat="left";
    menu.style.styleFloat="left";
    menuDIV.appendChild(menu);
    pageContent.appendChild(menuDIV);

    var windowHeight = 0;
    if ( typeof(window.innerHeight) != "undefined" && window.innerHeight != 0 ) {
        windowHeight = window.innerHeight;
    }
    else {
        windowHeight = document.body.clientHeight;
    }
    var offset = 70;
    if ( navigator.appVersion.indexOf("Safari") >= 0 ) {
        offset = 140;
    }

    var callbacks = new Array();
    if (mailbox.type != "account") {
        var newNode = document.createElement("li");
        newNode.mailbox = mailbox;
        newNode.appendChild(document.createTextNode(getLabel("This Folder")));
        menu.appendChild(newNode);
        menu.appendChild(document.createElement("li"));
        callbacks.push(callback);
        callbacks.push("-");
    }

    var submenuCount = 0;
    var newNode;
    for (var i = 0; i < mailbox.children.length; i++) {
        if ( menu.offsetHeight > windowHeight-offset ) {
            var menuWidth = parseInt(menu.offsetWidth) + 15
                menuWidth = menuWidth + "px";
            menu.style.width = menuWidth;
            menu = document.createElement("ul");
            menu.style.cssFloat="left";
            menu.style.styleFloat="left";
            menuDIV.appendChild(menu);
        }
        var child = mailbox.children[i];
        newNode = mailboxMenuNode(child.type, child.name);
        newNode.style.width = "auto";
        menu.appendChild(newNode);
        if (child.children.length > 0) {
            var newPrefix = prefix + submenuCount;
            var newSubmenuId = generateMenuForMailbox(child, newPrefix, callback);
            callbacks.push(newSubmenuId);
            submenuCount++;
        }
        else {
            newNode.mailbox = child;
            callbacks.push(callback);
        }
    }
    var menuWidth = parseInt(menu.offsetWidth) + 15
        menuWidth = menuWidth + "px";
    menu.style.width = menuWidth;
  
  
    initMenu(menuDIV, callbacks);

    return menuDIV.getAttribute("id");
}

function updateMailboxMenus() {
    var mailboxActions = { move: onMailboxMenuMove,
                           copy: onMailboxMenuCopy };

    for (key in mailboxActions) {
        var menuId = key + "MailboxMenu";
        var menuDIV = $(menuId);
        if (menuDIV)
            menuDIV.parentNode.removeChild(menuDIV);

        menuDIV = document.createElement("div");
        pageContent = $("pageContent");
        pageContent.appendChild(menuDIV);

        var menu = document.createElement("ul");
        menuDIV.appendChild(menu);

        $(menuDIV).addClassName("menu");
        menuDIV.setAttribute("id", menuId);

        var submenuIds = new Array();
        for (var i = 0; i < mailAccounts.length; i++) {
            var menuEntry = mailboxMenuNode("account", mailAccounts[i][1]);
            menu.appendChild(menuEntry);
            var mailbox = accounts[mailAccounts[i]];
            var newSubmenuId = generateMenuForMailbox(mailbox,
                                                      key, mailboxActions[key]);
            submenuIds.push(newSubmenuId);
        }
        initMenu(menuDIV, submenuIds);
    }
}

function onLoadMailboxesCallback(http) {
    if (http.status == 200) {
        checkAjaxRequestsState();
        if (http.responseText.length > 0) {
            var newAccount = buildMailboxes(http.callbackData,
                                            http.responseText);
            accounts[http.callbackData] = newAccount;
            mailboxTree.addMailAccount(newAccount);
            mailboxTree.pendingRequests--;
            activeAjaxRequests--;
            if (!mailboxTree.pendingRequests) {
                updateMailboxTreeInPage();
                updateMailboxMenus();
                checkAjaxRequestsState();
                getFoldersState();
                updateStatusFolders();
                configureDroppables();
            }
        }
        else
            log ("onLoadMailboxesCallback " + http.status);
    }

    //       var tree = $("mailboxTree");
    //       var treeNodes = document.getElementsByClassName("dTreeNode", tree);
    //       var i = 0;
    //       while (i < treeNodes.length
    // 	     && treeNodes[i].getAttribute("dataname") != Mailer.currentMailbox)
    // 	 i++;
    //       if (i < treeNodes.length) {
    // 	 //     log("found mailbox");
    // 	 var links = document.getElementsByClassName("node", treeNodes[i]);
    // 	 if (tree.selectedEntry)
    // 	    tree.selectedEntry.deselect();
    // 	 links[0].selectElement();
    // 	 tree.selectedEntry = links[0];
    // 	 expandUpperTree(links[0]);
    //       }
}

function buildMailboxes(accountKeys, encoded) {
    var account = new Mailbox("account", accountKeys[0], 
                              undefined, //necessary, null will cause issues
                              accountKeys[1]);
    var data = encoded.evalJSON(true);
    var mailboxes = data.mailboxes;
    var unseen = (data.status? data.status.unseen : 0);

    if (data.quotas)
        Mailer.quotas = data.quotas;
	
    for (var i = 0; i < mailboxes.length; i++) {
        var currentNode = account;
        var names = mailboxes[i].path.split("/");
        for (var j = 1; j < (names.length - 1); j++) {
            var node = currentNode.findMailboxByName(names[j]);
            if (!node) {
                node = new Mailbox("additional", names[j]);
                currentNode.addMailbox(node);
            }
            currentNode = node;
        }
        var basename = names[names.length-1];
        var leaf = currentNode.findMailboxByName(basename);
        if (leaf)
            leaf.type = mailboxes[i].type;
        else {
            if (mailboxes[i].type == 'inbox')
                leaf = new Mailbox(mailboxes[i].type, basename, unseen);
            else
                leaf = new Mailbox(mailboxes[i].type, basename);
            currentNode.addMailbox(leaf);
        }
    }

    return account;
}

function getFoldersState() {
    if (mailAccounts.length > 0) {
        var urlstr =  ApplicationBaseURL + "foldersState";
        triggerAjaxRequest(urlstr, getFoldersStateCallback);
    }
}

function getFoldersStateCallback(http) {
    if (http.status == 200) {
        if (http.responseText.length > 0) {
            // The response text is a JSON array
            // of the folders that were left opened.
            var data = http.responseText.evalJSON(true);
            for (var i = 1; i < mailboxTree.aNodes.length; i++) {
                if ($(data).indexOf(mailboxTree.aNodes[i].dataname) > 0)
                    // If the folder is found, open it
                    mailboxTree.o(i);
            }
        }
        mailboxTree.autoSync();
    }
}

function saveFoldersState() {
    if (mailAccounts.length > 0) {
        var foldersState = mailboxTree.getFoldersState();
        var urlstr =  ApplicationBaseURL + "saveFoldersState";
        var parameters = "expandedFolders=" + foldersState;
        triggerAjaxRequest(urlstr, saveFoldersStateCallback, null, parameters,
                           { "Content-type": "application/x-www-form-urlencoded" });
    }
}

function saveFoldersStateCallback(http) {
    if (isHttpStatus204(http.status)) {
        log ("folders state saved");
    }
}

function onMenuCreateFolder(event) {
    var name = window.prompt(getLabel("Name :"), "");
    if (name && name.length > 0) {
        var folderID = document.menuTarget.getAttribute("dataname");
        var urlstr = URLForFolderID(folderID) + "/createFolder?name=" + encodeURIComponent(name);
        var errorLabel = labels["The folder with name \"%{0}\" could not be created."];
        triggerAjaxRequest(urlstr, folderOperationCallback,
                           errorLabel.formatted(name));
    }
}

function onMenuRenameFolder(event) {
    var name = window.prompt(getLabel("Enter the new name of your folder :"),
                             "");
    if (name && name.length > 0) {
        var folderID = document.menuTarget.getAttribute("dataname");
        var urlstr = URLForFolderID(folderID) + "/renameFolder?name=" + name;
        var errorLabel = labels["This folder could not be renamed to \"%{0}\"."];
        triggerAjaxRequest(urlstr, folderOperationCallback,
                           errorLabel.formatted(name));
    }
}

function onMenuDeleteFolder(event) {
    var answer = window.confirm(getLabel("Do you really want to move this folder into the trash ?"));
    if (answer) {
        var folderID = document.menuTarget.getAttribute("dataname");
        var urlstr = URLForFolderID(folderID) + "/delete";
        var errorLabel = getLabel("The folder could not be deleted.");
        triggerAjaxRequest(urlstr, folderOperationCallback, errorLabel);
    }
}

function onMenuExpungeFolder(event) {
    var folderID = document.menuTarget.getAttribute("dataname");
    var urlstr = URLForFolderID(folderID) + "/expunge";
    triggerAjaxRequest(urlstr, folderRefreshCallback, { "mailbox": folderID, "refresh": false });
}

function onMenuEmptyTrash(event) {
    var folderID = document.menuTarget.getAttribute("dataname");
    var urlstr = URLForFolderID(folderID) + "/emptyTrash";
    var errorLabel = getLabel("The trash could not be emptied.");
    triggerAjaxRequest(urlstr, folderOperationCallback, errorLabel);

    if (folderID == Mailer.currentMailbox) {
        var div = $('messageContent');
        for (var i = div.childNodes.length - 1; i > -1; i--)
            div.removeChild(div.childNodes[i]);
        refreshCurrentFolder();
    }
    var msgID = Mailer.currentMessages[folderID];
    if (msgID)
        deleteCachedMessage(folderID + "/" + msgID);
}

function _onMenuChangeToXXXFolder(event, folder) {
    var type = document.menuTarget.getAttribute("datatype");
    if (type == "additional")
        window.alert(getLabel("You need to choose a non-virtual folder!"));
    else {
        var folderID = document.menuTarget.getAttribute("dataname");
        var urlstr = URLForFolderID(folderID) + "/setAs" + folder + "Folder";
        var errorLabel = getLabel("The folder functionality could not be changed.");
        triggerAjaxRequest(urlstr, folderOperationCallback, errorLabel);
    }
}

function onMenuChangeToDraftsFolder(event) {
    return _onMenuChangeToXXXFolder(event, "Drafts");
}

function onMenuChangeToSentFolder(event) {
    return _onMenuChangeToXXXFolder(event, "Sent");
}

function onMenuChangeToTrashFolder(event) {
    return _onMenuChangeToXXXFolder(event, "Trash");
}

function onMenuLabelNone() {
    var messages = new Array();

    if (document.menuTarget.tagName == "DIV")
        // Menu called from message content view
        messages.push(Mailer.currentMessages[Mailer.currentMailbox]);
    else if (Object.isArray(document.menuTarget))
        // Menu called from multiple selection in messages list view
        $(document.menuTarget).collect(function(row) {
                messages.push(row.getAttribute("id").substr(4));
            });
    else
        // Menu called from one selection in messages list view
        messages.push(document.menuTarget.getAttribute("id").substr(4));
  
    var url = ApplicationBaseURL + encodeURI(Mailer.currentMailbox) + "/";
    messages.each(function(id) {
            triggerAjaxRequest(url + id + "/removeAllLabels",
                               messageFlagCallback,
                               { mailbox: Mailer.currentMailbox, msg: id, label: null } );
        });  
}

function _onMenuLabelFlagX(flag) {
    var messages = new Hash();

    if (document.menuTarget.tagName == "DIV")
        // Menu called from message content view
        messages.set(Mailer.currentMessages[Mailer.currentMailbox],
                     $('row_' + Mailer.currentMessages[Mailer.currentMailbox]).getAttribute("labels"));
    else if (Object.isArray(document.menuTarget))
        // Menu called from multiple selection in messages list view
        $(document.menuTarget).collect(function(row) {
                messages.set(row.getAttribute("id").substr(4),
                             row.getAttribute("labels"));
            });
    else
        // Menu called from one selection in messages list view
        messages.set(document.menuTarget.getAttribute("id").substr(4),
                     document.menuTarget.getAttribute("labels"));
  
    var url = ApplicationBaseURL + encodeURI(Mailer.currentMailbox) + "/";
    messages.keys().each(function(id) {
            var flags = messages.get(id).split(" ");
            var operation = "add";
      
            if (flags.indexOf("label" + flag) > -1)
                operation = "remove";

            triggerAjaxRequest(url + id + "/" + operation + "Label" + flag,
                               messageFlagCallback,
                               { mailbox: Mailer.currentMailbox, msg: id,
                                       label: operation + flag } );
        });
}

function onMenuLabelFlag1() {
    _onMenuLabelFlagX(1);
}

function onMenuLabelFlag2() {
    _onMenuLabelFlagX(2);
}

function onMenuLabelFlag3() {
    _onMenuLabelFlagX(3);
}

function onMenuLabelFlag4() {
    _onMenuLabelFlagX(4);
}

function onMenuLabelFlag5() {
    _onMenuLabelFlagX(5);
}

function folderOperationCallback(http) {
    if (http.readyState == 4
        && isHttpStatus204(http.status))
        initMailboxTree();
    else
        window.alert(http.callbackData);
}

function folderRefreshCallback(http) {
    if (http.readyState == 4
        && isHttpStatus204(http.status)) {
        var oldMailbox = http.callbackData.mailbox;
        if (http.callbackData.refresh
            && oldMailbox == Mailer.currentMailbox)
            refreshCurrentFolder();
    }
    else {
        if (http.callbackData.id) {
            // Display hidden rows from move operation
            var s = http.callbackData.id + "";
            var uids = s.split(",");
            for (var i = 0; i < uids.length; i++) {
                var row = $("row_" + uids[i]);
                row.show();
            }
        }
        window.alert(getLabel("Operation failed"));
    }
}

function messageFlagCallback(http) {
    if (http.readyState == 4
        && isHttpStatus204(http.status)) {
        var data = http.callbackData;
        if (data["mailbox"] == Mailer.currentMailbox) {
            var row = $("row_" + data["msg"]);
            var operation = data["label"];
            if (operation) {
                var labels = row.getAttribute("labels");
                var flags;
                if (labels.length > 0)
                    flags = labels.split(" ");
                else
                    flags = new Array();
                if (operation.substr(0, 3) == "add")
                    flags.push("label" + operation.substr(3));
                else {
                    var flag = "label" + operation.substr(6);
                    var idx = flags.indexOf(flag);
                    flags.splice(idx, 1);
                }
                row.writeAttribute("labels", flags.join(" "));
                row.toggleClassName("_selected");
                row.toggleClassName("_selected");
            }
            else
                row.writeAttribute("labels", "");
        }
    }
}

function onLabelMenuPrepareVisibility() {
    var messageList = $("messageList");
    var flags = {};

    if (messageList) {
        var rows = messageList.getSelectedRows();
        for (var i = 0; i < rows.length; i++) {
            $w(rows[i].getAttribute("labels")).each(function(flag) {
                    flags[flag] = true;
                });
        }
    }

    var lis = this.childNodesWithTag("ul")[0].childNodesWithTag("li")
        var isFlagged = false;
    for (var i = 1; i < 6; i++) {
        if (flags["label" + i]) {
            isFlagged = true;
            lis[1 + i].addClassName("_chosen");
        }
        else
            lis[1 + i].removeClassName("_chosen");
    }
    if (isFlagged)
        lis[0].removeClassName("_chosen");
    else
        lis[0].addClassName("_chosen");
}

function saveAs(event) {
    var messageList = $("messageList").down("TBODY");
    var rows = messageList.getSelectedNodes();
    var uids = new Array(); // message IDs
    var paths = new Array(); // row IDs

    if (rows.length > 0) {
        for (var i = 0; i < rows.length; i++) {
            var uid = rows[i].readAttribute("id").substr(4);
            var path = Mailer.currentMailbox + "/" + uid;
            uids.push(uid);
            paths.push(path);
        }
        var url = ApplicationBaseURL + encodeURI(Mailer.currentMailbox) + "/saveMessages";
        window.open(url+"?id="+uids+"&uid="+uids+"&mailbox="+Mailer.currentMailbox+"&path="+paths);
    }
    else
        window.alert(getLabel("Please select a message."));

    return false;
}

function getMenus() {
    var menus = {}
    menus["accountIconMenu"] = new Array(null, null, onMenuCreateFolder, null,
                                         null, null);
    menus["inboxIconMenu"] = new Array(null, null, null, "-", null,
                                       onMenuCreateFolder, onMenuExpungeFolder,
                                       "-", null,
                                       onMenuSharing);
    menus["trashIconMenu"] = new Array(null, null, null, "-", null,
                                       onMenuCreateFolder, onMenuExpungeFolder,
                                       onMenuEmptyTrash, "-", null,
                                       onMenuSharing);
    menus["mailboxIconMenu"] = new Array(null, null, null, "-", null,
                                         onMenuCreateFolder,
                                         onMenuRenameFolder,
                                         onMenuExpungeFolder,
                                         onMenuDeleteFolder,
                                         "folderTypeMenu",
                                         "-", null,
                                         onMenuSharing);
    menus["addressMenu"] = new Array(newContactFromEmail, newEmailTo, null);
    menus["messageListMenu"] = new Array(onMenuOpenMessage, "-",
                                         onMenuReplyToSender,
                                         onMenuReplyToAll,
                                         onMenuForwardMessage, null,
                                         "-", "moveMailboxMenu",
                                         "copyMailboxMenu", "label-menu",
                                         "mark-menu", "-", saveAs,
                                         onMenuViewMessageSource, null,
                                         null, onMenuDeleteMessage);
    menus["messagesListMenu"] = new Array(onMenuForwardMessage,
                                          "-", "moveMailboxMenu",
                                          "copyMailboxMenu", "label-menu",
                                          "mark-menu", "-",
                                          saveAs, null,
                                          onMenuDeleteMessage);
    menus["imageMenu"] = new Array(saveImage);
    menus["attachmentMenu"] = new Array (saveAttachment);
    menus["messageContentMenu"] = new Array(onMenuReplyToSender,
                                            onMenuReplyToAll,
                                            onMenuForwardMessage,
                                            null, "moveMailboxMenu",
                                            "copyMailboxMenu",
                                            "-", "label-menu", "mark-menu",
                                            "-",
                                            saveAs, onMenuViewMessageSource,
                                            null, onPrintCurrentMessage,
                                            onMenuDeleteMessage);
    menus["folderTypeMenu"] = new Array(onMenuChangeToSentFolder,
                                        onMenuChangeToDraftsFolder,
                                        onMenuChangeToTrashFolder);

    menus["label-menu"] = new Array(onMenuLabelNone, "-", onMenuLabelFlag1,
                                    onMenuLabelFlag2, onMenuLabelFlag3,
                                    onMenuLabelFlag4, onMenuLabelFlag5);
    menus["mark-menu"] = new Array(null, null, null, null, "-", null, "-",
                                   null, null, null);
    menus["searchMenu"] = new Array(setSearchCriteria, setSearchCriteria,
                                    setSearchCriteria, setSearchCriteria,
                                    setSearchCriteria);
    var labelMenu = $("label-menu");
    if (labelMenu)
        labelMenu.prepareVisibility = onLabelMenuPrepareVisibility;

    return menus;
}

document.observe("dom:loaded", initMailer);

function Mailbox(type, name, unseen, displayName) {
    this.type = type;
    this.name = name;
    if (displayName)
      this.displayName = displayName;
    else
      this.displayName = name;
    this.unseen = unseen;
    this.parentFolder = null;
    this.children = new Array();
    return this;
}

Mailbox.prototype = {
    dump: function(indent) {
        if (!indent)
            indent = 0;
        log(" ".repeat(indent) + this.name);
        for (var i = 0; i < this.children.length; i++) {
            this.children[i].dump(indent + 2);
        }
    },
    fullName: function() {
        var fullName = "";

        var currentFolder = this;
        while (currentFolder.parentFolder) {
            fullName = "/folder" + currentFolder.name + fullName;
            currentFolder = currentFolder.parentFolder;
        }

        return "/" + currentFolder.name + fullName;
    },
    findMailboxByName: function(name) {
        var mailbox = null;

        var i = 0;
        while (!mailbox && i < this.children.length)
            if (this.children[i].name == name 
                || this.children[i].displayName == name)
                mailbox = this.children[i];
            else
                i++;

        return mailbox;
    },
    addMailbox: function(mailbox) {
        mailbox.parentFolder = this;
        this.children.push(mailbox);
    }
};


function configureDraggables () {
    var mainElement = $("dragDropVisual");
    Draggables.empty ();
    
    if (mainElement == null) {
        mainElement = new Element ("div", {id: "dragDropVisual"});
        document.body.appendChild(mainElement);
        mainElement.absolutize ();
    }
    mainElement.hide();
 
    new Draggable ("dragDropVisual", 
                   { handle: "messageList", 
                           onStart: startDragging,
                           onEnd: stopDragging,
                           onDrag: whileDragging,
                           scroll: "folderTreeContent" });
}

function configureDroppables () {
    var drops = $$("div#dmailboxTree1 div.dTreeNode a.node span.nodeName");
    
    Droppables.empty ();
    drops.each (function (drop) {
            drop.identify ()
                Droppables.add (drop.id, 
                                { hoverclass: "genericHoverClass",
                                        onDrop: dropAction });
        });
}

function startDragging (itm, e) {
    var target = Event.element(e);
    if (target.up().up().tagName != "TBODY")
        return false;
    
    var handle = $("dragDropVisual");
    var count = $('messageList').getSelectedRowsId().length;
    
    handle.update (count);
    if (e.shiftKey)
        handle.addClassName ("copy");
    handle.show();
}

function whileDragging (itm, e) {
    if (e) {
        var handle = $("dragDropVisual");
        if (e.shiftKey)
            handle.addClassName ("copy");
        else if (handle.hasClassName ("copy"))
            handle.removeClassName ("copy");
    }
}

function stopDragging () {
    var handle = $("dragDropVisual");
    handle.hide();
    if (handle.hasClassName ("copy"))
        handle.removeClassName ("copy");
}

function dropAction (dropped, zone, e) {
    var destination = zone.up("div.dTreeNode");
    var f;
    
    if ($("dragDropVisual").hasClassName("copy")) {
        // Message(s) copied
        f = onMailboxMenuCopy.bind(destination);
    }
    else {
        // Message(s) moved
        f = onMailboxMenuMove.bind(destination);
    }
    
    f();
}
