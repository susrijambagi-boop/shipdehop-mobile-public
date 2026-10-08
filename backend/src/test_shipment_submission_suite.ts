import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import Fastify from 'fastify';
import sensible from '@fastify/sensible';
// Dedicated offline process or imported only after the earlier route suites finish.
process.env.SUPABASE_URL ??= 'https://example.supabase.co';
process.env.SUPABASE_PUBLISHABLE_KEY ??= 'test-publishable-key';
process.env.SUPABASE_SECRET_KEY ??= 'test-secret-key';
process.env.GEMINI_API_KEY ??= 'test-gemini-key';
process.env.NODE_ENV ??= 'test';
const { adminSupabase } = await import('./lib/supabase.js');
const { config } = await import('./config.js');
const { hopShieldRoutes } = await import('./routes/hopshield.js');
const { shipmentDraftSchema, shipmentDraftRecord } = await import('./routes/shipmentDrafts.js');
const { validParcelImage } = await import('./services/parcelImage.js');
const { inspectWithGemini, normalizeInspection } = await import('./services/parcelInspection.js');
const { isPointInIndia } = await import('./lib/locationValidation.js');
const original = { from: adminSupabase.from, rpc: adminSupabase.rpc, fetch: globalThis.fetch,
  env: process.env.NODE_ENV, provider: config.PARCEL_INSPECTION_PROVIDER,
  dev: config.DEV_TEST_AUTH, aadhaar: config.BETA1_REQUIRE_AADHAAR };
const actor = '33333333-1111-4333-8333-111111111111';
const stranger = '44444444-1111-4333-8333-111111111111';
const payload = () => ({requestId: randomUUID(), itemType:'PARCEL', productUrl:null,
  declaredValue:15000,rewardAmount:500,weightKg:5,currency:'INR',
  pickupName:'Bengaluru',pickup:{lat:12.9716,lon:77.5946},
  dropName:'Hubballi',drop:{lat:15.3647,lon:75.124},
  earliestPickup:'2040-01-02T08:00:00+05:30', latestDelivery:'2040-01-03T22:00:00+05:30'});
const png = Buffer.concat([Buffer.from([137,80,78,71,13,10,26,10]), Buffer.alloc(100)]);
const photo = {imageBase64:png.toString('base64'), imageMimeType:'image/png'};
const rows = new Map<string, any>();
let verified = true, tier = 'TIER_2', dbOutage = false, geoOutage = false;
let modelOutage = false, modelMalformed = false, modelDecision = 'APPROVED';
let insertCalls = 0, modelCalls = 0, recordCalls = 0, recordLoss = false, insertLoss = false;
let passes = 0;
const check = async (label: string, test: () => unknown | Promise<unknown>) => {await test(); passes++; console.log(`PASS parcel submission: ${label}`);};
(adminSupabase as any).from = (table: string) => {
  const filters: Record<string, unknown> = {}; let inserted: any = null;
  const execute = async () => {
    if (table === 'user_identities') return {error:null,data:{id:randomUUID(),user_id:filters.user_id,
      verification_status:verified?'VERIFIED':'NOT_STARTED',identity_method:'OTHER_GOV_ID',created_at:new Date().toISOString(),consented_at:new Date().toISOString()}};
    if (table === 'users') return {data:{ekyc_tier:tier},error:null};
    assert.equal(table,'shipment_tasks','No arbitrary table access');
    if (dbOutage) return {data:null,error:{code:'UNAVAILABLE'}};
    if (inserted) {
      insertCalls++;
      if (rows.has(inserted.id)) return {data:null,error:{code:'23505'}};
      rows.set(inserted.id, {...inserted});
      if (insertLoss) {insertLoss=false;return {data:null,error:{code:'LOST_RESPONSE'}};}
      return {data:rows.get(inserted.id),error:null};
    }
    const row = rows.get(String(filters.id));
    return {data:row && Object.entries(filters).every(([k,v])=>row[k]===v)?{...row}:null,error:null};
  };
  const chain:any={select:()=>chain,eq:(k:string,v:unknown)=>{filters[k]=v;return chain;},
    insert:(value:unknown)=>{inserted=value;return chain;},single:execute,maybeSingle:execute};
  return chain;
};
(adminSupabase as any).rpc = async (name:string, p:any) => {
  if(name==='is_coord_in_india_f64') return {data:geoOutage?null:isPointInIndia(p.p_lat,p.p_lon),error:geoOutage?{code:'OFFLINE'}:null};
  assert.equal(name,'service_record_parcel_inspection'); recordCalls++;
  const row=rows.get(p.p_shipment_task_id);assert.equal(row.sender_id,p.p_submitted_by);
  row.inspection_status=p.p_decision;row.status=p.p_decision==='APPROVED'?'OPEN':'DRAFT';
  if(recordLoss){recordLoss=false;return {data:null,error:{code:'LOST_RESPONSE'}};}
  return {data:{...row},error:null};
};
globalThis.fetch=async input=>{
  const u=new URL(typeof input==='string'?input:input instanceof URL?input.href:input.url);
  assert.equal(u.hostname,'generativelanguage.googleapis.com','Only intercepted model requests permitted');
  modelCalls++;
  if(modelOutage)throw Error('controlled outage');
  return new Response(JSON.stringify({candidates:[{content:{role:'model',parts:[{text:modelMalformed?'not json':JSON.stringify({
    decision:modelDecision,confidence:.95,contentMismatch:false,prohibitedCategories:[],rationale:'Controlled fixture result',
  })}]},finishReason:'STOP'}]}),{headers:{'Content-Type':'application/json'}});
};
config.PARCEL_INSPECTION_PROVIDER='GEMINI';config.DEV_TEST_AUTH=false;config.BETA1_REQUIRE_AADHAAR=false;
process.env.NODE_ENV='production';
const app=Fastify();await app.register(sensible);
app.addHook('onRequest',async request=>{
  if(request.headers['x-fixture-actor']) {
    request.authUser={id:String(request.headers['x-fixture-actor'])} as any;
    request.userSupabase=adminSupabase;
  }
});
await app.register(hopShieldRoutes);await app.ready();
const draft=(body:any,user=actor)=>app.inject({method:'POST',url:'/hopshield/shipments/draft',payload:body,headers:{'x-fixture-actor':user}});
const scan=(id:string,body:any=photo,user=actor)=>app.inject({method:'POST',url:`/hopshield/shipments/${id}/inspect`,payload:body,headers:{'x-fixture-actor':user}});
try {
  await check('missing login creates no parcel',async()=>{const r=await app.inject({method:'POST',url:'/hopshield/shipments/draft',payload:payload()});assert.equal(r.statusCode,401);assert.equal(rows.size,0);});
  await check('real identity gate rejects unverified users before insertion',async()=>{verified=false;const r=await draft(payload());assert.equal(r.statusCode,403);assert.equal(r.json().error,'IDENTITY_VERIFICATION_REQUIRED');verified=true;assert.equal(rows.size,0);});
  await check('forged sender and client-supplied OPEN/APPROVED fields are rejected',async()=>{
    for(const extra of [{sender_id:stranger},{status:'OPEN'},{inspection_status:'APPROVED'}])assert.equal((await draft({...payload(),...extra})).statusCode,400);
    assert.equal(rows.size,0);
  });
  await check('15000 INR, 500 reward and 5 kg create one server-owned pending draft',async()=>{
    const p=payload();const r=await draft(p);assert.equal(r.statusCode,201);const saved=r.json().shipment;
    assert.equal(saved.sender_id,actor);assert.equal(saved.status,'DRAFT');assert.equal(saved.inspection_status,'PENDING');
    assert.equal(saved.declared_value,15000);assert.equal(saved.reward_amount,500);assert.equal(saved.weight_kg,5);assert.equal(saved.currency,'INR');
    assert.equal(saved.earliest_pickup,'2040-01-02T02:30:00.000Z');
  });
  await check('same payload plus nonce replays across calls without inserting twice',async()=>{
    const p=payload();const a=await draft(p);const before=insertCalls;const b=await draft(p);
    assert.equal(a.json().shipment.id,b.json().shipment.id);assert.equal(b.json().replayed,true);assert.equal(insertCalls,before);
  });
  await check('lost create response retries the same primary key',async()=>{
    const p=payload();const before=rows.size;insertLoss=true;assert.equal((await draft(p)).statusCode,503);
    const r=await draft(p);assert.equal(r.statusCode,200);assert.equal(rows.size,before+1);
  });
  await check('concurrent identical creation requests converge on one database key',async()=>{
    const p=payload();const before=rows.size;const values=await Promise.all([draft(p),draft(p)]);
    assert.ok(values.every(r=>[200,201].includes(r.statusCode)));assert.equal(rows.size,before+1);
    assert.equal(values[0]!.json().shipment.id,values[1]!.json().shipment.id);
  });
  await check('another authenticated user cannot inherit a draft by reusing its nonce',async()=>{
    const p=payload();const a=await draft(p);const b=await draft(p,stranger);
    assert.notEqual(a.json().shipment.id,b.json().shipment.id);assert.equal(b.json().shipment.sender_id,stranger);
  });
  await check('new deliberate nonce produces a separate draft',()=>{
    const p=payload();const a=shipmentDraftRecord(actor,shipmentDraftSchema.parse(p));
    assert.notEqual(a.id,shipmentDraftRecord(actor,shipmentDraftSchema.parse({...p,requestId:randomUUID()})).id);
  });
  await check('non-INR, excessive weight, zero reward and invalid numbers cannot create drafts',async()=>{
    const before=rows.size;for(const edit of [{currency:'USD'},{weightKg:41},{weightKg:0},{rewardAmount:0},{declaredValue:-1},{weightKg:0.0001}])
      assert.equal((await draft({...payload(),...edit})).statusCode,400);assert.equal(rows.size,before);
  });
  await check('expired and backwards timing get actionable validation errors',async()=>{
    assert.equal((await draft({...payload(),earliestPickup:'2020-01-01T00:00:00Z',latestDelivery:'2020-01-02T00:00:00Z'})).json().error,'EXPIRED_TIMING');
    assert.equal((await draft({...payload(),earliestPickup:'2041-01-01T00:00:00Z'})).statusCode,400);
  });
  await check('outside-India endpoint and geofence outage fail closed',async()=>{
    const before=rows.size;assert.equal((await draft({...payload(),pickup:{lat:25.2854,lon:51.531}})).statusCode,400);
    geoOutage=true;assert.equal((await draft(payload())).statusCode,503);geoOutage=false;assert.equal(rows.size,before);
  });
  await check('Buy-for-Me keeps HTTPS and identity-tier requirements',async()=>{
    assert.equal((await draft({...payload(),itemType:'URL_PURCHASE',productUrl:'http://example.com'})).statusCode,400);
    tier='TIER_1';assert.equal((await draft({...payload(),itemType:'URL_PURCHASE',productUrl:'https://example.com/product'})).statusCode,403);tier='TIER_2';
    assert.equal((await draft({...payload(),itemType:'URL_PURCHASE',productUrl:'https://example.com/product'})).statusCode,201);
  });
  await check('lookup failure never triggers an insert',async()=>{
    dbOutage=true;const before=insertCalls;assert.equal((await draft(payload())).statusCode,503);assert.equal(insertCalls,before);dbOutage=false;
  });
  await check('mismatched format, malformed base64 and oversized photo rejected before a model call',async()=>{
    const id=(await draft(payload())).json().shipment.id;const before=modelCalls;
    for(const p of [{...photo,imageMimeType:'image/jpeg'},{...photo,imageBase64:'!'.repeat(100)},{...photo,imageBase64:Buffer.alloc(5*1024*1024+1).toString('base64')}])
      assert.equal((await scan(id,p)).statusCode,400);
    assert.equal(modelCalls,before);assert.equal(validParcelImage(photo.imageBase64,'image/png'),true);
  });
  await check('unrelated user cannot scan another sender parcel',async()=>{
    const id=(await draft(payload())).json().shipment.id;const before=modelCalls;assert.equal((await scan(id,photo,stranger)).statusCode,403);assert.equal(modelCalls,before);
  });
  await check('model outage leaves draft pending with retryable 503, not a fake review',async()=>{
    const id=(await draft(payload())).json().shipment.id;const before=recordCalls;modelOutage=true;
    const r=await scan(id);modelOutage=false;assert.equal(r.statusCode,503);assert.equal(rows.get(id).inspection_status,'PENDING');assert.equal(recordCalls,before);
  });
  await check('malformed model output is retryable without recording an assessment',async()=>{
    const id=(await draft(payload())).json().shipment.id;modelMalformed=true;const before=recordCalls;
    assert.equal((await scan(id)).statusCode,503);modelMalformed=false;assert.equal(recordCalls,before);
  });
  await check('retrying scan publishes the same draft only after saved approval',async()=>{
    const id=(await draft(payload())).json().shipment.id;modelOutage=true;await scan(id);modelOutage=false;
    const count=rows.size;const r=await scan(id);assert.equal(r.statusCode,200);assert.equal(rows.size,count);
    assert.equal(r.json().shipment.status,'OPEN');assert.equal(r.json().shipment.inspection_status,'APPROVED');
  });
  await check('lost scan-save response replays the saved status without a second model call',async()=>{
    const id=(await draft(payload())).json().shipment.id;recordLoss=true;assert.equal((await scan(id)).statusCode,503);
    const before=modelCalls;const r=await scan(id);assert.equal(r.statusCode,200);assert.equal(r.json().replayed,true);assert.equal(modelCalls,before);
  });
  await check('REVIEW and BLOCKED remain unpublished and are not reclassified on retry',async()=>{
    for(const decision of ['REVIEW','BLOCKED']) {
      modelDecision=decision;const id=(await draft(payload())).json().shipment.id;const a=await scan(id);assert.equal(a.json().shipment.status,'DRAFT');
      const before=modelCalls;const b=await scan(id);assert.equal(b.json().shipment.inspection_status,decision);assert.equal(modelCalls,before);
    }modelDecision='APPROVED';
  });
  await check('completed parcel cannot be inspected again',async()=>{
    const id=(await draft(payload())).json().shipment.id;rows.get(id).status='DELIVERED';const before=modelCalls;
    assert.equal((await scan(id)).statusCode,400);assert.equal(modelCalls,before);
  });
  await check('contradictory prohibited-category approval is downgraded',()=>{
    assert.equal(normalizeInspection({decision:'APPROVED',confidence:.9,contentMismatch:false,prohibitedCategories:['hazardous'],rationale:'Contradiction'}).decision,'REVIEW');
  });
  await check('a hung model times out to a retryable, non-approval result',async()=>{
    const result=await inspectWithGemini({...photo,imageMimeType:'image/png',itemType:'PARCEL'},
      {timeoutMs:5,aiClient:{models:{generateContent:async()=>new Promise(()=>{})}} as any});
    assert.equal(result.retryable,true);assert.equal(result.decision,'REVIEW');
  });
  console.log(`BATCH3B_SUBMISSION: ${passes} passed; real HTTP handlers with controlled DB/model/identity responses; no live transactions.`);
} finally {
  await app.close();adminSupabase.from=original.from;adminSupabase.rpc=original.rpc;globalThis.fetch=original.fetch;
  config.PARCEL_INSPECTION_PROVIDER=original.provider;config.DEV_TEST_AUTH=original.dev;config.BETA1_REQUIRE_AADHAAR=original.aadhaar;
  if(original.env===undefined)delete process.env.NODE_ENV;else process.env.NODE_ENV=original.env;
}
