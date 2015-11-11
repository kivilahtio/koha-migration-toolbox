(: Käydään perusasiakastiedot yksi kerrallaan:)





declare function local:generate-pass() as xs:string {
  let $start:=random:integer(13)
  let $rng:=random-number-generator()
  let $pass:=$rng('permute')(('1','2','3','7','9','3','7','9','8','5','6','4','8','5','6','4','1','2'))
  return substring(string-join($pass,''),$start,4)
  
  
};

declare function local:generate-phone() as item() {
  let $start:=random:integer(13)
  let $to_choose:=random:integer(5)
  let $rng:=random-number-generator()
  let $phone:=$rng('permute')(('1','2','3','7','9','3','7','9','8','5','6','4','8','5','6','4','1','2'))
  let $provider:=('044-','045-','040-','050-','0400','046')
  return concat($provider[$to_choose],substring(string-join($phone,''),$start,7))
  
  
};

declare function local:generate-firstname() as xs:untypedAtomic* {
  let $to_choose:=random:integer(80)
  let $firstname:=data(db:open("patron-data-conversion","etunimet")/etunimet/nimi[$to_choose])
  return $firstname
  
  
};

declare function local:generate-surname() as item() {
  let $to_choose:=random:integer(15440)
  let $firstname:=data(db:open("patron-data-conversion","sukunimet")/sukunimet/nimi[$to_choose])
  return 
    if ($firstname) then
    $firstname
    else('Makkonen')
  
  
};

declare function local:generate-address() as item() {
  let $to_choose:=random:integer(20000)
  let $address:=
    if(data(db:open("patron-data-conversion","05-patron_addresses.csv")/csv/record[ADDRESS_TYPE = "1"][$to_choose]/ADDRESS_LINE1)) then
     db:open("patron-data-conversion","05-patron_addresses.csv")/csv/record[ADDRESS_TYPE = "1"][$to_choose]/ADDRESS_LINE1
     else (
       'Kotikuja 2'
     )
     
  return $address
   
};


declare function local:generate-ssn() as xs:string {
  
 replace(substring(random:uuid(),1,8),'-','')
  
  
};

declare function local:convert-date-to-iso($date as xs:string) as xs:string {
  let $months := map {
  'JAN': "01",
  'FEB': "02",
  'MAR': "03",
  'APR': "04",
  'MAY': "05",
  'JUN': "06",
  'JUL': "07",
  'AUG': "08",
  'SEP': "09",
  'OCT': "10",
  'NOV': "11",
  'DEC': "12"}
  let $tokenized_date:=tokenize($date,'-')
  let $month_token:=if($tokenized_date[2] and string-length($tokenized_date[2]) eq 3) then $tokenized_date[2] else 'JAN'
  let $date_token:=if($tokenized_date[1] and string-length($tokenized_date[1]) eq 2) then $tokenized_date[1] else '01'
  let $year_token:=if($tokenized_date[3] and string-length($tokenized_date[3]) eq 2) then $tokenized_date[3] else '00'
  let $month:=if(map:contains($months,$month_token)) then
    map:get($months, $month_token)
    else ('01')
  return string-join((concat('20',$year_token),$month,$date_token),'-') 
  
};

declare function local:generate-barcode() as item() {
  let $start:=random:integer(13)
  let $to_choose:=random:integer(7)
  let $rng:=random-number-generator()
  let $phone:=$rng('permute')(('1','2','3','7','9','3','7','9','8','5','6','4','8','5','6','4','1','2'))
  return concat('TESTI',substring(string-join($phone,''),$start,7))
  
  
};
let $patrons:=
  <patrons>{
for $patron in db:open("patron-data-conversion","07-patron_names_dates.csv")/csv/record[position()>=20000]
return
  let $patron_id:=data($patron/PATRON_ID)
    let $null_patron_group:=data(db:open("patron-data-conversion","08-patron_groups_nulls")/csv/record[PATRON_ID eq $patron_id][1]/PATRON_GROUP_ID)
  let $old_patron_group:= 
    if ($null_patron_group) then
    $null_patron_group
    else (
      data(db:open("patron-data-conversion","06-patron_groups.csv")/csv/record[PATRON_ID eq $patron_id][1]/PATRON_GROUP_ID)
    )
  let $patron_category:=data(db:open("patron-data-conversion","patron_group_mapping")/csv/record[
    OLD_PATRON_GROUP eq $old_patron_group]/NEW_PATRON_GROUP)
  let $phone:= 
    db:open("patron-data-conversion","10-patron_phones.csv")/csv/record[PATRON_ID 
      eq $patron_id and PHONE_DESC eq 'Primary']/PHONE_NUMBER
  let $institution_id_attribute:=
    if ($patron/INSTITUTION_ID) then
      concat('INST_ID:',local:generate-ssn())
      else()
  let $patron_barcode:=if (db:open("patron-data-conversion","patron_barcode_data.csv")/csv/record[
    PATRON_ID eq $patron_id]/PATRON_BARCODE) then
    db:open("patron-data-conversion","patron_barcode_data.csv")/csv/record[
    PATRON_ID eq $patron_id]/PATRON_BARCODE
    else (local:generate-barcode())
    
  let $old_stat_code:=data(db:open("patron-data-conversion","patron_stat_data.csv")/csv/record[PATRON_ID eq $patron_id][1]/PATRON_STAT_CODE)
  let $stat_code_attribute:=if ($old_stat_code) then
    concat('PATRON_STAT_CODE:',db:open("patron-data-conversion","tilastoryhmat")/csv/record[OLD_STAT_CODE 
    eq $old_stat_code]/NEW_STAT_CODE)
    else()
  let $second_barcode:=data(db:open("patron-data-conversion","06-patron_groups.csv")/csv/record[PATRON_ID eq $patron_id][1]/PATRON_BARCODE)
  let $pass:=data(db:open("patron-data-conversion","pass")/csv/record[PATRON_BARCODE eq $patron_barcode]/PASS)
  let $email:=data(db:open("patron-data-conversion","07-patron_addresses.csv")/csv/record[PATRON_ID eq $patron_id and ADDRESS_TYPE = 3]/ADDRESS_LINE1)
  let $full_address:=db:open("patron-data-conversion","05-patron_addresses.csv")/csv/record[
    PATRON_ID = $patron_id and ADDRESS_TYPE = "1"][1]
  let $patron_notes:=data(db:open("patron-data-conversion","09-patron_notes.csv")/csv/record[PATRON_ID = $patron_id]/NOTE)
return
<patron>
  <cardnumber>{data($patron_barcode)}</cardnumber>
  <surname>{local:generate-surname()}</surname>
  <firstname>{local:generate-firstname()}</firstname>
  <title></title>
  <othernames>{data($patron/MIDDLE_NAME)}</othernames>
  <address>{data(local:generate-address())}</address>
  <address2>{normalize-space(string-join(($full_address//ADDRESS_LINE2,$full_address//ADDRESS_LINE3),' '))}</address2>
  <city>{normalize-space(data($full_address//ADDRESS_LINE5[1]))}</city>
  <zipcode>{data($full_address//STATE_PROVINCE[1])}</zipcode>
  <country></country>
  <phone>{local:generate-phone()}</phone>
  <mobile></mobile>
  <email>koha.t.account@jyu.fi</email>
  <emailpro></emailpro>
  <branchcode>main</branchcode>
  <categorycode>{$patron_category}</categorycode>
  <dateenrolled>{local:convert-date-to-iso(data($patron/REGISTRATION_DATE))}</dateenrolled>
  <dateexpiry>{local:convert-date-to-iso(data($patron/EXPIRE_DATE))}</dateexpiry>
  <borrowernotes>{$patron_notes}</borrowernotes>
  <userid>{$second_barcode}</userid>
  <password>{local:generate-pass()}</password>
  <flags></flags>
  <patron_attributes>{string-join(($institution_id_attribute,$stat_code_attribute),',')}</patron_attributes>
</patron>
}</patrons>

return file:write('/Users/majulass/Documents/2015/koha-migration-data/patrons-20000-to-end.xml',$patrons)