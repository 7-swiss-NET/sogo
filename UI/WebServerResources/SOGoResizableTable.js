/* -*- Mode: java; indent-tabs-mode: nil; c-basic-offset: 4 -*- */

/*
 * Resizable table interface to be added to a TABLE (this!)
 *
 * Columns with the class resizable will be .. resizable.
 *
 */
var SOGoResizableTableInterface = {

    delayedResize: null,

    bind: function() {
        var i;
	var cells = $(this).down('tr').childElements();
	for (i = 0; i < cells.length; i++) {
            var cell = cells[i];
            if (Prototype.Browser.IE)
                cell.observe("selectstart", Event.stop);
            if (cell.hasClassName('resizable')) {
                Event.observe(cell, 'mouseover', SOGoResizableTable.initDetect);
                Event.observe(cell, 'mouseout', SOGoResizableTable.killDetect);
            }
            SOGoResizableTable._resize(this, $(cell), i, null, cell.getWidth());
        }
        Event.observe(window, "resize", this.restore.bind(this));
    },

    restore: function(e) {
        // Only resize the columns after a certain delay, otherwise it slow
        // down the interface.
        if (this.delayedResize) window.clearTimeout(this.delayedResize);
        this.delayedResize = this._restore.bind(this).delay(0.2);
    },

    _restore: function() {
        if (Prototype.Browser.IE)
            while (SOGoResizableTable._stylesheet.styleSheet.rules.length)
                SOGoResizableTable._stylesheet.styleSheet.removeRule();
        else
            while (SOGoResizableTable._stylesheet.firstChild)
                SOGoResizableTable._stylesheet.removeChild(SOGoResizableTable._stylesheet.firstChild);
        
        // TODO : widths ratios should be computed and columns restored accordingly.
        var cells = $(this).down('tr').childElements();
	for (i = 0; i < cells.length; i++) {
            var cell = cells[i];
            SOGoResizableTable._resize(this, $(cell), i, null, cell.getWidth());
        }
    }
};

SOGoResizableTable = {

    _onHandle: false,
    _cell: null,
    _tbl: null,
    _handle: null,
    _stylesheet: null,

    resize: function(table, index, w) {
        var cell;
        if (typeof index === 'number') {
            if (!table || (table.tagName && table.tagName !== "TABLE")) { return; }
            table = $(table);
            index = Math.min(table.rows[0].cells.length, index);
            index = Math.max(1, index);
            index -= 1;
            cell = $(table.rows[0].cells[index]);
        }
        else {
            cell = $(index);
            table = table ? $(table) : cell.up('table');
            index = SOGoResizableTable.getCellIndex(cell);
        }
        
        var cells =  table.down('tr').childElements();
        var nextResizableCell = null;
        for (var i = index + 1; i < cells.length; i++) {
            var c = cells[i];
            if (c.hasClassName('resizable')) {
                nextResizableCell = c;
                break;
            }
        }
        
        var delta = SOGoResizableTable._resize(table, cell, index, nextResizableCell, w, false);
        if (delta != 0 && nextResizableCell != null) {
            var w = nextResizableCell.getWidth() - delta;
            SOGoResizableTable._resize(table, nextResizableCell, i, null, w, true);
        }
    },

    _resize: function(table, cell, index, nextResizableCell, w, isAdjustment) {
        var pad = 0;
        if (!Prototype.Browser.WebKit) {
            pad = parseInt(cell.getStyle('paddingLeft'),10) + parseInt(cell.getStyle('paddingRight'),10);
            pad += parseInt(cell.getStyle('borderLeftWidth'),10) + parseInt(cell.getStyle('borderRightWidth'),10);
        }
        
        var cells = table.down('tr').childElements();
        if ((index + 1) == cells.length) {
            return 0;
        }
        
        if (!isAdjustment && cell.getWidth() < w) {
             if (nextResizableCell == null && (index + 2) == cells.length)
                 // The next cell is the last cell; respect its minimum width
                 // event if it's not resizable.
                 nextResizableCell = cells[index + 1];
             if (nextResizableCell != null) {
                 // Respect the minimum width of the next resizable cell.
                 var max = cells[index].getWidth()
                 + nextResizableCell.getWidth()
                 - parseInt(nextResizableCell.getStyle('minWidth'))
                 - pad;
                 w = Math.min(max, w);
             }
         }
        
        // Respect the minimum width of the cell.
        w = Math.max(w - pad, parseInt(cell.getStyle('minWidth')));

        var delta = w - cell.getWidth() + pad;

        var cssSelector = ' TABLE.' + $w(table.className).first() + ' .' + $w(cell.className).first();

        if (SOGoResizableTable._stylesheet == null) {
            SOGoResizableTable._stylesheet = document.createElement("style");
            SOGoResizableTable._stylesheet.type = "text/css";
            document.getElementsByTagName("head")[0].appendChild(SOGoResizableTable._stylesheet);
        }

        if (SOGoResizableTable._stylesheet.styleSheet && SOGoResizableTable._stylesheet.styleSheet.addRule) {
            // IE
            SOGoResizableTable._stylesheet.styleSheet.addRule(cssSelector,
                                                              ' { width: ' + w + 'px; max-width: ' + w + 'px; }');
        }
        else {
            // Mozilla + Safari
            SOGoResizableTable._stylesheet.appendChild(document.createTextNode(cssSelector +
                                                                               ' { width: ' + w + 'px; max-width: ' + w + 'px; }'));
        }
        
        return delta;
    },
    
    initDetect: function(e) {
        var cell = Event.element(e);
        if (cell.tagName != "TH") { return; }
        Event.observe(cell, 'mousemove', SOGoResizableTable.detectHandle);
        Event.observe(cell, 'mousedown', SOGoResizableTable.startResize);
    },
    
    detectHandle: function(e) {
        var cell = Event.element(e);
        if (SOGoResizableTable.pointerPos(cell, Event.pointerX(e), Event.pointerY(e))) {
            cell.addClassName('resize-handle-active');
            SOGoResizableTable._onHandle = true;
        }
        else {
            cell.removeClassName('resize-handle-active');
            SOGoResizableTable._onHandle = false;
        }
    },
    
    killDetect: function(e) {
        SOGoResizableTable._onHandle = false;
        var cell = Event.element(e);
        Event.stopObserving(cell, 'mousemove', SOGoResizableTable.detectHandle);
        Event.stopObserving(cell, 'mousedown', SOGoResizableTable.startResize);
        cell.removeClassName('resize-handle-active');
    },
    
    startResize: function(e) {
        if (!SOGoResizableTable._onHandle) { return; }
        var cell = Event.element(e);
        Event.stopObserving(cell, 'mousemove', SOGoResizableTable.detectHandle);
        Event.stopObserving(cell, 'mousedown', SOGoResizableTable.startResize);
        Event.stopObserving(cell, 'mouseout', SOGoResizableTable.killDetect);
        SOGoResizableTable._cell = cell;
        var table = cell.up('table');
        SOGoResizableTable._tbl = table;
        SOGoResizableTable._handle = $(document.createElement('div')).addClassName('resize-handle').setStyle({
                'top' : table.cumulativeOffset()[1] + 'px',
                'left' : Event.pointerX(e) + 'px',
                'height' : table.getHeight() + 'px',
                'max-height' : table.getHeight() + 'px'
            });
        document.body.appendChild(SOGoResizableTable._handle);
        
        Event.observe(document, 'mousemove', SOGoResizableTable.drag);
        Event.observe(document, 'mouseup', SOGoResizableTable.endResize);
        Event.stop(e);
    },

    endResize: function(e) {
        var cell = SOGoResizableTable._cell;
        if (!cell) { return; }
        SOGoResizableTable.resize(null, cell, (Event.pointerX(e) - cell.cumulativeOffset()[0]));
        Event.stopObserving(document, 'mousemove', SOGoResizableTable.drag);
        Event.stopObserving(document, 'mouseup', SOGoResizableTable.endResize);
        $$('div.resize-handle').each(function(elm){
                document.body.removeChild(elm);
            });
        Event.observe(cell, 'mouseout', SOGoResizableTable.killDetect);
        SOGoResizableTable._tbl = SOGoResizableTable._handle = SOGoResizableTable._cell = null;
        Event.stop(e);
    },

    drag: function(e) {
        e = $(e);
        if (SOGoResizableTable._handle === null) {
            try {
                SOGoResizableTable.resize(SOGoResizableTable._tbl, SOGoResizableTable._cell, (Event.pointerX(e) - SOGoResizableTable._cell.cumulativeOffset()[0]));
            }
            catch(e) {}
        }
        else {
            SOGoResizableTable._handle.setStyle({'left' : Event.pointerX(e) + 'px'});
        }
        return false;
    },
    
    pointerPos: function(element, x, y) {
    	var offset = $(element).cumulativeOffset();
        return (y >= offset[1] &&
                y <  offset[1] + element.offsetHeight &&
                x >= offset[0] + element.offsetWidth - 5 &&
                x <  offset[0] + element.offsetWidth);
    },

    getCellIndex : function(cell) {
        return $A(cell.parentNode.cells).indexOf(cell);
    }
    
};