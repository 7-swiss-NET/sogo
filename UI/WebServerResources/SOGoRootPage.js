function initLogin() {
  var date = new Date();
  date.setTime(date.getTime() - 86400000);
  document.cookie = ("0xHIGHFLYxSOGo-0.9=discard; path=/"
		     + "; expires=" + date.toGMTString());
  var submit = $("submit");
  Event.observe(submit, "click", onLoginClick);

  var userName = $("userName");
  userName.focus();

  var image = $("preparedAnimation");
  image.parentNode.removeChild(image);
}

function onLoginClick(event) {
  startAnimation($("loginButton"), $("submit"));

  var userName = $("userName").value;
  var password = $("password").value;

  if (userName.length > 0) {
    var url = $("connectForm").getAttribute("action");
    var parameters = ("userName=" + encodeURI(userName) + "&password=" + encodeURI(password));
    document.cookie = "";
    triggerAjaxRequest(url, onLoginCallback, null, parameters,
		       { "Content-type": "application/x-www-form-urlencoded",
			 "Content-length": parameters.length,
			 "Connection": "close" });
  }

  preventDefault(event);
}

function onLoginCallback(http) {
  if (http.readyState == 4) {
    if (isHttpStatus204(http.status)) {
      var userName = $("userName").value;
      var address = "" + window.location.href;
      var baseAddress = ApplicationBaseURL + encodeURI(userName);
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
  }
}

FastInit.addOnLoad(initLogin);
