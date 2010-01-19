/* -*- Mode: java; indent-tabs-mode: nil; c-basic-offset: 4 -*- */

var contactSelectorAction = 'acls-contacts';
var defaultUserID = '';
var AclEditor = {
    userRightsHeight: null,
    userRightsWidth: null
};

var usersToSubscribe = [];

function addUser(userName, userID) {
    var result = false;
    if (!$(userID)) {
        var ul = $("userList");
        ul.appendChild(nodeForUser(userName, userID));
        var url = window.location.href;
        var elements = url.split("/");
        elements[elements.length-1] = ("addUserInAcls?uid="
                                       + userID);
        triggerAjaxRequest(elements.join("/"), addUserCallback);
        result = true;
    }
    return result;
}

function addUserCallback(http) {
    // Ignore response
}

function setEventsOnUserNode(node) {
    var n = $(node);
    n.observe("mousedown", listRowMouseDownHandler);
    n.observe("selectstart", listRowMouseDownHandler);
    n.observe("dblclick", onOpenUserRights);
    n.observe("click", onRowClick);

    var cbParents = n.childNodesWithTag("label");
    if (cbParents && cbParents.length) {
        var cbParent = $(cbParents[0]);
        var checkbox = cbParent.childNodesWithTag("input")[0];
        $(checkbox).observe("change", onSubscriptionChange);
    }
}

function onSubscriptionChange(event) {
    var li = this.parentNode.parentNode;
    var username = li.getAttribute("id");
    var idx = usersToSubscribe.indexOf(username);
    if (this.checked) {
        if (idx < 0)
            usersToSubscribe.push(username);
    } else {
        if (idx > -1)
            usersToSubscribe.splice(idx, 1);
    }
}

function nodeForUser(userName, userId) {
    var node = $(document.createElement("li"));
    node.setAttribute("id", userId);

    var span = $(document.createElement("span"));
    span.addClassName("userFullName");
    var image = document.createElement("img");
    image.setAttribute("src", ResourcesURL + "/abcard.gif");
    span.appendChild(image);
    span.appendChild(document.createTextNode(" " + userName));
    node.appendChild(span);

    var label = $(document.createElement("label"));
    label.addClassName("class", "subscriptionArea");
    var cb = document.createElement("input");
    cb.type = "checkbox";
    label.appendChild(cb);
    label.appendChild(document.createTextNode(getLabel("Subscribe User")));
    node.appendChild(label);

    setEventsOnUserNode(node);

    return node;
}

function saveAcls() {
    var uidList = new Array();
    var users = $("userList").childNodesWithTag("li");
    for (var i = 0; i < users.length; i++)
        uidList.push(users[i].getAttribute("id"));
    $("userUIDS").value = uidList.join(",");
    $("aclForm").submit();

    return false;
}

function onUserAdd(event) {
    openUserFolderSelector(null, "user");

    preventDefault(event);
}

function removeUserCallback(http) {
    var node = http.callbackData;

    if (http.readyState == 4
        && isHttpStatus204(http.status))
        node.parentNode.removeChild(node);
    else
        log("error deleting user: " + node.getAttribute("id"));
}

function onUserRemove(event) {
    var userList = $("userList");
    var nodes = userList.getSelectedRows();

    var url = window.location.href;
    var elements = url.split("/");
    elements[elements.length-1] = "removeUserFromAcls?uid=";
    var baseURL = elements.join("/");

    for (var i = 0; i < nodes.length; i++) {
        var userId = nodes[i].getAttribute("id");
        triggerAjaxRequest(baseURL + userId, removeUserCallback, nodes[i]);
    }
    preventDefault(event);
}

function subscribeToFolder(refreshCallback, refreshCallbackData) {
    var result = true;
    if (UserLogin != refreshCallbackData["folder"]) {
        result = addUser(refreshCallbackData["folderName"],
                         refreshCallbackData["folder"]);
    }
    else
        refreshCallbackData["window"].alert(getLabel("You cannot subscribe to a folder that you own!"));
    return result;
}

function openRightsForUserID(userID) {
    var url = window.location.href;
    var elements = url.split("/");
    elements[elements.length-1] = "userRights?uid=" + userID;

    window.open(elements.join("/"), "",
                "width=" + AclEditor.userRightsWidth
                + ",height=" + AclEditor.userRightsHeight
                + ",resizable=0,scrollbars=0,toolbar=0,"
                + "location=0,directories=0,status=0,menubar=0,copyhistory=0");
}

function openRightsForUser(button) {
    var nodes = $("userList").getSelectedRows();
    if (nodes.length > 0)
        openRightsForUserID(nodes[0].getAttribute("id"));

    return false;
}

function openRightsForDefaultUser(event) {
    this.blur(); // required by IE
    openRightsForUserID(defaultUserID);
    Event.stop(event);
}

function onOpenUserRights(event) {
    openRightsForUser();
    preventDefault(event);
}

function onAclLoadHandler() {
    defaultUserID = $("defaultUserID").value;
    var defaultRolesBtn = $("defaultRolesBtn");
    if (defaultRolesBtn) {
        defaultRolesBtn.observe("click", openRightsForDefaultUser);
    }
    var ul = $("userList");
    var lis = ul.childNodesWithTag("li");
    for (var i = 0; i < lis.length; i++)
        setEventsOnUserNode(lis[i]);

    var buttonArea = $("userSelectorButtons");
    if (buttonArea) {
        var buttons = buttonArea.childNodesWithTag("a");
        $("aclAddUser").stopObserving ("click");
        $("aclDeleteUser").stopObserving ("click");
        $("aclAddUser").observe("mousedown", onUserAdd);
        $("aclDeleteUser").observe("mousedown", onUserRemove);
    }

    AclEditor['userRightsHeight'] = window.opener.getUsersRightsWindowHeight();
    AclEditor['userRightsWidth'] = window.opener.getUsersRightsWindowWidth();

    Event.observe(window, "beforeunload", onAclCloseHandler);
}

function onAclCloseHandler(event) {
    if (usersToSubscribe.length) {
        var url = (URLForFolderID($("folderID").value)
                   + "/subscribeUsers?uids=" + usersToSubscribe.join(","));
        new Ajax.Request(url, {
            asynchronous: false,
                    method: 'get',
                    onFailure: function(transport) {
                    log("Can't expunge current folder: " + transport.status);
                }
        });
    }

    return true;
}

document.observe("dom:loaded", onAclLoadHandler);
