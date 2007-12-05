/*
 Copyright (C) 2005 SKYRIX Software AG
 
 This file is part of OpenGroupware.org.
 
 OGo is free software; you can redistribute it and/or modify it under
 the terms of the GNU Lesser General Public License as published by the
 Free Software Foundation; either version 2, or (at your option) any
 later version.
 
 OGo is distributed in the hope that it will be useful, but WITHOUT ANY
 WARRANTY; without even the implied warranty of MERCHANTABILITY or
 FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
 License for more details.
 
 You should have received a copy of the GNU Lesser General Public
 License along with OGo; see the file COPYING.  If not, write to the
 Free Software Foundation, 59 Temple Place - Suite 330, Boston, MA
 02111-1307, USA.
*/

/* Dependencies:
 * It's required that "currentIndex" is defined in a top level context.
 *
 * Exports:
 * defines hasRecipients() returning a bool for the
 * surrounding context to check.
 */

var lastIndex = currentIndex;

function sanitizedCn(cn) {
  var parts;
  parts = cn.split(', ');
  if(parts.length == 1)
    return cn;
  return parts[0];
}

function hasAddress(email) {
  var e = $(email);
  if(e)
    return true;
  return false;
}

function rememberAddress(email) {
  var list, span, idx;
  
  list    = $('addr_addresses');
  span    = document.createElement('span');
  span.id = email;
  idx     = document.createTextNode(currentIndex);
  span.appendChild(idx);
  list.appendChild(span);
}

function checkAddresses() {
  alert("addressCount: " + this.getAddressCount() + " currentIndex: " + currentIndex + " lastIndex: " + lastIndex);
}

function addAddress(type, email, uid, sn, cn, dn) {
  var shouldAddRow, s, e;
  
  shouldAddRow = true;
  if (cn)
    s = this.sanitizedCn(cn) + ' <' + email + '>';
  else
    s = email;

  if(this.hasAddress(email))
    return;
  
  e = $('addr_0');
  if(e.value == '') {
    e.value = s;
    shouldAddRow = false;
  }
  if(shouldAddRow) {
    this.fancyAddRow(false, s);
  }
  this.rememberAddress(email);
}

function fancyAddRow(shouldEdit, text) {
  var addr, addressList, lastChild, proto, row, select, input;
  
  addr = $('addr_' + lastIndex);
  if (addr && addr.value == '') {
    input = $('subjectField');
    if (input && input.value != '') {
      input.focus();
      input.select();
      return;
    }
  }
  addressList = $("addressList").tBodies[0];
  lastChild = $("lastRow");
  
  currentIndex++;
  proto = lastChild.previous("tr");
  row = proto.cloneNode(true);
  row.setAttribute("id", 'row_' + currentIndex);

  // select popup
  var rowNodes = row.childNodesWithTag("td");
  select = $(rowNodes[0]).childNodesWithTag("select")[0];
  select.name = 'popup_' + currentIndex;
  select.value = proto.down("select").value;
  input = $(rowNodes[1]).childNodesWithTag("input")[0];
  input.name  = 'addr_' + currentIndex;
  input.id = 'addr_' + currentIndex;
  input.value = text;

  addressList.insertBefore(row, lastChild);

  if (shouldEdit) {
    input.setAttribute('autocomplete', 'off');
    input.focus();
    input.select();
    input.setAttribute('autocomplete', 'on');
  }
}

function addressFieldGotFocus(sender) {
  var idx;
  
  idx = this.getIndexFromIdentifier(sender.id);
  if (lastIndex == idx) return;
  this.removeLastEditedRowIfEmpty();
  onWindowResize(null);

  return false;
}

function addressFieldLostFocus(sender) {
  lastIndex = this.getIndexFromIdentifier(sender.id);
  
  return false;
}

function removeLastEditedRowIfEmpty() {
  var addr, addressList, senderRow;
  
  addressList = $("addressList").tBodies[0];
  
  if (lastIndex == 0 && addressList.childNodes.length <= 2) return;
  addr = $('addr_' + lastIndex);
  if (!addr) return;
  if (addr.value.strip() != '') return;
  addr = this.findAddressWithIndex(lastIndex);
  if(addr) {
    var addresses = $('addr_addresses');
    addresses.removeChild(addr);
  }
  senderRow = $("row_" + lastIndex);
  addressList.removeChild(senderRow);
}

function findAddressWithIndex(idx) {
  var list, i, count, addr, idx
  list = $('addr_addresses').childNodes;
  count = list.length;
  for(i = 0; i < count; i++) {
    addr = list[i];
    if(addr.innerHTML == idx)
      return addr;
  }
  return null;
}

function getIndexFromIdentifier(id) {
  return id.split('_')[1];
}

function getAddressIDs() {
  var addressList, rows, i, count, addressIDs;

  addressIDs = new Array();

  addressList = $("addressList").tBodies[0];
  rows  = addressList.childNodes;
  count = rows.length;

  for (i = 0; i < count; i++) {
    var row, rowId;
    
    row = rows[i];
    rowId = row.id;
    if (rowId && rowId != 'lastRow') {
      var idx;

      idx = this.getIndexFromIdentifier(rowId);
      addressIDs.push(idx);
    }
  }
  return addressIDs;
}

function getAddressCount() {
  var addressCount, addressIDs, i, count;
  
  addressCount = 0;
  addressIDs   = this.getAddressIDs();
  count        = addressIDs.length;
  for (i = 0; i < count; i++) {
    var idx, input;

    idx   = addressIDs[i];
    input = $('addr_' + idx);
    if (input && input.value != '')
      addressCount++;
  }
  return addressCount;
}

function hasRecipients() {
  var count;
  
  count = this.getAddressCount();

  return (count > 0)
}

function initMailToSelection() {
  currentIndex = lastIndex = $$("table#addressList tr").length - 2;
}

FastInit.addOnLoad(initMailToSelection);
