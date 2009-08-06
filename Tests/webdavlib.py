import httplib
import M2Crypto.httpslib
import time
import xml.sax.saxutils
import xml.dom.ext.reader.Sax2
import sys

class WebDAVClient:
    def __init__(self, hostname, port, username, password, forcessl = False):
        if port == "443" or forcessl:
            self.conn = M2Crypto.httpslib.HTTPSConnection(hostname, int(port),
                                                          True)
        else:
            self.conn = httplib.HTTPConnection(hostname, port, True)

        self.simpleauth_hash = (("%s:%s" % (username, password))
                                .encode('base64')[:-1])

    def _prepare_headers(self, query, body):
        headers = { "User-Agent": "Mozilla/5.0",
                    "authorization": "Basic %s" % self.simpleauth_hash }
        if body is not None:
            headers["content-length"] = len(body)
        if query.__dict__.has_key("query") and query.depth is not None:
            headers["depth"] = query.depth
        if query.__dict__.has_key("content_type"):
            headers["content-type"] = query.content_type

        return headers

    def execute(self, query):
        body = query.render()

        query.start = time.time()
        self.conn.request(query.method, query.url,
                          body, self._prepare_headers(query, body))
        query.set_response(self.conn.getresponse());
        query.duration = time.time() - query.start

class HTTPSimpleQuery:
    method = None

    def __init__(self, url):
        self.url = url
        self.response = None
        self.start = -1
        self.duration = -1

    def render(self):
        return None

    def set_response(self, http_response):
        headers = {}
        for rk, rv in http_response.getheaders():
            k = rk.lower()
            headers[k] = rv
        self.response = { "headers": headers,
                          "status": http_response.status,
                          "version": http_response.version,
                          "body": http_response.read() }

class HTTPGET(HTTPSimpleQuery):
    method = "GET"

class HTTPQuery(HTTPSimpleQuery):
    def __init__(self, url, content_type):
        HTTPSimpleQuery.__init__(self, url)
        self.content_type = content_type

class HTTPPUT(HTTPQuery):
    method = "PUT"

    def __init__(self, url, content, content_type = "application/octet-stream"):
        HTTPQuery.__init__(self, url, content_type)
        self.content = content

    def render(self):
        return self.content

class HTTPPOST(HTTPPUT):
    method = "POST"

class WebDAVQuery(HTTPQuery):
    method = None

    def __init__(self, url, depth = None):
        HTTPQuery.__init__(self, url, "application/xml; charset=\"utf-8\"")
        self.depth = depth
        self.ns_mgr = _WD_XMLNS_MGR()
        self.top_node = None
        self.xml_response = None

    def render(self):
        if self.top_node is not None:
            text = ("<?xml version=\"1.0\" encoding=\"utf-8\"?>\n%s"
                    % self.top_node.render(self.ns_mgr.render()))
        else:
            text = ""

        return text

    def render_tag(self, tag):
        cb = tag.find("}")
        if cb > -1:
            ns = tag[1:cb]
            real_tag = tag[cb+1:]
            new_tag = self.ns_mgr.register(real_tag, ns)
        else:
            new_tag = tag

        return new_tag

    def set_response(self, http_response):
        HTTPQuery.set_response(self, http_response)
        headers = self.response["headers"]
        if (headers.has_key("content-type")
            and headers.has_key("content-length")
            and (headers["content-type"].startswith("application/xml")
                 or headers["content-type"].startswith("text/xml"))
            and int(headers["content-length"]) > 0):
            dom_response = xml.dom.ext.reader.Sax2.FromXml(self.response["body"])
            self.response["document"] = dom_response.documentElement

class WebDAVMKCOL(WebDAVQuery):
    method = "MKCOL"

class WebDAVDELETE(WebDAVQuery):
    method = "DELETE"

class WebDAVREPORT(WebDAVQuery):
    method = "REPORT"

class WebDAVPROPFIND(WebDAVQuery):
    method = "PROPFIND"

    def __init__(self, url, properties, depth = None):
        WebDAVQuery.__init__(self, url, depth)
        self.top_node = _WD_XMLTreeElement("propfind")
        props = _WD_XMLTreeElement("prop")
        self.top_node.append(props)
        for prop in properties:
            prop_tag = self.render_tag(prop)
            props.append(_WD_XMLTreeElement(prop_tag))

class WebDAVCalendarMultiget(WebDAVREPORT):
    def __init__(self, url, properties, hrefs):
        WebDAVQuery.__init__(self, url)
        multiget_tag = self.ns_mgr.register("calendar-multiget", "urn:ietf:params:xml:ns:caldav")
        self.top_node = _WD_XMLTreeElement(multiget_tag)
        props = _WD_XMLTreeElement("prop")
        self.top_node.append(props)
        for prop in properties:
            prop_tag = self.render_tag(prop)
            props.append(_WD_XMLTreeElement(prop_tag))

        for href in hrefs:
            href_node = _WD_XMLTreeElement("href")
            self.top_node.append(href_node)
            href_node.append(_WD_XMLTreeTextNode(href))

class WebDAVSyncQuery(WebDAVREPORT):
    def __init__(self, url, token, properties):
        WebDAVQuery.__init__(self, url)
        self.top_node = _WD_XMLTreeElement("sync-collection")

        sync_token = _WD_XMLTreeElement("sync-token")
        self.top_node.append(sync_token)
        if token is not None:
            sync_token.append(_WD_XMLTreeTextNode(token))

        props = _WD_XMLTreeElement("prop")
        self.top_node.append(props)
        for prop in properties:
            prop_tag = self.render_tag(prop)
            props.append(_WD_XMLTreeElement(prop_tag))

# private classes to handle XML stuff
class _WD_XMLNS_MGR:
    def __init__(self):
        self.xmlns = {}
        self.counter = 0

    def render(self):
        text = " xmlns=\"DAV:\""
        for k in self.xmlns:
            text = text + " xmlns:%s=\"%s\"" % (self.xmlns[k], k)

        return text

    def create_key(self, namespace):
        new_nssym = "n%d" % self.counter
        self.counter = self.counter + 1
        self.xmlns[namespace] = new_nssym

        return new_nssym

    def register(self, tag, namespace):
        if namespace != "DAV:":
            if self.xmlns.has_key(namespace):
                key = self.xmlns[namespace]
            else:
                key = self.create_key(namespace)
        else:
            key = None

        if key is not None:
            newTag = "%s:%s" % (key, tag)
        else:
            newTag = tag

        return newTag

class _WD_XMLTreeElement:
    def __init__(self, tag):
        self.tag = tag
        self.children = []

    def append(self, child):
        self.children.append(child)

    def render(self, ns_text = None):
        text = "<" + self.tag

        if ns_text is not None:
            text = text + ns_text

        if len(self.children) > 0:
            text = text + ">"
            for child in self.children:
                text = text + child.render()
            text = text + "</" + self.tag + ">"
        else:
            text = text + "/>"

        return text

class _WD_XMLTreeTextNode:
    def __init__(self, text):
        self.text = xml.sax.saxutils.escape(text)

    def render(self):
        return self.text
