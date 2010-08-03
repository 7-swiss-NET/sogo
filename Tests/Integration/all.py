#!/usr/bin/python

import os, sys, unittest, getopt, traceback, time
import preferences
import sogotests
import unittest

if __name__ == "__main__":
    unittest._TextTestResult.oldStartTest = unittest._TextTestResult.startTest
    unittest._TextTestResult.startTest = sogotests.UnitTestTextTestResultNewStartTest
    unittest._TextTestResult.stopTest = sogotests.UnitTestTextTestResultNewStopTest

    loader = unittest.TestLoader()
    modules = []
    # Duplicated from UIxPreferences.m
    languages = ["Czech", "Dutch", "English", "French", 
                 "German", "Hungarian", "Italian", "BrazilianPortuguese", 
                 "Polish", "Russian", "Spanish", "Swedish", "Ukrainian", "Welsh"]

    # We can disable testing all languages
    testLanguages = False
    opts, args = getopt.getopt (sys.argv[1:], [], ["enable-languages"])
    for o, a in opts:
        if o == "--enable-languages":
            testLanguages = True


    for mod in os.listdir("."):
        if mod.startswith("test-") and mod.endswith(".py"):
            modules.append(mod[:-3])
            __import__(mod[:-3])

    if len(modules) > 0:
        suite = loader.loadTestsFromNames(modules)
        print "%d tests in modules: '%s'" % (suite.countTestCases(),
                                             "', '".join(modules))
        runner = unittest.TextTestRunner(verbosity=2)

        if testLanguages:
            prefs = preferences.preferences()
            # Get the current language
            userLanguageString = prefs.get ("Language")
            if userLanguageString:
                userLanguage = languages.index (userLanguageString)
            else:
                userLanguage = 2

            for i in range (0, len (languages)):
                try:
                    prefs.set ("language", i)
                except Exception, inst:
                    print '-' * 60
                    traceback.print_exc ()
                    print '-' * 60
                
                print "Running test in %s (%d/%d)" % \
                    (languages[i], i + 1, len (languages))
                runner.verbosity = 2
                runner.run(suite)
            # Revert to the original language
            prefs.set ("language", userLanguage)
        else:
            runner.run(suite)

    else:
        print "No test available."
