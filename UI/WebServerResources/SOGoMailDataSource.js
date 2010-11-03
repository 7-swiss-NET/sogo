/* -*- Mode: js2; indent-tabs-mode: nil; c-basic-offset: 4 -*- */

SOGoMailDataSource = Class.create({
        
        initialize: function(dataTable, url) {
            // Instance variables
            this.dataTable = dataTable;
            this.url = url;
            
            this.uids = new Array();
            this.cache = new Hash();
            
            this.loaded = false;
            this.delayedGetData = false;
            this.ajaxGetData = false;

            // Constants
            this.overflow = 50;   // must be higher or equal to the overflow of the data table class
        },
        
        destroy: function() {
            this.uids.clear();
            var keys = this.cache.keys();
            for (var i = 0; i < keys.length; i++)
                this.cache.unset(keys[i]);
        },

        invalidate: function(uid) {
            this.cache.unset(uid);
            var index = this.uids.indexOf(parseInt(uid));
//            log ("MailDataSource.invalidate(" + uid + ") at index " + index);

            return index;
        },

        remove: function(uid) {
            var index = this.invalidate(uid);
            if (index >= 0) {
                this.uids.splice(index, 1);
            }

            return index;
        },
        
        init: function(uids, headers) {
            this.uids = uids;
            
            var keys = headers[0];
            for (var i = 1; i < headers.length; i++) {
                var header = [];
                for (var j = 0; j < keys.length; j++)
                    header[keys[j]] = headers[i][j];
                this.cache.set(header["uid"], header);
            }

            this.loaded = true;
//            log ("MailDataSource.init() " + this.uids.length + " UIDs, " + this.cache.keys().length + " headers");
        },
        
        load: function(urlParams) {
            var params;
            this.loaded = false;
            if (urlParams.keys().length > 0) {
                params = urlParams.keys().collect(function(key) { return key + "=" + urlParams.get(key); }).join("&");
            }
            else
                params = "";

//            log ("MailDataSource.load() " + params);
            triggerAjaxRequest(this.url + "/uids",
                               this._loadCallback.bind(this),
                               null,
                               params,
                               { "Content-type": "application/x-www-form-urlencoded" });
        },
    
        _loadCallback: function(http) {
            if (http.status == 200) {
                if (http.responseText.length > 0) {
                    var data = http.responseText.evalJSON(true);
                    this.init(data.uids, data.headers);
                    this.loaded = true;
                    if (this.delayedGetData) {
                        this.delayedGetData();
                        this.delayedGetData = false;
                    }
                }
            }
            else {
                log("SOGoMailDataSource._loadCallback Error " + http.status + ": " + http.responseText);
            }
        },
        
        getData: function(id, index, count, callbackFunction, delay) {
            if (this.loaded == false) {
                // UIDs are not yet loaded -- delay the call until loading the data is completed.
//                 log ("MailDataSource.getData() delaying data fetching while waiting for UIDs");
                this.delayedGetData = this.getData.bind(this, id, index, count, callbackFunction, delay);
                return;
            }
            if (this.delayed_getData) window.clearTimeout(this.delayed_getData);
            this.delayed_getData = this._getData.bind(this,
                                                      id,
                                                      index,
                                                      count,
                                                      callbackFunction
                                                      ).delay(delay);
        },
        
        _getData: function(id, index, count, callbackFunction) {
            var start, end;
            var i, j;
            var missingUids = new Array();
            
            if (count > 1) {
                // Compute last index depending on number of UIDs
                start = index - (this.overflow/2);
                if (start < 0) start = 0;
                end = index + count + this.overflow - (index - start);
                if (end > this.uids.length) {
                    start -= end - this.uids.length;
                    end = this.uids.length;
                    if (start < 0) start = 0;
                }
            }
            else {
                // Count is 1; don't fetch more data since the caller is
                // SOGoDataTable.invalide() and asks for only one data row.
                start = index;
                end = index + count;
            }
//            log ("MailDataSource._getData() from " + index + " to " + (index + count) + " boosted from " + start + " to " + end);

            for (i = 0, j = start; j < end; j++) {
                if (!this.cache.get(this.uids[j])) {
                     missingUids[i] = this.uids[j];
                    i++;
                }
            }

            if (this.delayed_getRemoteData) window.clearTimeout(this.delayed_getRemoteData);
            if (missingUids.length > 0) {
                var params = "uids=" + missingUids.join(",");
                this.delayed_getRemoteData = this._getRemoteData.bind(this,
                                                                      { callbackFunction: callbackFunction,
                                                                        start: start, end: end,
                                                                        id: id },
                                                                      params).delay(0.5);
            }
            else if (callbackFunction)
                this._returnData(callbackFunction, id, start, end);
        },
        
        _getRemoteData: function(callbackData, urlParams) {
            if (this.ajaxGetData) {
                this.ajaxGetData.aborted = true;
                this.ajaxGetData.abort();
//                 log ("MailDataSource._getData() aborted previous AJAX request");
            }
//            log ("MailDataSource._getData() fetching headers of " + urlParams);
            this.ajaxGetData = triggerAjaxRequest(this.url + "/headers",
                                                  this._getRemoteDataCallback.bind(this),
                                                  callbackData,
                                                  urlParams,
                                                  { "Content-type": "application/x-www-form-urlencoded" });
        },
    
        _getRemoteDataCallback: function(http) {
            if (http.status == 200) {
                if (http.responseText.length > 0) {
                    // We receives an array of hashes
                    var headers = $A(http.responseText.evalJSON(true));
                    var data = http.callbackData;
                    var keys = headers[0];
                    for (var i = 1; i < headers.length; i++) {
                        var header = [];
                        for (var j = 0; j < keys.length; j++)
                            header[keys[j]] = headers[i][j];
                        this.cache.set(header["uid"], header);
                    }
                    
                    if (data["callbackFunction"])
                        this._returnData(data["callbackFunction"], data["id"], data["start"], data["end"]);
                }
            }
            else {
                log("SOGoMailDataSource._getRemoteDataCallback Error " + http.status + ": " + http.responseText);
            }
        },
        
        _returnData: function(callbackFunction, id, start, end) {
            var i, j;
            var data = new Array();
            for (i = start, j = 0; i < end; i++, j++) {
                data[j] = this.cache.get(this.uids[i]);
            }
            callbackFunction(id, start, this.uids.length, data);
        },

        indexOf: function(uid) {
            return this.uids.indexOf(parseInt(uid));
        }
});
