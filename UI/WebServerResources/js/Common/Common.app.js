/* -*- Mode: javascript; indent-tabs-mode: nil; c-basic-offset: 2 -*- */

(function() {
  'use strict';

  angular.module('SOGo.Common', ['ngMaterial'])
    .constant('sgSettings', {
      baseURL: ApplicationBaseURL,
      activeUser: {
        login: UserLogin,
        identification: UserIdentification,
        language: UserLanguage,
        folderURL: UserFolderURL,
        isSuperUser: IsSuperUser
      }
    })

    .constant('sgColors', {
      selection: [
        '#FFFFFF',
        '#330033',
        '#C0C0C0',
        '#999999',
        '#666666',
        '#333333',
        '#000000',
        '#FFCCCC',
        '#FF6666',
        '#FF0000',
        '#CC0000',
        '#990000',
        '#660000',
        '#330000',
        '#FFCC99',
        '#FF9966',
        '#FF9900',
        '#FF6600',
        '#CC6600',
        '#993300',
        '#663300',
        '#FFFF99',
        '#FFFF66',
        '#FFCC66',
        '#FFCC33',
        '#CC9933',
        '#996633',
        '#663333',
        '#FFFFCC',
        '#FFFF33',
        '#FFFF00',
        '#FFCC00',
        '#999900',
        '#666600',
        '#333300',
        '#CCCCCC',
        '#66FF99',
        '#33FF33',
        '#33CC00',
        '#009900',
        '#006600',
        '#003300',
        '#99FFFF',
        '#33FFFF',
        '#66CCCC',
        '#00CCCC',
        '#339999',
        '#336666',
        '#003333',
        '#CCFFFF',
        '#66FFFF',
        '#33CCFF',
        '#3366FF',
        '#3333FF',
        '#000099',
        '#000066',
        '#CCCCFF',
        '#9999FF',
        '#6666CC',
        '#6633FF',
        '#6600CC',
        '#333399',
        '#330099',
        '#FFCCFF',
        '#FF99FF',
        '#CC66CC',
        '#CC33CC',
        '#993399',
        '#663366',
        '#99FF99'
      ]
    })

  // md break-points values are hard-coded in angular-material/src/core/util/constant.js
  // $mdMedia has a built-in support for those values but can also evaluate others
  // For some reasons, angular-material's break-points don't match the specs
  // Here we define values according to specs
    .constant('sgConstant', {
      'sm': '(max-width: 600px)',
      'gt-sm': '(min-width: 600px)',
      'md': '(min-width: 600px) and (max-width: 1024px)',
      'gt-md': '(min-width: 1025px)',
      'lg': '(min-width: 1024px) and (max-width: 1280px)',
      'gt-lg': '(min-width: 1280px)'
    })

    .config(configure);

  configure.$inject = ['$mdThemingProvider'];
  function configure($mdThemingProvider) {
    $mdThemingProvider.definePalette('sogo-green', {
      '50': 'eaf5e9',
      '100': 'cbe5c8',
      '200': 'aad6a5',
      '300': '88c781',
      '400': '66b86a',
      '500': '56b04c',
      '600': '4da143',
      '700': '388e3c',
      '800': '367d2e',
      '900': '225e1b',
      'A100': 'b9f6ca',
      'A200': '69f0ae',
      'A400': '00e676',
      'A700': '00c853',
      'contrastDefaultColor': 'dark',
      'contrastDarkColors': '50 100 200',
      'contrastLightColors': '300 400 500 600 700 800 900'
    });
    $mdThemingProvider.definePalette('sogo-blue', {
      '50': 'f0faf9',
      '100': 'e1f5f3',
      '200': 'ceebe8',
      '300': 'bfe0dd',
      '400': 'b2d6d3',
      '500': 'a1ccc8',
      '600': '8ebfbb',
      '700': '7db3b0',
      '800': '639997',
      '900': '4d8080',
      'A100': 'd4f7fa',
      'A200': 'c3f5fa',
      'A400': '53e3f0',
      'A700': '00b0c0',
      'contrastDefaultColor': 'light',
      'contrastDarkColors': ['50', '100', '200'],
      'contrastLightColors': ['300', '400', '500', '600', '700', '800', '900', 'A100', 'A200', 'A400', 'A700']
    });
    $mdThemingProvider.definePalette('sogo-paper', {
      '50': 'fcf7f8',
      '100': 'f7f1dc',
      '200': 'ede5ca',
      '300': 'e6d8ba',
      '400': 'e2d2a3',
      '500': 'd6c48d',
      '600': 'baa870',
      '700': '857545',
      '800': '524517',
      '900': '433809',
      '1000': '000000',
      'A100': 'ffffff',
      'A200': 'eeeeee',
      'A400': 'bdbdbd',
      'A700': '616161',
      'contrastDefaultColor': 'dark',
      'contrastLightColors': '800 900'
    });
    // Default theme definition
    // .primaryColor will soon be deprecated in favor of primaryPalette (already on dev builds https://groups.google.com/forum/m/#!topic/ngmaterial/-sXR8CYBMPg)
    $mdThemingProvider.theme('default')
      .primaryPalette('sogo-blue', {
        'default': '300',
        'hue-1': '100',
        'hue-2': '400',
        'hue-3': 'A700'
      })
      .accentPalette('sogo-green', {
        'default': '500',
        'hue-1': '200',
        'hue-2': '300',
        'hue-3': 'A700'
      })
      .backgroundPalette('sogo-paper', {
        'default': '100',
        'hue-1': '200',
        'hue-2': '50',
        'hue-3': '500'
      });
  }

})();
