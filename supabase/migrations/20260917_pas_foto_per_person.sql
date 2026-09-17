-- Pas Foto dihitung berdasarkan jumlah orang
update public.packages
set
  pricing_type = 'per_person',
  included_people = null,
  additional_person_fee = null,
  min_people = 1,
  max_people = null
where slug in (
  'pas-foto-tanpa-print',
  'pas-foto-dengan-print'
);
