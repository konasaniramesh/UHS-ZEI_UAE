@AbapCatalog.viewEnhancementCategory: [#NONE]
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'E-Invoice Items'
@Metadata.ignorePropagatedAnnotations: true
@ObjectModel.usageType:{
    serviceQuality: #X,
    sizeCategory: #S,
    dataClass: #MIXED
}
define view entity ZI_EINVOICE_ITEMS
  as select from    vbrp           as a
    left outer join vbrk           as b on b.vbeln = a.vbeln
    left outer join makt           as c on  c.matnr = a.matnr
                                        and c.spras = $session.system_language
    left outer join marc           as d on  d.matnr = a.matnr
                                        and d.werks = a.werks
    left outer join zeinv_unitcode as e on e.meins = a.vrkme

{
  key b.bukrs           as CompanyCode,
  key a.vbeln           as SAPDocument,
  key b.gjahr           as FiscalYear,
  key a.posnr           as SAPDocItem,
      a.matnr           as Material,
      c.maktx           as MaterialDescription,
      @Semantics.quantity.unitOfMeasure: 'SalesUnit'
      a.fkimg           as Quantity,
      a.vrkme           as SalesUnit,
      e.eiunit          as EInvoiceUnit,
      b.waerk           as Currency,
      @Semantics.amount.currencyCode: 'Currency'
      a.netwr           as NetValue,
      @Semantics.amount.currencyCode: 'Currency'
      a.mwsbp           as TaxValue,
      @Semantics.amount.currencyCode: 'Currency'
      cast( cast( a.netwr as abap.dec(15,2) ) + cast( a.mwsbp as abap.dec(13,2) ) as abap.curr(15,2) ) as TotalValue,
      a.aubel           as SalesOrder,
      a.aupos           as SalesOrderItem,
      d.herkl           as OriginCountry
}
