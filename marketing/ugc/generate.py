import argparse,asyncio,json,os,shutil,subprocess
from pathlib import Path
ROOT=Path("ugc-output");ROOT.mkdir(exist_ok=True)
actor="Same 24-year-old Indian man from Bengaluru, short curly black hair, medium brown complexion, faint stubble, faded maroon T-shirt and navy backpack. Raw handheld iPhone 12 front-camera video, lived-in apartment and Bengaluru street, imperfect exposure, ordinary Indian domestic environment, natural skin texture. No commercial film lighting, no beauty filter, no polished advertisement, no text overlays, no generated speech, no fake app UI. "
shots=[
"Packing backpack on messy apartment bed, sees a notification, pauses deadpan and looks back at camera.",
"More messages arriving, turns selfie camera towards one ordinary cardboard parcel near backpack.",
"Two little boxes and achar dabba beside bag, stares at the pile and rubs forehead disbelievingly.",
"Shows pile of relatives' parcels while laughing at absurdity in cluttered bedroom.",
"Glances at phone as if idea has clicked, gives little half-smile on apartment landing.",
"Walks out of apartment entrance onto Bengaluru lane filming arm's length selfie, parked scooters, natural traffic.",
"Walking outside apartment, another notification, rolls his eyes with a laugh and abruptly lowers the phone."
]
lines=[
("The most dangerous words in India... भाई, एक छोटा सा काम है!","hi-IN-MadhurNeural"),
("कल पुणे निकल रहा हूँ. गलती से स्टोरी डाल दी. बस भाई.","hi-IN-MadhurNeural"),
("भाई, पुणे जा रहा है ना? बस एक छोटा सा बॉक्स है. अचार भी है!","hi-IN-SwaraNeural"),
("ये देख! मेरे कपड़े कम, दूसरों का सामान ज़्यादा. मैं पुणे जा रहा हूँ, कूरियर सर्विस नहीं चला रहा!","hi-IN-MadhurNeural"),
("फिर दोस्त ने ShipdeHop दिखाया. उस पे पहले से ट्रैवल करने वाले लोग पार्सल भी ले जा सकते हैं.","hi-IN-MadhurNeural"),
("अच्छा, तो सब आपस में डिसाइड कर लो. और ऐप का कमीशन जीरो!","hi-IN-MadhurNeural"),
("भाई एक आख़िरी छोटा सा काम है... नहीं भाई. लिंक भेज रहा हूँ!","hi-IN-MadhurNeural")]
def run(cmd):return subprocess.run(cmd,check=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
def dur(p):
 try:return float(run(["ffprobe","-v","error","-show_entries","format=duration","-of","default=noprint_wrappers=1:nokey=1",str(p)]).stdout.strip())
 except:return 0
def findvideo(obj):
 if isinstance(obj,str) and '.mp4' in obj:return obj
 if isinstance(obj,dict):
  for v in obj.values():
   a=findvideo(v)
   if a:return a
 if isinstance(obj,(tuple,list)):
  for v in obj:
   a=findvideo(v)
   if a:return a
 return None
def scene(i):
 from gradio_client import Client
 prompt=actor+shots[i]+" A SINGLE 5 second continuous phone video, realistic candid phone-camera motion, ambience only."
 c=Client("Lightricks/LTX-2-3")
 print("SPACE API",c.view_api(),flush=True)
 # Public API can change. Record failure rather than silently fabricate video.
 try: r=c.predict(None,prompt,5.0,False,71+i,False,768,512,api_name="/generate_video")
 except Exception as e:
  (ROOT/f"scene_{i}.error.txt").write_text(repr(e));raise
 p=findvideo(r)
 if not p:raise RuntimeError("Free Space did not return an MP4: "+repr(r)[:800])
 out=ROOT/f"scene_{i}.mp4"
 if p.startswith("https://"):
  import requests
  resp=requests.get(p,timeout=120);resp.raise_for_status();out.write_bytes(resp.content)
 else:shutil.copy(p,out)
 assert dur(out)>1 and out.stat().st_size>30000,"Invalid generated scene"
 print("CREATED",out)
async def voice():
 import edge_tts
 for i,(line,model) in enumerate(lines):
  try:await edge_tts.Communicate(line,model,rate="+7%").save(str(ROOT/f"voice_{i}.mp3"))
  except Exception as e:(ROOT/f"voice_{i}.error.txt").write_text(repr(e))
def assemble():
 from pydub import AudioSegment
 vids=sorted(ROOT.glob("scene_*.mp4"))
 if not vids:raise RuntimeError("No generated video clips to assemble")
 processed=[];audio=AudioSegment.silent(duration=80000,frame_rate=24000);start=0
 for p in vids:
  i=int(p.stem.split("_")[-1]);wav=ROOT/f"voice_{i}.mp3"
  n=max(dur(p),min(7.8,dur(wav)+.25 if wav.exists() else 5))
  out=ROOT/f"cut_{i}.mp4"
  run(["ffmpeg","-y","-i",str(p),"-vf",f"scale=540:960:force_original_aspect_ratio=increase,crop=540:960,tpad=stop_mode=clone:stop_duration=4,trim=duration={n},setpts=PTS-STARTPTS","-r","24","-an","-c:v","libx264","-preset","veryfast","-crf","25",str(out)])
  processed.append(out)
  if wav.exists():audio=audio.overlay(AudioSegment.from_mp3(wav),position=int((start+.1)*1000))
  start+=n
 (ROOT/"concat.txt").write_text("".join(f"file '{p.resolve()}'\n" for p in processed))
 run(["ffmpeg","-y","-f","concat","-safe","0","-i",str(ROOT/"concat.txt"),"-c","copy",str(ROOT/"visuals.mp4")])
 # Synthetic voices are disclosed in manifest. Do not imply a real human performed.
 audio[:int(start*1000)].export(ROOT/"audio.wav",format="wav")
 run(["ffmpeg","-y","-i",str(ROOT/"visuals.mp4"),"-i",str(ROOT/"audio.wav"),"-c:v","copy","-c:a","aac","-shortest","-movflags","+faststart",str(ROOT/"ShipdeHop_AI_UGC_Draft.mp4")])
 (ROOT/"report.json").write_text(json.dumps({"status":"AI generated draft","scene_count":len(vids),"synthetic_voices":True,"not_real_footage":True,"duration_seconds":start},indent=2))
if __name__=="__main__":
 parser=argparse.ArgumentParser();parser.add_argument("action",choices=["scene","voice","assemble"]);parser.add_argument("--scene",type=int,default=0);a=parser.parse_args()
 if a.action=="scene":scene(a.scene)
 elif a.action=="voice":asyncio.run(voice())
 else:assemble()
