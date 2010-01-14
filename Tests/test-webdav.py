#!/usr/bin/python

from config import hostname, port, username, password

import unittest
import webdavlib

def fetchUserInfo(login):
    client = webdavlib.WebDAVClient(hostname, port, username, password)
    resource = "/SOGo/dav/%s/" % login
    propfind = webdavlib.WebDAVPROPFIND(resource,
                                        ["displayname",
                                         "{urn:ietf:params:xml:ns:caldav}calendar-user-address-set"],
                                        0)
    propfind.xpath_namespace = { "D": "DAV:",
                                 "C": "urn:ietf:params:xml:ns:caldav" }
    client.execute(propfind)
    assert(propfind.response["status"] == 207)
    name_nodes = propfind.xpath_evaluate('/D:multistatus/D:response/D:propstat/D:prop/D:displayname',
                                          None)
    email_nodes = propfind.xpath_evaluate('/D:multistatus/D:response/D:propstat/D:prop/C:calendar-user-address-set/D:href',
                                          None)

    return (name_nodes[0].childNodes[0].nodeValue, email_nodes[0].childNodes[0].nodeValue)

class WebDAVTest(unittest.TestCase):
    def testPrincipalCollectionSet(self):
        """property: 'principal-collection-set' on collection object"""
        client = webdavlib.WebDAVClient(hostname, port, username, password)
        resource = '/SOGo/dav/%s/' % username
        propfind = webdavlib.WebDAVPROPFIND(resource,
                                            ["{DAV:}principal-collection-set"],
                                            0)
        propfind.xpath_namespace = { "D": "DAV:" }
        client.execute(propfind)
        self.assertEquals(propfind.response["status"], 207)
        nodes = propfind.xpath_evaluate('/D:multistatus/D:response/D:propstat/D:prop/D:principal-collection-set/D:href',
                                        None)
        responseHref = nodes[0].childNodes[0].nodeValue
        if responseHref[0:4] == "http":
            self.assertEquals("http://%s/SOGo/dav/" % hostname, responseHref,
                              "{DAV:}principal-collection-set returned %s instead of 'http../SOGo/dav/'"
                              % ( responseHref, resource ))
        else:
            self.assertEquals("/SOGo/dav/", responseHref,
                              "{DAV:}principal-collection-set returned %s instead of '/SOGo/dav/'"
                              % responseHref)

    def testPrincipalCollectionSet2(self):
        """property: 'principal-collection-set' on non-collection object"""
        client = webdavlib.WebDAVClient(hostname, port, username, password)
        resource = '/SOGo/dav/%s/freebusy.ifb' % username
        propfind = webdavlib.WebDAVPROPFIND(resource,
                                            ["{DAV:}principal-collection-set"],
                                            0)
        propfind.xpath_namespace = { "D": "DAV:" }
        client.execute(propfind)
        self.assertEquals(propfind.response["status"], 207)
        nodes = propfind.xpath_evaluate('/D:multistatus/D:response/D:propstat/D:prop/D:principal-collection-set/D:href',
                                        None)
        responseHref = nodes[0].childNodes[0].nodeValue
        expectedHref = '/SOGo/dav/'
        if responseHref[0:4] == "http":
            self.assertEquals("http://%s%s" % (hostname, expectedHref), responseHref,
                              "{DAV:}principal-collection-set returned %s instead of '%s'"
                              % ( responseHref, expectedHref ))
        else:
            self.assertEquals(expectedHref, responseHref,
                              "{DAV:}principal-collection-set returned %s instead of '%s'"
                              % ( responseHref, expectedHref ))

    def _testPropfindURL(self, resource):
        resourceWithSlash = resource[-1] == '/'
        client = webdavlib.WebDAVClient(hostname, port, username, password)
        propfind = webdavlib.WebDAVPROPFIND(resource,
                                            ["{DAV:}displayname", "{DAV:}resourcetype"],
                                            1)
        propfind.xpath_namespace = { "D": "DAV:" }
        client.execute(propfind)
        self.assertEquals(propfind.response["status"], 207)

        nodes = propfind.xpath_evaluate('/D:multistatus/D:response',
                                        None)
        for node in nodes:
            responseHref = propfind.xpath_evaluate('D:href', node)[0].childNodes[0].nodeValue
            hasSlash = responseHref[-1] == '/'
            resourcetypes = \
                propfind.xpath_evaluate('D:propstat/D:prop/D:resourcetype',
                                        node)[0].childNodes
            isCollection = len(resourcetypes) > 0
            if isCollection:
                self.assertEquals(hasSlash, resourceWithSlash,
                                  "failure with href '%s' while querying '%s'"
                                  % (responseHref, resource))
            else:
                self.assertEquals(hasSlash, False,
                                  "failure with href '%s' while querying '%s'"
                                  % (responseHref, resource))
    
    def testPropfindURL(self):
        """propfind: ensure various NSURL work-arounds"""
        # a collection without /
        self._testPropfindURL('/SOGo/dav/%s' % username)
        # a collection with /
        self._testPropfindURL('/SOGo/dav/%s/' % username)
        # a non-collection
        self._testPropfindURL('/SOGo/dav/%s/freebusy.ifb' % username)

    ## REPORT
    # http://tools.ietf.org/html/rfc3253.html#section-3.8
    def testExpandProperty(self):
        """expand-property"""
        client = webdavlib.WebDAVClient(hostname, port, username, password)
        resource = '/SOGo/dav/%s/' % username
        userInfo = fetchUserInfo(username)

        query_props = {"owner": { "href": resource,
                                  "displayname": userInfo[0]},
                       "principal-collection-set": { "href": "/SOGo/dav/",
                                                     "displayname": "SOGo"}}
        query = webdavlib.WebDAVExpandProperty(resource, query_props.keys(),
                                               ["displayname"])
        client.execute(query)
        self.assertEquals(query.response["status"], 207)

        topResponse = query.xpath_evaluate('/D:multistatus/D:response')[0]
        topHref = query.xpath_evaluate('D:href', topResponse)[0]
        self.assertEquals(resource, topHref.childNodes[0].nodeValue)
        for query_prop in query_props.keys():
            propResponse = query.xpath_evaluate('D:propstat/D:prop/D:%s'
                                                % query_prop, topResponse)[0]


# <?xml version="1.0" encoding="utf-8"?>
# <D:multistatus xmlns:D="DAV:">
#   <D:response>
#     <D:href>/SOGo/dav/wsourdeau/</D:href>
#     <D:propstat>
#       <D:prop>
#         <D:owner>
#           <D:response>
#             <D:href>/SOGo/dav/wsourdeau/</D:href>
#             <D:propstat>
#               <D:prop>
#                 <D:displayname>Wolfgang Sourdeau</D:displayname>
#               </D:prop>
#               <D:status>HTTP/1.1 200 OK</D:status>
#             </D:propstat>
#           </D:response>
#         </D:owner>
            propHref = query.xpath_evaluate('D:response/D:href',
                                            propResponse)[0]
            self.assertEquals(query_props[query_prop]["href"],
                              propHref.childNodes[0].nodeValue,
                              "'%s', href mismatch: exp. '%s', got '%s'"
                              % (query_prop,
                                 query_props[query_prop]["href"],
                                 propHref.childNodes[0].nodeValue))
            propDisplayname = query.xpath_evaluate('D:response/D:propstat/D:prop/D:displayname',
                                                   propResponse)[0]
            self.assertEquals(query_props[query_prop]["displayname"],
                              propDisplayname.childNodes[0].nodeValue,
                              "'%s', displayname mismatch: exp. '%s', got '%s'"
                              % (query_prop,
                                 query_props[query_prop]["displayname"],
                                 propDisplayname.nodeValue))

if __name__ == "__main__":
    unittest.main()
