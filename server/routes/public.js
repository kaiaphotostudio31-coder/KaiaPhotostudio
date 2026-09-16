const express = require('express');
const crypto = require('crypto');
const router = express.Router();

function bookingAccessToken(booking) {
  const secret = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!secret) throw new Error('SUPABASE_SERVICE_ROLE_KEY is required');
  return crypto.createHmac('sha256', secret).update(`kaia-booking:${booking.id}:${booking.idempotency_key || ''}`).digest('base64url');
}
function safeEqual(a,b) {
  const aa=Buffer.from(String(a)); const bb=Buffer.from(String(b));
  return aa.length===bb.length && crypto.timingSafeEqual(aa,bb);
}
const supabase = require('../supabase');
const { readSettings } = require('../config');
const { toMinutes, toHHMM, todayJakartaStr, nowInJakarta, overlaps } = require('../utils/time');
const { computePricing } = require('../utils/pricing');
const { listDriveImages, getDriveImageStream } = require('../google');

router.get('/settings/public', async (req, res) => {
  const s = await readSettings();
  res.json({ studioName:s.studioName,address:s.address,openTime:s.openTime,closeTime:s.closeTime,whatsapp:s.whatsapp,instagram:s.instagram,bankName:s.bankName,bankAccount:s.bankAccount,bankHolder:s.bankHolder });
});

function mapPackage(p) { return { id:p.id,category:p.category,name:p.name,slug:p.slug,description:p.description,pricingType:p.pricing_type,basePrice:p.base_price,includedPeople:p.included_people,additionalPersonFee:p.additional_person_fee,minPeople:p.min_people,maxPeople:p.max_people,durationMinutes:p.duration_minutes,isAddon:!!p.is_addon,benefits:p.benefits||[],terms:p.terms||[],printOptions:p.print_options||[] }; }

router.get('/packages', async (req,res)=>{
  const {data,error}=await supabase.from('packages').select('*').eq('active',true).order('category').order('base_price');
  if(error) return res.status(500).json({error:'Gagal memuat paket.'});
  const packages=(data||[]).map(mapPackage), grouped={}; packages.forEach(p=>(grouped[p.category] ||= []).push(p));
  res.json({packages,grouped});
});

async function getBusySlots(date) {
  const [{data:bookings},{data:blocked}] = await Promise.all([
    supabase.from('bookings').select('start_time,end_time').eq('booking_date',date).neq('booking_status','Cancelled'),
    supabase.from('blocked_slots').select('start_time,end_time').eq('date',date)
  ]);
  return [...(bookings||[]),...(blocked||[])].filter(b=>b.start_time&&b.end_time).map(b=>({start:toMinutes(b.start_time),end:toMinutes(b.end_time)}));
}

router.get('/availability', async (req,res)=>{
  const {packageId,date}=req.query;
  if(!packageId||!date) return res.status(400).json({error:'Paket dan tanggal wajib diisi.'});
  const {data:pkg}=await supabase.from('packages').select('*').eq('id',packageId).eq('active',true).single();
  if(!pkg) return res.status(404).json({error:'Paket tidak ditemukan.'});
  if(pkg.is_addon) return res.status(400).json({error:'Paket ini add-on, bukan sesi booking utama.'});
  if(pkg.duration_minutes == null) return res.status(422).json({error:'Paket ini belum memiliki durasi yang ditentukan. Silakan hubungi admin untuk penjadwalan manual.',manualScheduling:true});
  const settings=await readSettings(), openMin=toMinutes(settings.openTime), closeMin=toMinutes(settings.closeTime), step=Number(settings.slotIntervalMinutes)||10, duration=Number(pkg.duration_minutes), busy=await getBusySlots(date);
  const isToday=date===todayJakartaStr(), now=nowInJakarta(), nowMin=isToday?now.getHours()*60+now.getMinutes():-1, slots=[];
  for(let t=openMin;t+duration<=closeMin;t+=step){ if(isToday&&t<=nowMin) continue; if(!busy.some(b=>overlaps(t,t+duration,b.start,b.end))) slots.push(toHHMM(t)); }
  res.json({date,durationMinutes:duration,slots});
});

router.post('/bookings', async (req,res)=>{
  const {packageId,date,startTime,customerName,whatsapp,email,peopleCount,photoUploadPermission}=req.body;
  const idempotencyKey=String(req.get('Idempotency-Key')||'').trim();
  if(!idempotencyKey || idempotencyKey.length<16 || idempotencyKey.length>200) return res.status(400).json({error:'Idempotency-Key wajib diisi (minimal 16 karakter).'});
  if(!packageId||!date||!startTime) return res.status(400).json({error:'Paket, tanggal, dan jam wajib dipilih.'});
  if(!customerName||!String(customerName).trim()) return res.status(400).json({error:'Nama wajib diisi.'});
  if(!whatsapp||!String(whatsapp).trim()) return res.status(400).json({error:'Nomor WhatsApp wajib diisi.'});
  if(photoUploadPermission!=='Ya'&&photoUploadPermission!=='Tidak') return res.status(400).json({error:'Izin upload foto wajib dipilih.'});
  const {data:pkg}=await supabase.from('packages').select('*').eq('id',packageId).eq('active',true).single();
  if(!pkg) return res.status(404).json({error:'Paket tidak ditemukan atau sudah tidak aktif.'});
  if(pkg.is_addon) return res.status(400).json({error:'Paket add-on tidak bisa dibooking sebagai sesi utama.'});
  if(pkg.duration_minutes==null) return res.status(422).json({error:'Paket ini belum memiliki durasi yang ditentukan. Silakan hubungi admin untuk penjadwalan manual.',manualScheduling:true});
  const pricing=computePricing(pkg,peopleCount); if(pricing.errors.length) return res.status(400).json({error:pricing.errors[0]});
  const settings=await readSettings(), openMin=toMinutes(settings.openTime), closeMin=toMinutes(settings.closeTime), startMin=toMinutes(startTime), endMin=startMin+Number(pkg.duration_minutes);
  if(startMin<openMin||endMin>closeMin) return res.status(400).json({error:'Studio tidak beroperasi pada jam tersebut.'});
  const today=todayJakartaStr(); if(date<today) return res.status(400).json({error:'Tanggal booking tidak boleh di masa lalu.'});
  if(date===today && startMin<=nowInJakarta().getHours()*60+nowInJakarta().getMinutes()) return res.status(400).json({error:'Jam yang dipilih sudah lewat.'});
  const payload={packageId,date,startTime,customerName:String(customerName).trim(),whatsapp:String(whatsapp).trim(),email:String(email||'').trim(),peopleCount:Number(peopleCount),photoUploadPermission};
  const requestHash=crypto.createHash('sha256').update(JSON.stringify(payload)).digest('hex');
  const {data:booking,error}=await supabase.rpc('create_booking',{
    p_idempotency_key:idempotencyKey,p_request_hash:requestHash,p_customer_name:payload.customerName,p_whatsapp:payload.whatsapp,p_email:payload.email,p_package_id:pkg.id,
    p_package_name:pkg.name,p_category:pkg.category,p_pricing_type:pkg.pricing_type,p_base_price:pricing.basePrice,p_duration_minutes:pkg.duration_minutes,
    p_additional_person_fee:pkg.additional_person_fee,p_included_people:pkg.included_people,p_people_count:payload.peopleCount,p_additional_people_charged:pricing.additionalPeopleCharged,
    p_total_price:pricing.totalPrice,p_booking_date:date,p_start_time:startTime,p_photo_upload_permission:photoUploadPermission
  });
  if(error){ const m=error.message||''; if(m.includes('SLOT_TAKEN')) return res.status(409).json({error:'Maaf, slot ini baru saja dibooking customer lain. Silakan pilih jam lain.'}); if(m.includes('IDEMPOTENCY_CONFLICT')) return res.status(409).json({error:'Idempotency-Key sudah pernah dipakai untuk data booking yang berbeda.'}); console.error(error); return res.status(500).json({error:'Booking gagal. Silakan coba lagi.'}); }
  const b=Array.isArray(booking)?booking[0]:booking;
  res.status(201).json({bookingCode:b.booking_code,accessToken:bookingAccessToken(b),packageName:b.package_name_snapshot,basePrice:b.base_price_snapshot,additionalPeopleCharged:b.additional_people_charged,additionalFeeTotal:(b.additional_people_charged||0)*(b.additional_person_fee_snapshot||0),totalPrice:b.total_price,date:b.booking_date,startTime:b.start_time,endTime:b.end_time,peopleCount:b.people_count,paymentStatus:b.payment_status,bookingStatus:b.booking_status,settings:{whatsapp:settings.whatsapp,bankName:settings.bankName,bankAccount:settings.bankAccount,bankHolder:settings.bankHolder}});
});

router.get('/bookings/:code', async(req,res)=>{ const token=String(req.query.token||''); if(!token)return res.status(401).json({error:'Token akses booking diperlukan.'}); const {data:b}=await supabase.from('bookings').select('*').eq('booking_code',req.params.code).single(); if(!b)return res.status(404).json({error:'Booking tidak ditemukan.'}); let expected; try{expected=bookingAccessToken(b);}catch(e){return res.status(500).json({error:'Status booking belum dapat dimuat.'});} if(!safeEqual(token,expected))return res.status(403).json({error:'Token akses booking tidak valid.'}); res.json({bookingCode:b.booking_code,packageName:b.package_name_snapshot,basePrice:b.base_price_snapshot,additionalPeopleCharged:b.additional_people_charged,totalPrice:b.total_price,date:b.booking_date,startTime:b.start_time,endTime:b.end_time,peopleCount:b.people_count,paymentStatus:b.payment_status,bookingStatus:b.booking_status,calendarSyncStatus:b.calendar_sync_status||'pending'}); });

// Secure photo selection: the token is the only customer authorization credential.
router.get('/selection/:token', async(req,res)=>{
  const tokenHash=crypto.createHash('sha256').update(req.params.token).digest('hex');
  const {data:s,error}=await supabase.from('photo_selection_sessions').select('id,booking_id,expires_at,status,template_code,selected_color').eq('token_hash',tokenHash).maybeSingle();
  if(error||!s) return res.status(404).json({error:'Link foto tidak valid.'});
  if(new Date(s.expires_at)<new Date()) return res.status(410).json({error:'Link foto sudah kedaluwarsa.'});
  const {data:b}=await supabase.from('bookings').select('booking_code,customer_name').eq('id',s.booking_id).single();
  const {data:photos}=await supabase.from('photo_metadata').select('id,display_name,code,mime_type').eq('selection_session_id',s.id).order('display_name');
  const publicPhotos=(photos||[]).map(p=>({...p,thumbnail_url:`/api/selection/${encodeURIComponent(req.params.token)}/photo/${p.id}`}));
  const {data:templates}=await supabase.from('templates').select('code,name,status,config').order('code');
  res.json({session:{id:s.id,bookingCode:b?.booking_code,customerName:b?.customer_name,expiresAt:s.expires_at,status:s.status,templateCode:s.template_code,selectedColor:s.selected_color},photos:publicPhotos,templates:templates||[]});
});

router.get('/selection/:token/photo/:photoId', async(req,res)=>{
  const tokenHash=crypto.createHash('sha256').update(req.params.token).digest('hex');
  const {data:s}=await supabase.from('photo_selection_sessions').select('id,expires_at').eq('token_hash',tokenHash).maybeSingle();
  if(!s||new Date(s.expires_at)<new Date()) return res.status(404).json({error:'Link foto tidak valid atau sudah kedaluwarsa.'});
  if(!/^\d+$/.test(String(req.params.photoId))) return res.status(400).json({error:'Foto tidak valid.'});
  const {data:photo}=await supabase.from('photo_metadata').select('drive_file_id,mime_type').eq('id',req.params.photoId).eq('selection_session_id',s.id).maybeSingle();
  if(!photo) return res.status(404).json({error:'Foto tidak ditemukan.'});
  if(!['image/jpeg','image/png','image/webp'].includes(photo.mime_type)) return res.status(415).json({error:'Tipe foto tidak didukung.'});
  try {
    const response=await getDriveImageStream(photo.drive_file_id);
    res.setHeader('Content-Type',photo.mime_type);
    res.setHeader('Cache-Control','private, max-age=300');
    response.data.on('error',()=>{ if(!res.headersSent) res.status(502); res.end(); });
    response.data.pipe(res);
  } catch(e) {
    console.error(e);
    res.status(502).json({error:'Foto tidak dapat dimuat.'});
  }
});

router.post('/selection/:token', async(req,res)=>{
  const tokenHash=crypto.createHash('sha256').update(req.params.token).digest('hex');
  const {data:s}=await supabase.from('photo_selection_sessions').select('*').eq('token_hash',tokenHash).maybeSingle();
  if(!s||new Date(s.expires_at)<new Date()) return res.status(404).json({error:'Link foto tidak valid atau sudah kedaluwarsa.'});
  const {photoIds,templateCode,color}=req.body;
  if(!Array.isArray(photoIds)||!photoIds.length) return res.status(400).json({error:'Pilih minimal satu foto.'});
  const {data:t}=await supabase.from('templates').select('*').eq('code',templateCode).single();
  if(!t||t.status!=='IMPLEMENTED') return res.status(400).json({error:'Template belum tersedia.'});
  const allowed=t.config?.supportedColors||[]; if(!allowed.includes(color)) return res.status(400).json({error:'Warna tidak tersedia untuk template ini.'});
  const {data:valid}=await supabase.from('photo_metadata').select('id').eq('selection_session_id',s.id).in('id',photoIds); if((valid||[]).length!==photoIds.length)return res.status(400).json({error:'Ada foto yang tidak valid untuk booking ini.'});
  const {error}=await supabase.rpc('submit_photo_selection',{p_session_id:s.id,p_photo_ids:photoIds,p_template_code:templateCode,p_color:color});
  if(error){ console.error(error); return res.status(500).json({error:'Gagal menyimpan pilihan foto.'}); }
  res.json({ok:true});
});

module.exports = router;
