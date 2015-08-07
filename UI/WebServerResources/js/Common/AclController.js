/* -*- Mode: javascript; indent-tabs-mode: nil; c-basic-offset: 2 -*- */

(function() {
  'use strict';

  /**
   * @ngInject
   */
  AclController.$inject = ['$mdDialog', 'Dialog', 'usersWithACL', 'User', 'folder'];
  function AclController($mdDialog, Dialog, usersWithACL, User, folder) {
    var vm = this;

    vm.users = usersWithACL; // ACL users
    vm.folder = folder;
    vm.selectedUser = null;
    vm.userToAdd = '';
    vm.searchText = '';
    vm.userFilter = userFilter;
    vm.closeModal = closeModal;
    vm.saveModal = saveModal;
    vm.confirmChange = confirmChange;
    vm.removeUser = removeUser;
    vm.addUser = addUser;
    vm.selectUser = selectUser;
    vm.confirmation = { showing: false,
                        message: ''};

    function userFilter($query) {
      return User.$filter($query, folder.$acl.users);
    }

    function closeModal() {
      folder.$acl.$resetUsersRights(); // cancel changes
      $mdDialog.hide();
    }

    function saveModal() {
      folder.$acl.$saveUsersRights().then(function() {
        $mdDialog.hide();
      }, function(data, status) {
        Dialog.alert(l('Warning'), l('An error occured please try again.'));
      });
    }

    function confirmChange(user) {
      var confirmation = user.$confirmRights();
      if (confirmation) {
        vm.confirmation.showing = true;
        vm.confirmation.message = confirmation;
      }
    }

    function removeUser(user) {
      folder.$acl.$removeUser(user.uid).catch(function(data, status) {
        Dialog.alert(l('Warning'), l('An error occured please try again.'));
      });
    }

    function addUser(data) {
      if (data) {
        folder.$acl.$addUser(data).then(function() {
          vm.userToAdd = '';
          vm.searchText = '';
        }, function(error) {
          Dialog.alert(l('Warning'), error);
        });
      }
    }

    function selectUser(user) {
      if (vm.selectedUser == user) {
        vm.selectedUser = null;
      }
      else {
        vm.selectedUser = user;
        vm.selectedUser.$rights();
      }
    }
  }

  angular
    .module('SOGo.Common')
    .controller('AclController', AclController);
})();
