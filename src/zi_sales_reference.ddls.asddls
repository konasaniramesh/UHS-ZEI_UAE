@AbapCatalog.viewEnhancementCategory: [#NONE]
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Sales Order Reference'
@Metadata.ignorePropagatedAnnotations: true
define view entity ZI_SALES_REFERENCE
  as select from    vbrp            as a
    left outer join vbrk            as b on b.vbeln = a.vbeln
    left outer join vbak            as c on c.vbeln = a.aubel
    left outer join zeinv_cn_rsn_sd as d on d.cn_reason = c.augru
{
  key b.bukrs     as CompanyCode,
  key a.vbeln     as SAPDocument,
  key b.gjahr     as FiscalYear,
      c.vbeln     as SalesDocument,
      c.bstnk     as CustomerReference,
      c.bstdk     as CustomerReferenceDate,
      c.augru     as OrderReason,
      d.ei_reason as EInvoiceCreditNoteReason
}

group by
  b.bukrs,
  a.vbeln,
  b.gjahr,
  c.vbeln,
  c.bstnk,
  c.bstdk,
  c.augru,
  d.ei_reason
