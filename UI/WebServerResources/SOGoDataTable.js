/* -*- Mode: java; indent-tabs-mode: nil; c-basic-offset: 4 -*- */

/*
 * Data table interface to be added to a DIV (this!)
 *
 * Available events:
 *   datatable:rendered -- fired once the view rendering is completed
 *
 */
var SOGoDataTableInterface = {
  
    // Object variables initialized with "bind"
    columnsCount: null,
    rowModel: null,
    rowHeight: 0,
    body: null,
 
    // Object variables
    dataSource: null,
    rowTop: null,
    rowBottom: null,
    renderedIndex: -1,
    renderedCount: 0,
    rowRenderCallback: null,
    
    // Constants
    overflow: 30,         // must be lower than the overflow of the data source class
    renderDelay: 0.2,     // delay (in seconds) before which the table is rendered upon scrolling
    
    bind: function() {
        this.observe("scroll" , this.render.bind(this));
        
        this.body = this.down("tbody");
        this.rowModel = this.body.down("tr");

        // Since we use the fixed table layout, the first row must have the
        // proper CSS classes that will define the columns width.
        this.rowTop = new Element('tr', {'id': 'rowTop'});//.update(new Element('td'));
        this.body.insertBefore(this.rowTop, this.rowModel); // IE requires the element to be inside the DOM before appending new children
        var cells = this.rowModel.select('TD');
        for (var i = 0; i < cells.length; i++) {
            var cell = cells[i];
            var td = new Element('td', {'class': cell.className});
            this.rowTop.appendChild(td);
        }

        this.rowBottom = new Element('tr', {'id': 'rowBottom'}).update(new Element('td'));
        this.body.insertBefore(this.rowBottom, this.rowModel);
 
        this.columnsCount = this.rowModel.select("td").length;
        this.rowHeight = this.rowModel.getHeight();
    },
    
    setRowRenderCallback: function(callbackFunction) {
        // Each time a row is created or updated with new data, this callback
        // function will be called.
        this.rowRenderCallback = callbackFunction;
    },

    setSource: function(dataSourceClass, url, params) {
//         log ("DataTable.setSource() " + url);
        if (this.dataSource) this.dataSource.destroy();
        this._emptyTable();
        this.dataSource = new window[dataSourceClass](this, url);
        this.scrollTop = 0;
        this.load(params);
    },

    load: function(urlParams) {
        if (!this.dataSource) return;
//         log ("DataTable.load() with parameters [" + urlParams.keys().join(' ') + "]");
        if (Object.isHash(urlParams) && urlParams.keys().length > 0) this.dataSource.load(urlParams);
        else this.dataSource.load(new Hash());
    },
    
    visibleRowCount: function() {
        var divHeight = this.getHeight();
        var visibleRowCount = Math.ceil(divHeight/this.rowHeight);

        return visibleRowCount;
    },
 
    firstVisibleRowIndex: function() {
        var firstRowIndex = Math.floor(this.scrollTop/this.rowHeight);
        
        return firstRowIndex;
    },
    
    render: function(uid) {
        var index = this.firstVisibleRowIndex();
        var count = this.visibleRowCount();

        // Overflow the query to the maximum defined in the class variable overflow
        var start = index - (this.overflow/2);
        if (start < 0) start = 0;
        var end = index + count + this.overflow - (index - start);
//             log ("DataTable.getData() from " + index + " to " + (index + count) + " boosted from " + start + " to " + end);

        // Don't overflow above the maximum number of entries from the data source
        if (this.dataSource.uids && this.dataSource.uids.length < end) end = this.dataSource.uids.length;

        index = start;
        count = end - start;

        this.currentRenderID = index + "-" + count;
        // Query the data source only if at least one row is not loaded
        if (this.renderedIndex < 0 || 
            this.renderedIndex > index ||
            this.renderedCount < count ||
            (index + count) > (this.renderedIndex + this.renderedCount)) {
            this.dataSource.getData(this.currentRenderID,
                                    index,
                                    count,
                                    this._render.bind(this),
                                    this.renderDelay);
        }
    },

    _render: function(renderID, start, max, data) {
        if (this.currentRenderID != renderID) {
//             log ("DataTable._render() ignore render for " + renderID + " (current is " + this.currentRenderID + ")");
            return;
        }
//         log("DataTable._render() for " + data.length + " uids (from " + start + ")");

        var h, i, j;
        var rows = this.body.select("tr");
        var scroll;

        scroll = this.scrollTop;
        lastClickedRow = -1; // defined in generic.js

        h = start * this.rowHeight;
        if (Prototype.Browser.IE)
            this.rowTop.setStyle({ 'height': h + 'px', 'line-height': h + 'px' });
        this.rowTop.firstChild.setStyle({ 'height': h + 'px', 'line-height': h + 'px' });

        h = (max - start - data.length) * this.rowHeight;
        if (Prototype.Browser.IE)
            this.rowBottom.setStyle({ 'height': h + 'px', 'line-height': h + 'px' });
        this.rowBottom.firstChild.setStyle({ 'height': h + 'px', 'line-height': h + 'px' });
        
        if (this.renderedIndex < 0) {
            this.renderedIndex = 0;
            this.renderedCount = 0;
        }

        if (start > (this.renderedIndex + this.renderedCount) ||
            start + data.length < this.renderedIndex) {
            // No reusable row in the viewport;
            // refresh the complete view port

            for (i = 0, j = start;
                 i < this.renderedCount && i < data.length;
                 i++, j++) {
                // Render all existing rows with new data
                var row = rows[i+1]; // must skip the first row (this.rowTop)
                row.removeClassName('_selected');
                this.rowRenderCallback(row, data[i], false);
            }

            for (i = this.renderedCount;
                 i < data.length;
                 i++, j++) {
                // Add new rows, if necessary
                var row = this.rowModel.cloneNode(true);
                this.rowRenderCallback(row, data[i], true);
                row.show();
                this.body.insertBefore(row, this.rowBottom);
            }

            for (i = this.renderedCount;
                 i > data.length;
                 i--) {
                // Delete extra rows, if necessary
                this.body.removeChild(rows[i]);
            }
        }
        else if (start >= this.renderedIndex) {
            // Scrolling down

            // Delete top rows
            for (i = start; i > this.renderedIndex; i--) {
                this.body.removeChild(rows[i - this.renderedIndex]);
            }
            
            // Add bottom rows
            for (j = this.renderedIndex + this.renderedCount - start, i = this.renderedIndex + this.renderedCount;
                 j < data.length;
                 j++, i++) {
                var row = this.rowModel.cloneNode(true);
                this.rowRenderCallback(row, data[j], true);
                row.show();
                this.body.insertBefore(row, this.rowBottom);
            }
        }
        else {
            // Scrolling up

            // Delete bottom rows
            for (i = this.renderedIndex + this.renderedCount, j = this.renderedCount;
                 i > (start + data.length);
                 i--, j--) {
                this.body.removeChild(rows[j]);
            }

            // Add top rows
            for (i = 0, j = start;
                 j < this.renderedIndex;
                 i++, j++) {
                var row = this.rowModel.cloneNode(true);
                this.rowRenderCallback(row, data[i], true);
                row.show();
                this.body.insertBefore(row, rows[1]);
            }
        }

        this.body.refreshSelectionByIds();
//         log ("DataTable._render() top gap/bottom gap/total rows = " + this.rowTop.getStyle('height') + "/" + this.rowBottom.getStyle('height') + "/" + this.body.select("tr").length + " (height = " + this.down("table").getHeight() + "px)");
        
        // Save current rendered view index and count
        this.renderedIndex = start;
        this.renderedCount = data.length;

        // Restore scroll position (necessary in certain cases)
        this.scrollTop = scroll;

        Event.fire(this, "datatable:rendered", max);
    },

    remove: function(uid) {
        var rows = this.body.select("TR#row_" + uid);
        if (rows.length == 1) {
            var row = rows.first();
            row.parentNode.removeChild(row);
            var index = this.dataSource.invalidate(uid);
//             log ("DataTable.remove(" + uid + ")");
            if (this.renderedIndex < index &&
                (this.renderedIndex + this.renderedCount) > index) {
                this.renderedCount--;
            }
        }
    },
 
    _emptyTable: function() {
        var rows = this.body.select("tr");
        var currentCount = rows.length;
        
        for (var i = currentCount - 1; i >= 0; i--) {
            if (rows[i] != this.rowModel &&
                rows[i] != this.rowTop &&
                rows[i] != this.rowBottom)
                this.body.removeChild(rows[i]);
        }
        
        this.renderedIndex = -1;
        this.renderedCount = 0;
        this.rowTop.firstChild.setStyle({ 'height': '0px', 'line-height': '0px' });
        this.rowBottom.firstChild.setStyle({ 'height': '0px', 'line-height': '0px' });
    }
};
