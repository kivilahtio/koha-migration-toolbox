SELECT 
  jykdb.line_item.bib_id,
  jykdb.invoice.vendor_id
FROM
  jykdb.line_item
INNER JOIN
  jykdb.line_item_copy 
ON jykdb.line_item_copy.line_item_id = jykdb.line_item.line_item_id
INNER JOIN
  jykdb.line_item_copy_status
ON jykdb.line_item_copy_status.line_item_id = jykdb.line_item_copy.line_item_id
INNER JOIN
  jykdb.invoice_line_item
ON jykdb.invoice_line_item.inv_line_item_id = jykdb.line_item_copy_status.line_item_id
INNER JOIN
  jykdb.invoice
ON jykdb.invoice.invoice_id = jykdb.invoice_line_item.invoice_id
