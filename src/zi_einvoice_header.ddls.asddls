@AbapCatalog.viewEnhancementCategory: [#NONE]
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'E-Invoice Header Information'
@Metadata.ignorePropagatedAnnotations: true
@ObjectModel.usageType:{
    serviceQuality: #X,
    sizeCategory: #S,
    dataClass: #MIXED
}
@Analytics.dataCategory: #CUBE
define view entity ZI_EINVOICE_HEADER
  as select from    vbrk               as a
    left outer join zeinvoice_detail   as a1  on  a1.bukrs = a.bukrs
                                              and a1.vbeln = a.vbeln
                                              and a1.gjahr = a.gjahr
    left outer join tvzbt              as a2  on  a2.zterm = a.zterm
                                              and a2.spras = $session.system_language
    inner join      zeinv_invtype_sd   as a3  on  a3.bukrs = a.bukrs
                                              and a3.fkart = a.fkart
    left outer join vbrk               as a4  on a4.vbeln = a.xblnr
    left outer join bseg               as a5  on  a5.bukrs = a.bukrs
                                              and a5.belnr = a.belnr
                                              and a5.gjahr = a.gjahr
                                              and a5.koart = 'D'
                                              and a5.vbeln = a.vbeln
    left outer join zeinv_pay_method   as a6  on a6.payment_method = a5.zlsch
    left outer join t012k              as a7  on  a7.bukrs = a5.bukrs
                                              and a7.hbkid = a5.hbkid
                                              and a7.hktid = a5.hktid
    left outer join t012               as a8  on  a8.bukrs = a5.bukrs
                                              and a8.hbkid = a5.hbkid
    left outer join bnka               as a9  on  a9.banks = a8.banks
                                              and a9.bankl = a8.bankl
    left outer join tiban              as a10 on  a10.banks = a8.banks
                                              and a10.bankl = a8.bankl
                                              and a10.bankn = a7.bankn
    left outer join ZI_SALES_REFERENCE as a11 on  a11.CompanyCode = a.bukrs
                                              and a11.SAPDocument = a.vbeln
                                              and a11.FiscalYear  = a.gjahr
  //Supplier Details
    left outer join t001               as b1  on b1.bukrs = a.bukrs
    left outer join adrc               as b2  on b2.addrnumber = b1.adrnr
    left outer join zeinv_company      as b3  on b3.bukrs = a.bukrs
    left outer join zeinv_pay_method   as b4  on b4.payment_method = b3.payment_method
    left outer join zeinv_state        as b5  on b5.state = b2.region
  //Buyer
    left outer join vbpa               as c1  on  c1.vbeln = a.vbeln
                                              and c1.parvw = 'AG'
    left outer join kna1               as c2  on c2.kunnr = c1.kunnr
    left outer join adrc               as c3  on c3.addrnumber = c2.adrnr
    left outer join dfkkbptaxnum       as c4  on  c4.partner = c1.kunnr
                                              and c4.taxtype = 'AE0'
    left outer join dfkkbptaxnum       as c5  on  c5.partner = c1.kunnr
                                              and c5.taxtype = 'AE1'
    left outer join but0id             as c6  on  c6.partner         = c1.kunnr
                                              and c6.type            = 'AELRID'
                                              and c6.valid_date_from <= $session.system_date
                                              and c6.valid_date_to   >= $session.system_date
    left outer join but0id             as c7  on  c7.partner         = c1.kunnr
                                              and c7.type            = 'PAP001'
                                              and c7.valid_date_from <= $session.system_date
                                              and c7.valid_date_to   >= $session.system_date
    left outer join knb1               as c8  on  c8.kunnr = c1.kunnr
                                              and c8.bukrs = a.bukrs
    left outer join zeinv_pay_method   as c9  on c9.payment_method = c8.zwels
    left outer join t012               as c10 on  c10.bukrs = c8.bukrs
                                              and c10.hbkid = c8.hbkid
    left outer join bnka               as c11 on  c11.banks = c10.banks
                                              and c11.bankl = c10.bankl
    left outer join knbk               as c12 on  c12.kunnr = c8.kunnr
                                              and c12.banks = c10.banks
                                              and c12.bankl = c10.bankl
                                              and c12.bvtyp = '0001'
    left outer join tiban              as c13 on  c13.banks = c10.banks
                                              and c13.bankl = c10.bankl
                                              and c13.bankn = c12.bankn
    left outer join zeinv_state        as c14 on c14.state = c3.region
  //Payee
    left outer join vbpa               as d1  on  d1.vbeln = a.vbeln
                                              and d1.parvw = 'RG'
    left outer join but020             as d2  on d2.partner = d1.kunnr
    left outer join adrc               as d3  on d3.addrnumber = d2.addrnumber
    left outer join dfkkbptaxnum       as d4  on  d4.partner = d1.kunnr
                                              and d4.taxtype = 'AE0'
    left outer join dfkkbptaxnum       as d5  on  d5.partner = d1.kunnr
                                              and d5.taxtype = 'AE1'
    left outer join but0id             as d6  on  d6.partner         = d1.kunnr
                                              and d6.type            = 'AELRID'
                                              and d6.valid_date_from <= $session.system_date
                                              and d6.valid_date_to   >= $session.system_date
    left outer join but0id             as d7  on  d7.partner         = d1.kunnr
                                              and d7.type            = 'PAP001'
                                              and d7.valid_date_from <= $session.system_date
                                              and d7.valid_date_to   >= $session.system_date
    left outer join zeinv_state        as d8  on d8.state = d3.region
  //Delivery
    left outer join vbpa               as e1  on  e1.vbeln = a.vbeln
                                              and e1.parvw = 'AG'
    left outer join kna1               as e2  on e2.kunnr = e1.kunnr
    left outer join adrc               as e3  on e3.addrnumber = e2.adrnr
    left outer join dfkkbptaxnum       as e4  on  e4.partner = e1.kunnr
                                              and e4.taxtype = 'AE0'
    left outer join dfkkbptaxnum       as e5  on  e5.partner = e1.kunnr
                                              and e5.taxtype = 'AE1'
    left outer join but0id             as e6  on  e6.partner         = e1.kunnr
                                              and e6.type            = 'AELRID'
                                              and e6.valid_date_from <= $session.system_date
                                              and e6.valid_date_to   >= $session.system_date
    left outer join but0id             as e7  on  e7.partner         = e1.kunnr
                                              and e7.type            = 'PAP001'
                                              and e7.valid_date_from <= $session.system_date
                                              and e7.valid_date_to   >= $session.system_date
    left outer join but000             as e8  on e8.partner = e1.kunnr
    left outer join zeinv_state        as e9  on e9.state = e3.region

{
  key a.bukrs                                    as CompanyCode,
  key a.vbeln                                    as SAPDocument,
  key a.gjahr                                    as FiscalYear,
  key 'SD'                                       as Type,
      'Sales'                                    as TypeName,
      a.erdat                                    as CreationDate,
      a.erzet                                    as CreationTime,
      a.fkdat                                    as BillingDate,
      a.fkart                                    as DocumentType,
      a3.eitype                                  as EInvoiceType,
      a3.automatic                               as AutoEInvoice,
      a.xblnr                                    as HeaderReference,
      a11.SalesDocument                          as SalesDocument,
      a11.CustomerReference                      as CustomerReference,
      a11.EInvoiceCreditNoteReason               as EInvoiceCreditNoteReason,
      a.waerk                                    as Currency,
      a.knumv                                    as ConditionNo,
      case when a1.msgty is not null or
                a1.msgty is not initial
           then a1.msgty
           else 'P'
      end                                        as MessageType,
      case when a1.msgty = 'S' then '@5B@'
           when a1.msgty = 'E' then '@5C@'
           when a1.msgty = 'W' then '@5D@'
           else '@BZ@'
      end                                        as Status,
      a1.dformat                                 as RequestFormat,
      a1.request_payload                         as RequestPayload,
      a1.referenceid                             as ReferenceID,
      case when a1.pstatus is null or
                a1.pstatus is initial
           then 'PENDING'
           else a1.pstatus
      end                                        as EInvoiceStatus,
      a1.response_payload                        as ResponsePayload,
      a2.vtext                                   as PaymentTerms,
      a4.vbeln                                   as OriginalDocument,
      a4.bukrs                                   as OriginalCompanyCode,
      a4.gjahr                                   as OriginalFiscalYear,
      a4.erdat                                   as OriginalCreationDate,
      a5.zlsch                                   as PaymentMethod,
      a6.eipayment_method                        as EInvoicePaymentMethod,
      a6.eipayment_method_name                   as EInvoicePaymentMethodName,
      a10.iban                                   as IBAN,
      a9.banka                                   as AccountName,
      a9.swift                                   as SWIFTCode,
      //Seller Address
      concat_with_space( b2.name1, b2.name2, 1 ) as SupplierName,
      b2.street                                  as SupplierStreetName,
      b2.str_suppl1                              as SupplierAdditionalStreetName,
      b2.city1                                   as SupplierCityName,
      b2.post_code1                              as SupplierPostalCode,
      b5.eistate                                 as SupplierRegion,
      b2.country                                 as SupplierCountry,
      b3.trn                                     as SupplierVATRegistrationCode,
      b3.tin                                     as SupplierTIN,
      b3.trade_license                           as SupplierLegalRegistrationID,
      b3.peppol_id                               as SupplierPeppolID,
      b3.asp_provider                            as SupplierASPProvider,
      b3.asp_id                                  as SupplierASPID,
      b4.eipayment_method                        as SupplierPaymentMethod,
      b4.eipayment_method_name                   as SupplierPaymentMethodName,
      b3.iban                                    as SupplierIBAN,
      b3.account_name                            as SupplierAccountName,
      b3.swift_code                              as SupplierSWIFTCode,
      //Customer Address
      c1.kunnr                                   as Customer,
      concat_with_space( c3.name1, c3.name2, 1 ) as CustomerName,
      c3.street                                  as CustomerStreetName,
      c3.str_suppl1                              as CustomerAdditionalStreetName,
      c3.city1                                   as CustomerCityName,
      c3.post_code1                              as CustomerPostalCode,
      c14.eistate                                as CustomerRegion,
      c3.country                                 as CustomerCountry,
      c4.taxnum                                  as CustomerVATRegistrationCode,
      c5.taxnum                                  as CustomerTIN,
      c6.idnumber                                as CustomerLegalRegistrationID,
      c7.idnumber                                as CustomerPeppolID,
      c8.zzeinvoice                              as EInvoiceEnabled,
      c8.zzbusinesstype                          as BusinessType,
      c8.zzzonetype                              as ZoneType,
      c9.eipayment_method                        as CustomerPaymentMethod,
      c9.eipayment_method_name                   as CustomerPaymentMethodName,
      c13.iban                                   as CustomerIBAN,
      c11.banka                                  as CustomerAccountName,
      c11.swift                                  as CustomerSWIFTCode,
      //Payee Address
      d1.kunnr                                   as Payee,
      concat_with_space( d3.name1, d3.name2, 1 ) as PayeeName,
      d3.street                                  as PayeeStreetName,
      d3.str_suppl1                              as PayeeAdditionalStreetName,
      d3.city1                                   as PayeeCityName,
      d3.post_code1                              as PayeePostalCode,
      d8.eistate                                 as PayeeRegion,
      d3.country                                 as PayeeCountry,
      d4.taxnum                                  as PayeeVATRegistrationCode,
      d5.taxnum                                  as PayeeTIN,
      d6.idnumber                                as PayeeLegalRegistrationID,
      d7.idnumber                                as PayeePeppolID,
      //Delivery/Ship-To Address
      e1.kunnr                                   as ShipTo,
      concat_with_space( e3.name1, e3.name2, 1 ) as ShipToName,
      e3.street                                  as ShipToStreetName,
      e3.str_suppl1                              as ShipToAdditionalStreetName,
      e3.city1                                   as ShipToCityName,
      e3.post_code1                              as ShipToPostalCode,
      e9.eistate                                 as ShipToRegion,
      e3.country                                 as ShipToCountry,
      e4.taxnum                                  as ShipToVATRegistrationCode,
      e5.taxnum                                  as ShipToTIN,
      e6.idnumber                                as ShipToLegalRegistrationID,
      e7.idnumber                                as ShipToPeppolID,

      //AmountDetails
      @Semantics.amount.currencyCode: 'Currency'
      a.netwr                                    as NetValue,
      @Semantics.amount.currencyCode: 'Currency'
      a.mwsbk                                    as TaxValue,
      @Semantics.amount.currencyCode: 'Currency'
      @Aggregation.default: #SUM
      cast( cast( a.netwr as abap.dec(15,2) ) + cast( a.mwsbk as abap.dec(13,2) ) as abap.curr(15,2) ) as TotalValue

}

//union all
//
//select from       bkpf             as a
//  left outer join zeinvoice_detail as a1  on  a1.bukrs = a.bukrs
//                                          and a1.vbeln = a.belnr
//                                          and a1.gjahr = a.gjahr
//  inner join      zeinv_invtype_fi as a3  on  a3.bukrs = a.bukrs
//                                          and a3.blart = a.blart
////    left outer join vbrk               as a4  on a4.vbeln = a.xblnr
//  left outer join bseg             as a5  on  a5.bukrs = a.bukrs
//                                          and a5.belnr = a.belnr
//                                          and a5.gjahr = a.gjahr
//                                          and a5.koart = 'D'
//  left outer join tvzbt            as a2  on  a2.zterm = a5.zterm
//                                          and a2.spras = $session.system_language
//  left outer join zeinv_pay_method as a6  on a6.payment_method = a5.zlsch
//  left outer join t012k            as a7  on  a7.bukrs = a5.bukrs
//                                          and a7.hbkid = a5.hbkid
//                                          and a7.hktid = a5.hktid
//  left outer join t012             as a8  on  a8.bukrs = a5.bukrs
//                                          and a8.hbkid = a5.hbkid
//  left outer join bnka             as a9  on  a9.banks = a8.banks
//                                          and a9.bankl = a8.bankl
//  left outer join tiban            as a10 on a10.banks = a8.banks
////                                              and a10.bankl = a8.bankl
////                                              and a10.bankn = a7.bankn
////    left outer join ZI_SALES_REFERENCE as a11 on  a11.CompanyCode = a.bukrs
////                                              and a11.SAPDocument = a.vbeln
////                                              and a11.FiscalYear  = a.gjahr
////Supplier Details
//  left outer join t001             as b1  on b1.bukrs = a.bukrs
//  left outer join adrc             as b2  on b2.addrnumber = b1.adrnr
//  left outer join zeinv_company    as b3  on b3.bukrs = a.bukrs
//  left outer join zeinv_pay_method as b4  on b4.payment_method = b3.payment_method
//  left outer join zeinv_state      as b5  on b5.state = b2.region
////Buyer
//  left outer join kna1             as c2  on c2.kunnr = a5.kunnr
//  left outer join adrc             as c3  on c3.addrnumber = c2.adrnr
//  left outer join dfkkbptaxnum     as c4  on  c4.partner = a5.kunnr
//                                          and c4.taxtype = 'AE0'
//  left outer join dfkkbptaxnum     as c5  on  c5.partner = a5.kunnr
//                                          and c5.taxtype = 'AE1'
//  left outer join but0id           as c6  on  c6.partner         = a5.kunnr
//                                          and c6.type            = 'AELRID'
//                                          and c6.valid_date_from <= $session.system_date
//                                          and c6.valid_date_to   >= $session.system_date
//  left outer join but0id           as c7  on  c7.partner         = a5.kunnr
//                                          and c7.type            = 'PAP001'
//                                          and c7.valid_date_from <= $session.system_date
//                                          and c7.valid_date_to   >= $session.system_date
//  left outer join knb1             as c8  on  c8.kunnr = a5.kunnr
//                                          and c8.bukrs = a.bukrs
//  left outer join zeinv_pay_method as c9  on c9.payment_method = c8.zwels
//  left outer join t012             as c10 on  c10.bukrs = c8.bukrs
//                                          and c10.hbkid = c8.hbkid
//  left outer join bnka             as c11 on  c11.banks = c10.banks
//                                          and c11.bankl = c10.bankl
//  left outer join knbk             as c12 on  c12.kunnr = c8.kunnr
//                                          and c12.banks = c10.banks
//                                          and c12.bankl = c10.bankl
//                                          and c12.bvtyp = '0001'
//  left outer join tiban            as c13 on  c13.banks = c10.banks
//                                          and c13.bankl = c10.bankl
//                                          and c13.bankn = c12.bankn
//  left outer join zeinv_state      as c14 on c14.state = c3.region
//  //Payee
//    left outer join vbpa               as d1  on  d1.vbeln = a.vbeln
//                                              and d1.parvw = 'RG'
//    left outer join but020             as d2  on d2.partner = d1.kunnr
//    left outer join adrc               as d3  on d3.addrnumber = d2.addrnumber
//    left outer join dfkkbptaxnum       as d4  on  d4.partner = d1.kunnr
//                                              and d4.taxtype = 'AE0'
//    left outer join dfkkbptaxnum       as d5  on  d5.partner = d1.kunnr
//                                              and d5.taxtype = 'AE1'
//    left outer join but0id             as d6  on  d6.partner         = d1.kunnr
//                                              and d6.type            = 'AELRID'
//                                              and d6.valid_date_from <= $session.system_date
//                                              and d6.valid_date_to   >= $session.system_date
//    left outer join but0id             as d7  on  d7.partner         = d1.kunnr
//                                              and d7.type            = 'PAP001'
//                                              and d7.valid_date_from <= $session.system_date
//                                              and d7.valid_date_to   >= $session.system_date
//    left outer join zeinv_state        as d8  on d8.state = d3.region
//  //Delivery
//    left outer join vbpa               as e1  on  e1.vbeln = a.vbeln
//                                              and e1.parvw = 'AG'
//    left outer join kna1               as e2  on e2.kunnr = e1.kunnr
//    left outer join adrc               as e3  on e3.addrnumber = e2.adrnr
//    left outer join dfkkbptaxnum       as e4  on  e4.partner = e1.kunnr
//                                              and e4.taxtype = 'AE0'
//    left outer join dfkkbptaxnum       as e5  on  e5.partner = e1.kunnr
//                                              and e5.taxtype = 'AE1'
//    left outer join but0id             as e6  on  e6.partner         = e1.kunnr
//                                              and e6.type            = 'AELRID'
//                                              and e6.valid_date_from <= $session.system_date
//                                              and e6.valid_date_to   >= $session.system_date
//    left outer join but0id             as e7  on  e7.partner         = e1.kunnr
//                                              and e7.type            = 'PAP001'
//                                              and e7.valid_date_from <= $session.system_date
//                                              and e7.valid_date_to   >= $session.system_date
//    left outer join but000             as e8  on e8.partner = e1.kunnr
//    left outer join zeinv_state        as e9  on e9.state = e3.region
//
//{
//  key a.bukrs                                    as CompanyCode,
//  key a.belnr                                    as SAPDocument,
//  key a.gjahr                                    as FiscalYear,
//  key 'FI'                                       as Type,
//      'Finance'                                  as TypeName,
//      a.cpudt                                    as CreationDate,
//      a.cputm                                    as CreationTime,
//      a.bldat                                    as BillingDate,
//      a.blart                                    as DocumentType,
//      a3.eitype                                  as EInvoiceType,
//      a3.automatic                               as AutoEInvoice,
//      a.xblnr                                    as HeaderReference,
//      cast( '' as vbeln_va )                     as SalesDocument,
//      a.xblnr                                    as CustomerReference,
//      //a11.EInvoiceCreditNoteReason               as EInvoiceCreditNoteReason,
//      a.waers                                    as Currency,
//      a.knumv                                    as ConditionNo,
//      case when a1.msgty is not null or
//                a1.msgty is not initial
//           then a1.msgty
//           else 'P'
//      end                                        as MessageType,
//      case when a1.msgty = 'S' then '@5B@'
//           when a1.msgty = 'E' then '@5C@'
//           when a1.msgty = 'W' then '@5D@'
//           else '@BZ@'
//      end                                        as Status,
//      a1.dformat                                 as RequestFormat,
//      a1.request_payload                         as RequestPayload,
//      a1.referenceid                             as ReferenceID,
//      case when a1.pstatus is null or
//                a1.pstatus is initial
//           then 'PENDING'
//           else a1.pstatus
//      end                                        as EInvoiceStatus,
//      a1.response_payload                        as ResponsePayload,
//      a2.vtext                                   as PaymentTerms,
//      a4.vbeln                                   as OriginalDocument,
//      a4.bukrs                                   as OriginalCompanyCode,
//      a4.gjahr                                   as OriginalFiscalYear,
//      a4.erdat                                   as OriginalCreationDate,
//      a5.zlsch                                   as PaymentMethod,
//      a6.eipayment_method                        as EInvoicePaymentMethod,
//      a6.eipayment_method_name                   as EInvoicePaymentMethodName,
//      a10.iban                                   as IBAN,
//      a9.banka                                   as AccountName,
//      a9.swift                                   as SWIFTCode,
//      //Seller Address
//      concat_with_space( b2.name1, b2.name2, 1 ) as SupplierName,
//      b2.street                                  as SupplierStreetName,
//      b2.str_suppl1                              as SupplierAdditionalStreetName,
//      b2.city1                                   as SupplierCityName,
//      b2.post_code1                              as SupplierPostalCode,
//      b5.eistate                                 as SupplierRegion,
//      b2.country                                 as SupplierCountry,
//      b3.trn                                     as SupplierVATRegistrationCode,
//      b3.tin                                     as SupplierTIN,
//      b3.trade_license                           as SupplierLegalRegistrationID,
//      b3.peppol_id                               as SupplierPeppolID,
//      b3.asp_id                                  as SupplierASPID,
//      b4.eipayment_method                        as SupplierPaymentMethod,
//      b4.eipayment_method_name                   as SupplierPaymentMethodName,
//      b3.iban                                    as SupplierIBAN,
//      b3.account_name                            as SupplierAccountName,
//      b3.swift_code                              as SupplierSWIFTCode,
//      //Customer Address
//      a5.kunnr                                   as Customer,
//      concat_with_space( c3.name1, c3.name2, 1 ) as CustomerName,
//      c3.street                                  as CustomerStreetName,
//      c3.str_suppl1                              as CustomerAdditionalStreetName,
//      c3.city1                                   as CustomerCityName,
//      c3.post_code1                              as CustomerPostalCode,
//      c14.eistate                                as CustomerRegion,
//      c3.country                                 as CustomerCountry,
//      c4.taxnum                                  as CustomerVATRegistrationCode,
//      c5.taxnum                                  as CustomerTIN,
//      c6.idnumber                                as CustomerLegalRegistrationID,
//      c7.idnumber                                as CustomerPeppolID,
//      c8.zzeinvoice                              as EInvoiceEnabled,
//      c8.zzbusinesstype                          as BusinessType,
//      c8.zzzonetype                              as ZoneType,
//      c9.eipayment_method                        as CustomerPaymentMethod,
//      c9.eipayment_method_name                   as CustomerPaymentMethodName,
//      c13.iban                                   as CustomerIBAN,
//      c11.banka                                  as CustomerAccountName,
//      c11.swift                                  as CustomerSWIFTCode,
//      //Payee Address
//      d1.kunnr                                   as Payee,
//      concat_with_space( d3.name1, d3.name2, 1 ) as PayeeName,
//      d3.street                                  as PayeeStreetName,
//      d3.str_suppl1                              as PayeeAdditionalStreetName,
//      d3.city1                                   as PayeeCityName,
//      d3.post_code1                              as PayeePostalCode,
//      d8.eistate                                 as PayeeRegion,
//      d3.country                                 as PayeeCountry,
//      d4.taxnum                                  as PayeeVATRegistrationCode,
//      d5.taxnum                                  as PayeeTIN,
//      d6.idnumber                                as PayeeLegalRegistrationID,
//      d7.idnumber                                as PayeePeppolID,
//      //Delivery/Ship-To Address
//      e1.kunnr                                   as ShipTo,
//      concat_with_space( e3.name1, e3.name2, 1 ) as ShipToName,
//      e3.street                                  as ShipToStreetName,
//      e3.str_suppl1                              as ShipToAdditionalStreetName,
//      e3.city1                                   as ShipToCityName,
//      e3.post_code1                              as ShipToPostalCode,
//      e9.eistate                                 as ShipToRegion,
//      e3.country                                 as ShipToCountry,
//      e4.taxnum                                  as ShipToVATRegistrationCode,
//      e5.taxnum                                  as ShipToTIN,
//      e6.idnumber                                as ShipToLegalRegistrationID,
//      e7.idnumber                                as ShipToPeppolID,
//
//      //AmountDetails
//      @Semantics.amount.currencyCode: 'Currency'
//      a.netwr                                    as NetValue,
//      @Semantics.amount.currencyCode: 'Currency'
//      a.mwsbk                                    as TaxValue,
//      @Semantics.amount.currencyCode: 'Currency'
//      @Aggregation.default: #SUM
//      a.netwr + a.mwsbk                          as TotalValue
//
//}
