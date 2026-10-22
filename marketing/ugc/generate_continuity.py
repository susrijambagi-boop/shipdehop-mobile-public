import argparse, json, shutil, subprocess, time, traceback
from pathlib import Path

OUT = Path("ugc-output")
OUT.mkdir(exist_ok=True)
ANCHOR = Path("ugc-anchor.jpg")

BASE = ("Raw candid selfie footage from a smartphone's front camera in a normal Bengaluru Indian apartment, "
        "same Indian young man as the reference image: curly black hair, medium brown skin, navy backpack and maroon t-shirt, "
        "24 years old. Natural daylight, believable ordinary body movement, handheld smartphone shake, "
        "no studio lighting, natural imperfect exposure, wide focus, modest bedroom, shoes by door. "
        "Single physically plausible continuous 5-second take, no cuts, no captions, no commercial grade, "
        "no speech, no hand abnormalities, no text.")

SHOTS = {
  0:"He is looking down and adding folded clothes to a backpack on his bed, then a phone notification distracts him. He freezes and looks at the camera with raised eyebrow. Frame stays in selfie arm's length.",
  2:"He is next to an overpacked backpack and a couple of small boxes on the bed. He slowly turns the selfie camera down to show boxes and a metal achar jar, then turns to the camera with annoyance.",
  4:"He sits on the edge of a messy bed, notices a phone notification, rolls his eyes, then grins as an idea occurs to him. Natural selfie arm's length view.",
  5:"He walks slowly down a simple apartment corridor while filming himself on his phone. Small natural walking jiggle, backpack strap visible, daylight visible at far door.",
  6:"He is in the doorway of his Bengaluru apartment, a small parcel appears held by another person's hand from off-screen, he laughs and shakes his head in disbelief, selfie camera wobble."
}

def gen(i):
    from gradio_client import Client, handle_file
    c=Client("Lightricks/LTX-2-3")
    prompt=BASE+" "+SHOTS[i]
    errors=[]
    for n in range(1,5):
      try:
        print("scene", i, "attempt", n, flush=True)
        r=c.predict(handle_file(str(ANCHOR)),prompt,5.0,False,220+i*10+n,False,768,512,api_name="/generate_video")
        file=r[0] if isinstance(r,(tuple,list)) else r
        if isinstance(file,dict): file=file.get("path") or file.get("url")
        if not file or not isinstance(file,str):raise ValueError("invalid output "+repr(r)[:500])
        out=OUT/f"scene_{i}.mp4"
        if file.startswith("http"):
          import requests
          data=requests.get(file,timeout=90);data.raise_for_status();out.write_bytes(data.content)
        else:shutil.copyfile(file,out)
        probe=subprocess.run(["ffprobe","-v","error","-select_streams","v","-show_entries","stream=nb_frames,width,height","-of","json",str(out)],text=True,capture_output=True)
        if probe.returncode or out.stat().st_size < 70000: raise ValueError("invalid video "+probe.stdout)
        print("SUCCESS", str(out),out.stat().st_size,flush=True)
        return
      except Exception as exc:
        s=f"attempt {n}: {type(exc).__name__}: {str(exc)}"
        print(s,flush=True);errors.append(s)
        time.sleep(5)
    (OUT/f"scene_{i}.error.txt").write_text("\n".join(errors))
    raise RuntimeError("No free GPU after 4 attempts")
if __name__=="__main__":
   a=argparse.ArgumentParser()
   a.add_argument("--scene",type=int,required=True)
   args=a.parse_args()
   gen(args.scene)
