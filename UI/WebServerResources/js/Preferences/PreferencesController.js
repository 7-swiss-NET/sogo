/* -*- Mode: javascript; indent-tabs-mode: nil; c-basic-offset: 2 -*- */
/* JavaScript for SOGoPreferences */

(function() {
  'use strict';
  
  /**
   * @ngInject
   */
  PreferencesController.$inject = ['$q', '$window', '$state', '$mdMedia', '$mdSidenav', '$mdDialog', '$mdToast', 'sgSettings', 'sgFocus', 'Dialog', 'User', 'Account', 'Preferences', 'Authentication'];
  function PreferencesController($q, $window, $state, $mdMedia, $mdSidenav, $mdDialog, $mdToast, sgSettings, focus, Dialog, User, Account, Preferences, Authentication) {
    var vm = this, account, mailboxes = [], today = new Date(), tomorrow = today.beginOfDay().addDays(1);

    this.$onInit = function() {
      this.preferences = Preferences;
      this.passwords = { newPassword: null, newPasswordConfirmation: null };
      this.timeZonesList = $window.timeZonesList;
      this.timeZonesSearchText = '';
      this.sieveVariablesCapability = ($window.sieveCapabilities.indexOf('variables') >= 0);


      if (sgSettings.activeUser('path').mail) {
        // Fetch a flatten version of the mailboxes list of the main account (0)
        // This list will be forwarded to the Sieve filter controller
        account = new Account({ id: 0 });
        account.$getMailboxes().then(function() {
          var allMailboxes = account.$flattenMailboxes({all: true}),
              index = -1,
              length = allMailboxes.length;
          while (++index < length) {
            mailboxes.push(allMailboxes[index]);
          }
        });
      }

      // Set alternate avatar in User service
      if (Preferences.defaults.SOGoAlternateAvatar)
        User.$alternateAvatar = Preferences.defaults.SOGoAlternateAvatar;

      this.updateVacationDates();
    };

    this.go = function(module, form) {
      if (form.$valid) {
        // Close sidenav on small devices
        if ($mdMedia('xs'))
          $mdSidenav('left').close();
        $state.go('preferences.' + module);
      }
    };

    this.onLanguageChange = function(form) {
      if (form.$valid)
        Dialog.confirm(l('Warning'),
                       l('Save preferences and reload page now?'),
                       {ok: l('Yes'), cancel: l('No')})
        .then(function() {
          vm.save(form, { quick: true }).then(function() {
            $window.location.reload(true);
          });
        });
    };

    this.addCalendarCategory = function(form) {
      this.preferences.defaults.SOGoCalendarCategoriesColors["New category"] = "#aaa";
      this.preferences.defaults.SOGoCalendarCategories.push("New category");
      focus('calendarCategory_' + (this.preferences.defaults.SOGoCalendarCategories.length - 1));
      form.$setDirty();
    };

    this.removeCalendarCategory = function(index, form) {
      var key = this.preferences.defaults.SOGoCalendarCategories[index];
      this.preferences.defaults.SOGoCalendarCategories.splice(index, 1);
      delete this.preferences.defaults.SOGoCalendarCategoriesColors[key];
      form.$setDirty();
    };

    this.addContactCategory = function(form) {
      var i = _.indexOf(this.preferences.defaults.SOGoContactsCategories, "");
      if (i < 0) {
        this.preferences.defaults.SOGoContactsCategories.push("");
        i = this.preferences.defaults.SOGoContactsCategories.length - 1;
      }
      focus('contactCategory_' + i);
      form.$setDirty();
    };

    this.removeContactCategory = function(index, form) {
      this.preferences.defaults.SOGoContactsCategories.splice(index, 1);
      form.$setDirty();
    };

    this.addMailAccount = function(ev, form) {
      var account;

      this.preferences.defaults.AuxiliaryMailAccounts.push({});

      account = _.last(this.preferences.defaults.AuxiliaryMailAccounts);
      angular.extend(account,
                     {
                       name: "",
                       identities: [
                         {
                           fullName: "",
                           email: ""
                         }
                       ],
                       receipts: {
                         receiptAction: "ignore",
                         receiptNonRecipientAction: "ignore",
                         receiptOutsideDomainAction: "ignore",
                         receiptAnyAction: "ignore"
                       }
                     });

      $mdDialog.show({
        controller: 'AccountDialogController',
        controllerAs: '$AccountDialogController',
        templateUrl: 'editAccount?account=new',
        targetEvent: ev,
        locals: {
          defaults: this.preferences.defaults,
          account: account,
          accountId: (this.preferences.defaults.AuxiliaryMailAccounts.length-1),
          mailCustomFromEnabled: $window.mailCustomFromEnabled
        }
      }).then(function() {
        form.$setDirty();
      }).catch(function() {
        vm.preferences.defaults.AuxiliaryMailAccounts.pop();
      });
    };

    this.editMailAccount = function(event, index, form) {
      var account = this.preferences.defaults.AuxiliaryMailAccounts[index];
      $mdDialog.show({
        controller: 'AccountDialogController',
        controllerAs: '$AccountDialogController',
        templateUrl: 'editAccount?account=' + index,
        targetEvent: event,
        locals: {
          defaults: this.preferences.defaults,
          account: account,
          accountId: index,
          mailCustomFromEnabled: $window.mailCustomFromEnabled
        }
      }).then(function() {
        vm.preferences.defaults.AuxiliaryMailAccounts[index] = account;
        form.$setDirty();
      });
    };

    this.removeMailAccount = function(index, form) {
      this.preferences.defaults.AuxiliaryMailAccounts.splice(index, 1);
      form.$setDirty();
    };
    
    this.addMailLabel = function(form) {
      // See $omit() in the Preferences services for real key generation
      var key = '_$$' + guid();
      this.preferences.defaults.SOGoMailLabelsColors[key] =  ["New label", "#aaa"];
      focus('mailLabel_' + (_.size(this.preferences.defaults.SOGoMailLabelsColors) - 1));
      form.$setDirty();
    };

    this.removeMailLabel = function(key, form) {
      delete this.preferences.defaults.SOGoMailLabelsColors[key];
      form.$setDirty();
    };

    this.addMailFilter = function(ev, form) {
      var filter = { match: 'all' };

      $mdDialog.show({
        templateUrl: 'editFilter?filter=new',
        controller: 'FiltersDialogController',
        controllerAs: 'filterEditor',
        targetEvent: ev,
        locals: {
          filter: filter,
          mailboxes: mailboxes,
          labels: this.preferences.defaults.SOGoMailLabelsColors
        }
      }).then(function() {
        if (!vm.preferences.defaults.SOGoSieveFilters)
          vm.preferences.defaults.SOGoSieveFilters = [];
        vm.preferences.defaults.SOGoSieveFilters.push(filter);
        form.$setDirty();
      });
    };
    
    this.editMailFilter = function(ev, index, form) {
      var filter = angular.copy(this.preferences.defaults.SOGoSieveFilters[index]);
      
      $mdDialog.show({
        templateUrl: 'editFilter?filter=' + index,
        controller: 'FiltersDialogController',
        controllerAs: 'filterEditor',
        targetEvent: null,
        locals: {
          filter: filter,
          mailboxes: mailboxes,
          labels: this.preferences.defaults.SOGoMailLabelsColors
        }
      }).then(function() {
        vm.preferences.defaults.SOGoSieveFilters[index] = filter;
        form.$setDirty();
      });
    };

    this.removeMailFilter = function(index, form) {
      this.preferences.defaults.SOGoSieveFilters.splice(index, 1);
      form.$setDirty();
    };

    this.addDefaultEmailAddresses = function(form) {
      var v = [];

      if (angular.isDefined(this.preferences.defaults.Vacation.autoReplyEmailAddresses)) {
        v = this.preferences.defaults.Vacation.autoReplyEmailAddresses.split(',');
      }

      this.preferences.defaults.Vacation.autoReplyEmailAddresses = (_.union($window.defaultEmailAddresses.split(','), v)).join(',');
      form.$setDirty();
    };

    this.userFilter = function(search, excludedUsers) {
      if (search.length < sgSettings.minimumSearchLength())
        return [];

      return User.$filter(search, excludedUsers).then(function(users) {
        // Set users avatars
        _.forEach(users, function(user) {
          if (!user.$$image) {
            if (user.image)
              user.$$image = user.image;
            else
              vm.preferences.avatar(user.c_email, 32, {no_404: true}).then(function(url) {
                user.$$image = url;
              });
            }
        });
        return users;
      });
    };

    this.confirmChanges = function($event, form) {
      var target;

      if (form.$dirty && $form.$valid) {
        // Stop default action
        $event.preventDefault();
        $event.stopPropagation();

        // Find target link
        target = $event.target;
        while (target.tagName != 'A')
          target = target.parentNode;

        Dialog.confirm(l('Unsaved Changes'),
                       l('Do you want to save your changes made to the configuration?'),
                       { ok: l('Save'), cancel: l('Don\'t Save') })
        .then(function() {
          // Save & follow link
          vm.save(form, { quick: true }).then(function() {
            $window.location = target.href;
          });
        }, function() {
          // Don't save & follow link
          $window.location = target.href;
        });
      }
    };

    this.save = function(form, options) {
      var i, sendForm, addresses, defaultAddresses, domains, domain;

      sendForm = true;
      domains = [];

      // We do some sanity checks
      if ($window.forwardConstraints > 0 &&
          angular.isDefined(this.preferences.defaults.Forward) &&
          this.preferences.defaults.Forward.enabled &&
          angular.isDefined(this.preferences.defaults.Forward.forwardAddress)) {

        addresses = this.preferences.defaults.Forward.forwardAddress.split(",");

        // We first extract the list of 'known domains' to SOGo
        defaultAddresses = $window.defaultEmailAddresses.split(/, */);

        _.forEach(defaultAddresses, function(adr) {
          var domain = adr.split("@")[1];
          if (domain) {
            domains.push(domain.toLowerCase());
          }
        });

        // We check if we're allowed or not to forward based on the domain defaults
        for (i = 0; i < addresses.length && sendForm; i++) {
          domain = addresses[i].split("@")[1].toLowerCase();
          if (domains.indexOf(domain) < 0 && $window.forwardConstraints == 1) {
            Dialog.alert(l('Error'), l("You are not allowed to forward your messages to an external email address."));
            sendForm = false;
          }
          else if (domains.indexOf(domain) >= 0 && $window.forwardConstraints == 2) {
            Dialog.alert(l('Error'), l("You are not allowed to forward your messages to an internal email address."));
            sendForm = false;
          }
        }
      }

      if (sendForm)
        return this.preferences.$save().then(function(data) {
          if (!options || !options.quick) {
            $mdToast.show(
              $mdToast.simple()
                .content(l('Preferences saved'))
                .position('bottom right')
                .hideDelay(2000));
            form.$setPristine();
          }
        });

      return $q.reject();
    };

    this.canChangePassword = function() {
      if (this.passwords.newPassword && this.passwords.newPassword.length > 0 &&
          this.passwords.newPasswordConfirmation && this.passwords.newPasswordConfirmation.length &&
          this.passwords.newPassword == this.passwords.newPasswordConfirmation)
        return true;

      return false;
    };
    
    this.changePassword = function() {
      Authentication.changePassword(this.passwords.newPassword).then(function() {
        var alert = $mdDialog.alert({
          title: l('Password'),
          content: l('The password was changed successfully.'),
          ok: l('OK')
        });
        $mdDialog.show( alert )
          .finally(function() {
            alert = undefined;
          });
      }, function(msg) {
        var alert = $mdDialog.alert({
          title: l('Password'),
          content: msg,
          ok: l('OK')
        });
        $mdDialog.show( alert )
          .finally(function() {
            alert = undefined;
          });
      });
    };

    this.timeZonesListFilter = function(filter) {
      return _.filter(this.timeZonesList, function(value) {
        return value.toUpperCase().indexOf(filter.toUpperCase()) >= 0;
      });
    };

    this.updateVacationDates = function() {
      var d = this.preferences.defaults;

      if (d &&
          d.Vacation &&
          d.Vacation.enabled) {
        this.toggleVacationStartDate();
        this.toggleVacationEndDate();
      }
    };

    this.toggleVacationStartDate = function() {
      var v;

      v = this.preferences.defaults.Vacation;

      if (v.startDateEnabled) {
        // Enabling the start date
        if (v.endDateEnabled && v.startDate.getTime() > v.endDate.getTime()) {
          v.startDate = new Date(v.endDate.getTime());
          v.startDate.addDays(-1);
        }
        if (v.startDate.getTime() < tomorrow.getTime()) {
          v.startDate = new Date(tomorrow.getTime());
        }
      }
    };

    this.toggleVacationEndDate = function() {
      var v;

      v = this.preferences.defaults.Vacation;

      if (v.endDateEnabled) {
        // Enabling the end date
        if (v.startDateEnabled && v.endDate.getTime() < v.startDate.getTime()) {
          v.endDate = new Date(v.startDate.getTime());
          v.endDate.addDays(1);
        }
        else if (v.endDate.getTime() < tomorrow.getTime()) {
          v.endDate = new Date(tomorrow.getTime());
        }
      }
    };

    this.validateVacationStartDate = function(date) {
      var d = vm.preferences.defaults, r = true;
      if (d &&
          d.Vacation &&
          d.Vacation.enabled) {
        if (d.Vacation.startDateEnabled) {
          r = (!d.Vacation.endDateEnabled ||
               date.getTime() < d.Vacation.endDate.getTime()) &&
            date.getTime() >= tomorrow.getTime();
        }
      }

      return r;
    };

    this.validateVacationEndDate = function(date) {
      var d = vm.preferences.defaults, r = true;
      if (d &&
          d.Vacation &&
          d.Vacation.enabled) {
        if (d.Vacation.endDateEnabled) {
          r = (!d.Vacation.startDateEnabled ||
               date.getTime() > d.Vacation.startDate.getTime()) &&
            date.getTime() >= tomorrow.getTime();
        }
      }

      return r;
    };
  }

  angular
    .module('SOGo.PreferencesUI')
    .controller('PreferencesController', PreferencesController);

})();
