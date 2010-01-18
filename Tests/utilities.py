#!/usr/bin/python

import unittest
import webdavlib

class TestUtility(unittest.TestCase):
    def __init__(self, client):
        self.client = client
        self.userInfo = {}

    def fetchUserInfo(self, login):
        if not self.userInfo.has_key(login):
            resource = "/SOGo/dav/%s/" % login
            propfind = webdavlib.WebDAVPROPFIND(resource,
                                                ["displayname",
                                                 "{urn:ietf:params:xml:ns:caldav}calendar-user-address-set"],
                                                0)
            propfind.xpath_namespace = { "D": "DAV:",
                                         "C": "urn:ietf:params:xml:ns:caldav" }
            self.client.execute(propfind)
            assert(propfind.response["status"] == 207)
            name_nodes = propfind.xpath_evaluate('/D:multistatus/D:response/D:propstat/D:prop/D:displayname',
                                                 None)
            email_nodes = propfind.xpath_evaluate('/D:multistatus/D:response/D:propstat/D:prop/C:calendar-user-address-set/D:href',
                                                  None)
            self.userInfo[login] = (name_nodes[0].childNodes[0].nodeValue,
                                    email_nodes[0].childNodes[0].nodeValue)

        return self.userInfo[login]

class TestACLUtility(TestUtility):
    def __init__(self, client, resource):
        TestUtility.__init__(self, client)
        self.resource = resource

    def subscribe(self, subscribers=None):
        rights_str = "".join(["<%s/>" % x
                              for x in self.rightsToSOGoRights(rights) ])
        subscribeQuery = ("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
                          + "<subscribe"
                          + " xmlns=\"urn:inverse:params:xml:ns:inverse-dav\"")
        if (subscribers is not None):
            subscribeQuery = (subscribeQuery
                              + " users=\"%s\"" % subscribers.join(","))
        subscribeQuery = subscribeQuery + "/>"
        post = webdavlib.HTTPPOST(self.resource, subscribeQuery)
        post.content_type = "application/xml; charset=\"utf-8\""
        self.client.execute(post)
        self.assertEquals(post.response["status"], 204,
                          "subscribtion failure to set '%s' (status: %d)"
                          % (rights_str, post.response["status"]))

    def rightsToSOGoRights(self, rights):
        self.fail("subclass must implement this method")

    def setupRights(self, username, rights):
        rights_str = "".join(["<%s/>" % x for x in self.rightsToSOGoRights(rights) ])
        aclQuery = ("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
                    + "<acl-query"
                    + " xmlns=\"urn:inverse:params:xml:ns:inverse-dav\">"
                    + "<set-roles user=\"%s\">%s</set-roles>" % (username,
                                                                 rights_str)
                    + "</acl-query>")

        post = webdavlib.HTTPPOST(self.resource, aclQuery)
        post.content_type = "application/xml; charset=\"utf-8\""
        self.client.execute(post)
        self.assertEquals(post.response["status"], 204,
                          "rights modification: failure to set '%s' (status: %d)"
                          % (rights_str, post.response["status"]))

# Calendar:
#   rights:
#     v: view all
#     d: view date and time
#     m: modify
#     r: respond
#   short rights notation: { "c": create,
#                            "d": delete,
#                            "pu": public,
#                            "pr": private,
#                            "co": confidential }
class TestCalendarACLUtility(TestACLUtility):
    def rightsToSOGoRights(self, rights):
        sogoRights = []
        if rights.has_key("c") and rights["c"]:
            sogoRights.append("ObjectCreator")
        if rights.has_key("d") and rights["d"]:
            sogoRights.append("ObjectEraser")

        classes = { "pu": "Public",
                    "pr": "Private",
                    "co": "Confidential" }
        rights_table = { "v": "Viewer",
                         "d": "DAndTViewer",
                         "m": "Modifier",
                         "r": "Responder" }
        for k in classes.keys():
            if rights.has_key(k):
                right = rights[k]
                sogo_right = "%s%s" % (classes[k], rights_table[right])
                sogoRights.append(sogo_right)

        return sogoRights

# Addressbook:
#   short rights notation: { "c": create,
#                            "d": delete,
#                            "e": edit,
#                            "v": view }
class TestAddressBookACLUtility(TestACLUtility):
    def rightsToSOGoRights(self, rights):
        sogoRightsTable = { "c": "ObjectCreator",
                            "d": "ObjectEraser",
                            "v": "ObjectViewer",
                            "e": "ObjectEditor" }

        sogoRights = []
        for k in rights.keys():
            sogoRights.append(sogoRightsTable[k])

        return sogoRights
