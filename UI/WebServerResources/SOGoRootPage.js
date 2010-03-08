/* -*- Mode: java; indent-tabs-mode: nil; c-basic-offset: 4 -*- */

var dialogs = {};

function initLogin() {
    var date = new Date();
    date.setTime(date.getTime() - 86400000);

    var href = $("connectForm").action.split("/");
    var appName = href[href.length-2];

    document.cookie = ("0xHIGHFLYxSOGo=discarded"
                       + "; expires=" + date.toGMTString()
                       + "; path=/" + appName + "/");

    var about = $("about");
    if (about) {
        about.observe("click", function(event) {
                                  $("aboutBox").show();
                                  event.stop() });

        var aboutClose = $("aboutClose");
        aboutClose.observe("click", function(event) {
                                  $("aboutBox").hide();
                                  event.stop() });
    }

    var submit = $("submit");
    submit.observe("click", onLoginClick);

    var userName = $("userName");
    userName.focus();
    userName.observe("keydown", onFieldKeyDown);

    var passw = $("password");
    passw.observe("keydown", onFieldKeyDown);

    var image = $("preparedAnimation");
    image.parentNode.removeChild(image);

    var submitBtn = $("submit");
    submitBtn.disabled = false;
}

function onFieldKeyDown(event) {
    if (event.keyCode == Event.KEY_RETURN)
        if ($("password").value.length > 0
            && $("userName").value.length > 0)
            return onLoginClick (event);
        else
            Event.stop(event);
}

function onLoginClick(event) {
    var userNameField = $("userName");
    var userName = userNameField.value;
    var password = $("password").value;
    var language = $("language");

    if (userName.length > 0) {
        SetLogMessage("errorMessage", null);
        this.disabled = true;
        startAnimation($("animation"));

        if (typeof(loginSuffix) != "undefined"
            && loginSuffix.length > 0
            && !userName.endsWith(loginSuffix))
            userName += loginSuffix;

        var url = $("connectForm").getAttribute("action");
        var parameters = ("userName=" + encodeURIComponent(userName)
                          + "&password=" + encodeURIComponent(password));
        if (language)
            parameters += ((language.value == "WONoSelectionString")
                           ? ""
                           : ("&language=" + language.value));
        /// Discarded as it seems to create a cookie for nothing. To discard
        //  a cookie in JS, have a look here: http://www.quirksmode.org/js/cookies.html
        //document.cookie = "";
        triggerAjaxRequest(url, onLoginCallback, null, (parameters),
                           { "Content-type": "application/x-www-form-urlencoded",
                                   "Content-length": parameters.length,
                                   "Connection": "close" });
    }
    else
        userNameField.focus();

    preventDefault(event);
}

function onLoginCallback(http) {
    if (http.readyState == 4) {
        var submitBtn = $("submit");

        if (isHttpStatus204(http.status)) {
            // Make sure browser's cookies are enabled
            var loginCookie = readLoginCookie();
            if (!loginCookie) {
                SetLogMessage("errorMessage", _("cookiesNotEnabled"));
                submitBtn.disabled = false;
                return;
            }

            redirectToUserPage();
        }
        else {
            if (http.status == 403
                && http.getResponseHeader("content-type")
                == "application/json") {
                var jsonResponse = http.responseText.evalJSON(false);
                handlePasswordError(jsonResponse);
            } else {
                SetLogMessage("errorMessage", _("An unhandled error occurred."));
            }
            submitBtn.disabled = false;
        }
    }
}

function redirectToUserPage() {
    // Redirect to proper page
    var userName = $("userName").value;
    if (typeof(loginSuffix) != "undefined"
        && loginSuffix.length > 0
        && !userName.endsWith(loginSuffix))
        userName += loginSuffix;
    var address = "" + window.location.href;
    var baseAddress = ApplicationBaseURL + encodeURIComponent(userName);
    var altBaseAddress;
    if (baseAddress[0] == "/") {
        var parts = address.split("/");
        var hostpart = parts[2];
        var protocol = parts[0];
        baseAddress = protocol + "//" + hostpart + baseAddress;
    }
    var altBaseAddress;
    var parts = baseAddress.split("/");
    parts.splice(3, 0);
    altBaseAddress = parts.join("/");

    var newAddress;
    if ((address.startsWith(baseAddress)
         || address.startsWith(altBaseAddress))
        && !address.endsWith("/logoff"))
        newAddress = address;
    else
        newAddress = baseAddress;
    window.location.href = newAddress;
}

function handlePasswordError(jsonResponse) {
    var perr = jsonResponse["LDAPPasswordPolicyError"];
    if (perr == PolicyNoError) {
        SetLogMessage("errorMessage", _("Wrong username or password."));
    } else if (perr == PolicyAccountLocked) {
        SetLogMessage("errorMessage",
                      _("Your account was locked due to too many"
                        + " failed attempts."));
    } else if (perr == PolicyChangeAfterReset
               || perr == PolicyPasswordExpired) {
        showPasswordDialog("change", createPasswordChangeDialog, 5);
    } else
        SetLogMessage("errorMessage",
                      _("Login failed due to unhandled error case: " + perr));
}

function showPasswordDialog(dialogType, constructor, parameters) {
    var dialog = dialogs[dialogType];
    if (!dialog) {
        dialog = constructor(parameters);
        var form = $("connectForm");
        form.appendChild(dialog);
        dialogs[dialogType] = dialog;
    }
    var password = $("password");
    var offsets = password.cumulativeOffset();
    dialog.show();
    var top = offsets[1] + 5;
    var left = offsets[0] + password.clientWidth - dialog.clientWidth;
    dialog.setStyle({ "top": top + "px", "left": left + "px"});
}

function createPasswordChangeDialog() {
    var fields = createElement("p");
    createElement("span", "passwordError", null, null, null, fields);

    var fieldNames = [ "newPassword", "newPassword2" ];
    var fieldLabels = [ _("New password:"), _("Confirmation:") ];
    for (var i = 0; i < fieldNames.length; i++) {
        var label = createElement("label", null, null, null, null, fields);
        label.appendChild(document.createTextNode(fieldLabels[i]));
        createElement("input", fieldNames[i], "textField",
                      { "name": fieldNames[i], "type": "text" },
                      null, label);
        createElement("br", null, null, null, null, fields);
    }

    var button = createButton("passwordOKButton", _("OK"), passwordDialogOK);
    button.addClassName("actionButton");
    fields.appendChild(button);
    fields.appendChild(document.createTextNode(" "));
    button = createButton("passwordCancelButton",
                          _("Cancel"), passwordDialogCancel);
    fields.appendChild(button);

    var dialog = createDialog("passwordChangeDialog",
                              _("Change your Password"),
                              _("Your password has expired, please"
                                +" enter a new one below:"),
                              fields,
                              "right");

    return dialog;
}

function passwordDialogOK(event) {
    var field = $("newPassword");
    var confirmationField = $("newPassword2");
    if (field && confirmationField) {
        var newPassword = field.value;
        if (newPassword == confirmationField.value) {
            if (newPassword.length > 0) {
                var userName = $("userName");
                var password = $("password");
                var policy = new PasswordPolicy(userName.value,
                                                password.value);
                policy.setCallbacks(onPasswordChangeSuccess,
                                    onPasswordChangeFailure);
                policy.changePassword(newPassword);
            }
            else
                SetLogMessage("passwordError",
                              _("Password must not be empty."));
        }
        else {
            SetLogMessage("passwordError",
                          _("The passwords do not match. Please try again."));
            field.focus();
            field.select();
        }
    }
    event.stop();
}

function onPasswordChangeSuccess() {
    SetLogMessage("passwordError", _("Please wait..."));
    redirectToUserPage();
}

function onPasswordChangeFailure(code, message) {
    SetLogMessage("passwordError", message);
}

function passwordDialogCancel(event) {
    var dialog = $("passwordChangeDialog");
    dialog.hide();
    event.stop();
}

function createPasswordGraceDialog(tries) {
    var button = createButton("graceOKButton", _("OK"));
    button.observe("click", passwordGraceDialogOK);
    button.addClassName("actionButton");

    return createDialog("passwordGraceDialog",
                        _("Password Grace Period"),
                        _("You have %{0} logins remaining before your"
                          + " password expires. Please change your"
                          + " password in the preference dialog.")
                        .formatted(tries),
                        button,
                        "right");
}

function passwordGraceDialogOK(event) {
    var dialog = $("passwordGraceDialog");
    dialog.hide();
    event.stop();
}

document.observe("dom:loaded", initLogin);
