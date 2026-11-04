@AbapCatalog.viewEnhancementCategory: [#NONE]
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'E-Invoice Conditions'
@Metadata.ignorePropagatedAnnotations: true
@ObjectModel.usageType:{
    serviceQuality: #X,
    sizeCategory: #S,
    dataClass: #MIXED
}
define view entity ZI_EINVOICE_CONDITIONS
  as select from    prcd_elements   as a
    left outer join zeinv_allowance as b on a.kschl = b.kschl
    left outer join zeinv_unitcode  as c on c.meins = a.kmein
    left outer join zeinv_taxtype   as d on d.mwskz = a.mwsk1
{
  key a.knumv                 as ConditionNo,
  key a.kposn                 as Item,
  key a.kschl                 as ConditionType,
      a.krech                 as CalculationType,
      a.kawrt                 as BaseAmount,
      a.kbetr                 as Amount,
      a.kpein                 as PricingUnit,
      a.kmein                 as ConditionUnit,
      @Semantics.amount.currencyCode: 'Currency'
      a.kwert                 as Value,
      a.waerk                 as Currency,
      a.kvsl1                 as AccountKey,
      a.koaid                 as ConditionClass,
      a.mwsk1                 as TaxCode,
      b.allowance_type        as AllowanceType,
      b.allowance_code        as AllowanceCode,
      b.allowance_name        as AllowanceName,
      c.eiunit                as EInvoiceUnit,
      d.tax_rate              as TaxRate,
      d.eitaxtype             as EInvoiceTaxType,
      d.reverse_charge        as ReverseCharge,
      d.exemption_reason_code as ExemptionReasonCode

}
where
  a.kinak = ' '
