(function(){"use strict";function Administration(){}Administration.$factory=["$q","$timeout","$log","sgSettings","Resource","User",function($q,$timeout,$log,Settings,Resource,User){angular.extend(Administration,{$q:$q,$timeout:$timeout,$log:$log,$$resource:new Resource(Settings.activeUser("folderURL"),Settings.activeUser()),activeUser:Settings.activeUser(),$User:User});return new Administration}];try{angular.module("SOGo.AdministrationUI")}catch(e){angular.module("SOGo.AdministrationUI",["SOGo.Common"])}angular.module("SOGo.AdministrationUI").factory("Administration",Administration.$factory)})();
//# sourceMappingURL=Administration.services.js.map