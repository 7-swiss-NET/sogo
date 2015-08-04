/* -*- Mode: javascript; indent-tabs-mode: nil; c-basic-offset: 2 -*- */

(function() {
  'use strict';

  /**
   * @ngInject
   */
  MessageController.$inject = ['$scope', '$state', '$mdDialog', 'stateAccounts', 'stateAccount', 'stateMailbox', 'stateMessage', 'encodeUriFilter', 'sgFocus', 'Dialog', 'Account', 'Mailbox', 'Message'];
  function MessageController($scope, $state, $mdDialog, stateAccounts, stateAccount, stateMailbox, stateMessage, encodeUriFilter, focus, Dialog, Account, Mailbox, Message) {
    var vm = this;

    vm.accounts = stateAccounts;
    vm.account = stateAccount;
    vm.mailbox = stateMailbox;
    vm.message = stateMessage;
    vm.service = Message;
    vm.tags = { searchText: '', selected: '' };
    vm.doDelete = doDelete;
    vm.reply = reply;
    vm.replyAll = replyAll;
    vm.forward = forward;
    vm.edit = edit;

    // Watch the message model "flags" attribute to remove on-the-fly a tag from the IMAP message
    // when removed from the message viewer.
    // TODO: this approach should be reviewed once md-chips supports ng-change.
    $scope.$watchCollection('viewer.message.flags', function(oldTags, newTags) {
      _.each(_.difference(newTags, oldTags), function(tag) {
        vm.message.removeTag(tag);
      });
    });

    function doDelete() {
      stateMailbox.$deleteMessages([stateMessage.uid]).then(function() {
        // Remove message from list of messages
        var index = _.findIndex(stateMailbox.$messages, function(o) {
          return o.uid == stateMessage.uid;
        });
        if (index != -1)
          stateMailbox.$messages.splice(index, 1);
        // Remove message object from scope
        vm.message = null;
        $state.go('mail.account.mailbox', { accountId: stateAccount.id, mailboxId: encodeUriFilter(stateMailbox.path) });
      });
    }

    function showMailEditor($event, message) {
      $mdDialog.show({
        parent: angular.element(document.body),
        targetEvent: $event,
        clickOutsideToClose: true,
        escapeToClose: true,
        templateUrl: 'UIxMailEditor',
        controller: 'MessageEditorController',
        controllerAs: 'editor',
        locals: {
          stateAccounts: vm.accounts,
          stateMessage: message
        }
      });
    }

    function reply($event) {
      var message = vm.message.$reply();
      showMailEditor($event, message);
    }

    function replyAll($event) {
      var message = vm.message.$replyAll();
      showMailEditor($event, message);
    }

    function forward($event) {
      var message = vm.message.$forward();
      showMailEditor($event, message);
    }

    function edit($event) {
      vm.message.$editableContent().then(function() {
        showMailEditor($event, vm.message);
      });
    }
  }
  
  angular
    .module('SOGo.MailerUI')  
    .controller('MessageController', MessageController);                                    
})();
