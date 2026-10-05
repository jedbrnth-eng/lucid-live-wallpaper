# Graphics pass for the Day 1 reel (v4). Usage: python3 render_day1_reel.py out.mp4 [preview]
# Inputs: src/raw2.mp4 (clean phone take, no captions), src/img1339.mov (README install B-roll), src/img1341.mov (apply B-roll).
# Needs ffmpeg and Inter TTFs (Bold, SemiBold, Medium) in ./fonts (https://github.com/rsms/inter/releases).
# No stabilization on purpose: vidstab reads on-screen scrolling as camera shake and bounces the frame.
# Timings are keyed to the words in the original 31 s take; re-time the constants if the cut changes.
import subprocess, sys, os
F_B="fonts/Inter-Bold.ttf"; F_S="fonts/Inter-SemiBold.ttf"; F_M="fonts/Inter-Medium.ttf"
WHITE="white"; GREY="0xA1A1AA"; ACC="0x7C5CFF"; RED="0xFF453A"
CX="(w-text_w)/2"
def clip01(x): return f"min(1\\,max(0\\,{x}))"
def smooth(p): return f"({p})*({p})*(3-2*({p}))"              # smoothstep
def easeout(p): return f"(1-pow(1-({p})\\,3))"                 # cubic ease-out
def alpha(s,e,din=0.22,dout=0.22):
    pin=clip01(f"(t-{s})/{din}"); pout=clip01(f"({e}-t)/{dout}")
    return f"min({smooth(pin)}\\,{smooth(pout)})"
def rise(y,s,d=0.45,px=34):
    return f"{y}+{px}*(1-{easeout(clip01(f'(t-{s})/{d}'))})"
def txt(text,font,size,color,x,y,s,e,box=None,din=0.22,dout=0.22):
    t=text.replace("\\","\\\\").replace("'", "\\'").replace(":", "\\:").replace("%","%%")
    o=[f"drawtext=fontfile={font}",f"text='{t}'",f"fontsize={size}",f"fontcolor={color}",
       f"x={x}",f"y={y}",f"enable='between(t\\,{s}\\,{e})'",f"alpha='{alpha(s,e,din,dout)}'",
       "shadowcolor=black@0.5","shadowx=0","shadowy=4"]
    if box: o += ["box=1",f"boxcolor={box}","boxborderw=26"]
    return ":".join(o)
def dim(name,x,y,w,h,s,e,a,d=0.3):
    L=e-s
    return (f"color=c=black@{a}:s={w}x{h}:r=30:d={L},format=yuva420p,"
            f"fade=t=in:st=0:d={d}:alpha=1,fade=t=out:st={L-d}:d={d}:alpha=1,setpts=PTS+{s}/TB[{name}]"), (x,y)
STAB="null"
pre=[]
# base: stabilized, 1080x1920, slow 4% push-in over the whole take
pre.append("[0:v]"+STAB.format(trf="stab0.trf")+",scale=1080:1920:flags=lanczos,format=yuv420p[base]")
# cutaways with dissolve edges
pre.append("[1:v]"+STAB.format(trf="stab1.trf")+",trim=1.6:3.4,setpts=PTS-STARTPTS,scale=1080:1920:flags=lanczos,format=yuva420p,fade=t=in:st=0:d=0.3:alpha=1,fade=t=out:st=1.5:d=0.3:alpha=1,setpts=PTS+23.6/TB[c1]")
pre.append("[2:v]"+STAB.format(trf="stab2.trf")+",trim=4.3:5.9,setpts=PTS-STARTPTS,scale=1080:1920:flags=lanczos,format=yuva420p,fade=t=in:st=0:d=0.3:alpha=1,fade=t=out:st=1.3:d=0.3:alpha=1,setpts=PTS+25.4/TB[c2]")
pre.append("[base][c1]overlay=eof_action=pass[b1]")
pre.append("[b1][c2]overlay=eof_action=pass[b2]")
# dims (full frame) and the lower-third panel
layers=[dim("d1",0,0,1080,1920,16.8,20.1,0.42),dim("d2",0,0,1080,1920,20.3,23.5,0.42),
        dim("d3",0,0,1080,1920,27.2,30.9,0.42),dim("p1",40,1080,720,320,3.5,6.8,0.45)]
cur="b2"
for i,(src,(x,y)) in enumerate(layers):
    pre.append(src); name=src.split("[")[-1][:-1]
    pre.append(f"[{cur}][{name}]overlay=x={x}:y={y}:eof_action=pass[L{i}]"); cur=f"L{i}"
chain=[f"[{cur}]null"]
# A. hook stamp
chain.append(txt("DAY 1",F_B,170,WHITE,72,rise(150,0.1),0.1,3.3))
chain.append(txt("replacing my subscriptions",F_M,44,GREY,76,rise(345,0.25),0.25,3.3))
chain.append(txt("with apps I vibe code",F_M,44,GREY,76,rise(400,0.3),0.3,3.3))
chain.append(txt("DAY 1  ·  subscription challenge",F_M,34,GREY,72,120,3.5,31,din=0.5))
# B. lower third
chain.append(txt("Lucid",F_S,120,WHITE,72,rise(1110,3.5),3.5,6.8))
chain.append(txt("Live 4K wallpapers for Mac",F_M,46,WHITE,76,rise(1250,3.6),3.6,6.8))
chain.append(txt("Free  ·  Open source",F_M,46,ACC,76,rise(1312,3.7),3.7,6.8))
# C. pills
for tx,s,e,f,sz in [("Drag in any video",7.0,10.8,F_M,44),("Done.",12.9,14.0,F_S,52),("Works with any video file",14.3,16.5,F_M,44),("Installs in 10 seconds",23.7,25.4,F_M,44)]:
    y=1380 if tx.startswith("Installs") else 560
    chain.append(txt(tx,f,sz,WHITE,CX,rise(y,s,0.35,18),s,e,box="black@0.55"))
# E. counter, eased, fixed-slot digits
p=easeout(clip01("(t-17.0)/1.3"))
v=f"floor({p}*590)"
SLOT=128; X0=(1080-(3*SLOT+120))//2; Y=rise(720,16.8)
def digit(expr,slot,cond):
    en=f"between(t\\,16.8\\,20.1)*({cond})"
    return (f"drawtext=fontfile={F_B}:text='%{{eif\\:{expr}\\:d}}':fontsize=200:fontcolor={WHITE}"
            f":x={X0+slot*SLOT}+({SLOT}-text_w)/2:y={Y}:enable='{en}':alpha='{alpha(16.8,20.1)}'"
            f":shadowcolor=black@0.5:shadowx=0:shadowy=4")
chain.append(digit(f"floor({v}/100)",0,f"gte({v}\\,100)"))
chain.append(digit(f"mod(floor({v}/10)\\,10)",1,f"gte({v}\\,10)"))
chain.append(digit(f"mod({v}\\,10)",2,"1"))
chain.append(f"drawtext=fontfile={F_B}:text='+':fontsize=200:fontcolor={WHITE}:x={X0+3*SLOT}:y={Y}:enable='between(t\\,16.8\\,20.1)':alpha='{alpha(16.8,20.1)}':shadowcolor=black@0.5:shadowx=0:shadowy=4")
chain.append(txt("wallpapers built in",F_M,50,GREY,CX,rise(950,17.0),17.0,20.1))
# F. scoreboard
chain.append(txt("I was paying",F_M,46,GREY,CX,rise(700,20.3),20.3,23.5))
chain.append(txt("$2 / month",F_B,150,WHITE,CX,rise(770,20.35),20.35,23.5))
# strike grows left to right
chain.append(f"drawbox=x=170:y=862:w='740*{easeout(clip01('(t-21.5)/0.35'))}':h=16:color={RED}@0.95:t=fill:enable='between(t\\,21.5\\,23.5)'")
chain.append(txt("now  $0",F_B,150,ACC,CX,rise(980,21.9),21.9,23.5))
# G. tags
for i,(lab,s) in enumerate([("Open source",24.0),("MIT license",24.45),("No account",24.9),("No tracking",25.35)]):
    chain.append(txt(lab,F_M,46,WHITE,rise(72,s,0.4,-40).replace("72+","72+"),640+i*104,s,27.0,box="black@0.55"))
# subtitles
subs=[(0.0,0.8,"Day one."),(0.8,1.6,"Vibe coding an app"),(1.6,3.3,"so I can replace my subscriptions."),
(3.3,4.3,"First app I made"),(4.3,6.3,"a live 4K wallpaper app for my Mac."),(6.3,9.2,"Just drag in anything"),
(9.2,10.8,"into Downloads here."),(11.8,13.0,"Should be downloaded."),(13.0,13.9,"There we go."),
(14.0,16.5,"Use whatever wallpaper you find online."),(16.6,18.2,"Comes with a good amount"),(18.2,20.0,"of wallpapers already."),
(20.0,21.6,"I was paying $2 a month"),(21.6,23.6,"for a similar application."),(23.6,25.0,"Now I vibe coded my own"),
(25.0,26.0,"open source app"),(26.0,27.0,"you guys can use as well."),(27.0,28.0,"Just comment LUCID"),
(28.0,28.8,"to get the link."),(28.8,30.9,"Check my bio, hit my GitHub.")]
for a,b,tx in subs:
    chain.append(txt(tx,F_M,46,WHITE,CX,1520,a,b,box="black@0.38",din=0.12,dout=0.12))
# H. CTA
chain.append(txt("Comment LUCID",F_B,116,WHITE,CX,rise(640,27.2),27.2,30.9))
chain.append(txt("GitHub link in bio",F_M,52,ACC,CX,rise(800,27.35),27.35,30.9))
chain.append(txt("github.com/jedbrnth-eng/",F_M,42,GREY,CX,rise(900,27.5),27.5,30.9))
chain.append(txt("lucid-live-wallpaper",F_M,42,GREY,CX,rise(955,27.5),27.5,30.9))
vf=",".join(chain)+"[v]"
hits=[0.1,17.0,21.5,27.2]
af=["[0:a]highpass=f=80,acompressor=threshold=-24dB:ratio=2.5:attack=8:release=120,loudnorm=I=-14:TP=-1.5:LRA=9:measured_I=-26.1:measured_TP=-5.0:measured_LRA=2.5:measured_thresh=-36.1:linear=true[voice]"]
for i,h in enumerate(hits):
    af.append(f"aevalsrc='0.9*sin(2*PI*55*t)*exp(-7*t)+0.45*sin(2*PI*110*t)*exp(-9*t)':d=0.7:s=48000,adelay={int(h*1000)}|{int(h*1000)},volume=0.8[h{i}]")
af.append("[voice]"+"".join(f"[h{i}]" for i in range(len(hits)))+f"amix=inputs={len(hits)+1}:normalize=0:duration=first,alimiter=limit=0.89[a]")
open("filters4.txt","w").write(";".join(pre)+";"+vf+";"+";".join(af))
inputs=["src/raw2.mp4","src/img1339.mov","src/img1341.mov"]
out=sys.argv[1]; preview=len(sys.argv)>2
cmd=["ffmpeg","-y","-v","error"]+sum([["-i",f] for f in inputs],[])+["-filter_complex_script","filters4.txt","-map","[v]","-map","[a]",
     "-r","30","-c:v","libx264","-preset","fast" if preview else "slow","-crf","28" if preview else "19","-pix_fmt","yuv420p","-c:a","aac","-b:a","256k","-movflags","+faststart"]
subprocess.run(cmd+[out],check=True)
