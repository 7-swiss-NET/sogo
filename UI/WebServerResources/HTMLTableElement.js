Element.addMethods({
  getSelectedRows: function(element) {
    element = $(element);
    if (element.tagName == 'TABLE') {
      var tbody = (element.getElementsByTagName('tbody'))[0];
      
      return tbody.getSelectedNodes();
    }
    else if (element.tagName == 'UL') {
      return element.getSelectedNodes();
    }
  },

  getSelectedRowsId: function(element) {
    element = $(element);
    if (element.tagName == 'TABLE') {
      var tbody = (element.getElementsByTagName('tbody'))[0];
      
      return tbody.getSelectedNodesId();
    }
    else if (element.tagName == 'UL') {
      return element.getSelectedNodesId();
    }
  },

  selectRowsMatchingClass: function(element, className) {
    element = $(element);
    if (element.tagName == 'TABLE') {
      var tbody = (element.getElementsByTagName('tbody'))[0];
      var nodes = tbody.childNodes;
      for (var i = 0; i < nodes.length; i++) {
	var node = nodes.item(i);
	if (node instanceof HTMLElement
	    && node.hasClassName(className))
	  node.select();
      }
    }
  }
}); // Element.addMethods
