# Graphics pass for the Day 1 reel. Usage: python3 render_day1_reel.py out.mp4 [preview]
# Inputs: src/raw2.mp4 (clean phone take, no captions), src/img1339.mov (README install B-roll), src/img1341.mov (apply B-roll).
# Needs ffmpeg and Inter TTFs (Bold, SemiBold, Medium) in ./fonts (https://github.com/rsms/inter/releases).
# Timings are keyed to the words in the original 31 s take; re-time the constants if the cut changes.
import subprocess, sys
F_B="fonts/Inter-Bold.ttf"; F_S="fonts/Inter-SemiBold.ttf"; F_M="fonts/Inter-Medium.ttf"
W,H=1080,1920
WHITE="white"; GREY="0xA1A1AA"; ACC="0x7C5CFF"; RED="0xFF453A"
def fade(s,e,d=0.25):
    return f"if(lt(t\\,{s})\\,0\\,if(lt(t\\,{s+d})\\,(t-{s})/{d}\\,if(lt(t\\,{e-d})\\,1\\,if(lt(t\\,{e})\\,({e}-t)/{d}\\,0))))"
def rise(y,s,d=0.35,px=28):
    return f"{y}+{px}*(1-min(1\\,max(0\\,(t-{s})/{d})))"
def txt(text,font,size,color,x,y,s,e,alpha=True,box=None,xexpr=None):
    t=text.replace("\\","\\\\").replace("'", "\\'").replace(":", "\\:").replace("%","%%")
    o=[f"drawtext=fontfile={font}",f"text='{t}'",f"fontsize={size}",f"fontcolor={color}",
       f"x={xexpr or x}",f"y={y}",f"enable='between(t\\,{s}\\,{e})'","shadowcolor=black@0.55","shadowx=0","shadowy=4"]
    if alpha: o.append(f"alpha='{fade(s,e)}'")
    if box: o += ["box=1",f"boxcolor={box}","boxborderw=26"]
    return ":".join(o)
CX="(w-text_w)/2"
pre=["[0:v]scale=1080:1920:flags=lanczos,format=yuv420p[base]",
     "[1:v]trim=1.6:3.4,setpts=PTS-STARTPTS+23.6/TB,scale=1080:1920:flags=lanczos,format=yuv420p[c1]",
     "[2:v]trim=4.3:5.9,setpts=PTS-STARTPTS+25.4/TB,scale=1080:1920:flags=lanczos,format=yuv420p[c2]",
     "[base][c1]overlay=eof_action=pass:enable='between(t\\,23.6\\,25.4)'[b1]",
     "[b1][c2]overlay=eof_action=pass:enable='between(t\\,25.4\\,27.0)'[b2]"]
chain=["[b2]null"]
# A. DAY 1 stamp, big, hook
chain.append(txt("DAY 1",F_B,170,WHITE,72,rise(150,0.1),0.1,3.3))
chain.append(txt("replacing my subscriptions",F_M,44,GREY,76,rise(345,0.25),0.25,3.3))
chain.append(txt("with apps I vibe code",F_M,44,GREY,76,rise(400,0.3),0.3,3.3))
# persistent small series tag
chain.append(txt("DAY 1  ·  subscription challenge",F_M,34,GREY,72,120,3.5,31,alpha=False))
for a,b in [(16.8,20.1),(20.3,23.9),(27.2,30.9)]:
    chain.append(f"drawbox=x=0:y=0:w=iw:h=ih:color=black@0.42:t=fill:enable='between(t\\,{a}\\,{b})'")
chain.append("drawbox=x=40:y=1080:w=720:h=320:color=black@0.45:t=fill:enable='between(t\\,3.5\\,6.8)'")
# B. product lower third (above the caption band)
chain.append(txt("Lucid",F_S,120,WHITE,72,rise(1110,3.5),3.5,6.8))
chain.append(txt("Live 4K wallpapers for Mac",F_M,46,WHITE,76,rise(1250,3.6),3.6,6.8))
chain.append(txt("Free  ·  Open source",F_M,46,ACC,76,rise(1312,3.7),3.7,6.8))
# C. step pills
chain.append(txt("Drag in any video",F_M,44,WHITE,CX,560,7.0,10.8,alpha=False,box="black@0.55"))
chain.append(txt("Done.",F_S,52,WHITE,CX,560,12.9,14.0,alpha=False,box="black@0.55"))
chain.append(txt("Works with any video file",F_M,44,WHITE,CX,560,14.3,16.5,alpha=False,box="black@0.55"))
# E. counter 0 -> 590
cnt="%{eif\\:min(590\\,max(0\\,(t-17.0)/1.1)*590)\\:d}+"
chain.append(f"drawtext=fontfile={F_B}:text='{cnt}':fontsize=200:fontcolor={WHITE}:x={CX}:y=720:enable='between(t\\,16.8\\,20.1)':alpha='{fade(16.8,20.1)}'")
chain.append(txt("wallpapers built in",F_M,50,GREY,CX,950,17.0,20.1))
# F. scoreboard
chain.append(txt("I was paying",F_M,46,GREY,CX,700,20.3,23.9))
chain.append(txt("$2 / month",F_B,150,WHITE,CX,770,20.3,23.9))
chain.append(f"drawbox=x=170:y=862:w=740:h=16:color={RED}@0.95:t=fill:enable='between(t\\,21.5\\,23.9)'")
chain.append(txt("now  $0",F_B,150,ACC,CX,980,21.9,23.9))
# G. tags
for i,(lab,s) in enumerate([("Open source",24.0),("MIT license",24.45),("No account",24.9),("No tracking",25.35)]):
    chain.append(txt(lab,F_M,46,WHITE,72,640+i*104,s,27.0,alpha=False,box="black@0.55"))
# subtitles
subs=[(0.0,0.8,"Day one."),(0.8,1.6,"Vibe coding an app"),(1.6,3.3,"so I can replace my subscriptions."),
(3.3,4.3,"First app I made"),(4.3,6.3,"a live 4K wallpaper app for my Mac."),(6.3,9.2,"Just drag in anything"),
(9.2,10.8,"into Downloads here."),(11.8,13.0,"Should be downloaded."),(13.0,13.9,"There we go."),
(14.0,16.5,"Use whatever wallpaper you find online."),(16.6,18.2,"Comes with a good amount"),(18.2,20.0,"of wallpapers already."),
(20.0,21.6,"I was paying $2 a month"),(21.6,23.6,"for a similar application."),(23.6,25.0,"Now I vibe coded my own"),
(25.0,26.0,"open source app"),(26.0,27.0,"you guys can use as well."),(27.0,28.0,"Just comment LUCID"),
(28.0,28.8,"to get the link."),(28.8,30.9,"Check my bio, hit my GitHub.")]
for a,b,tx in subs:
    chain.append(txt(tx,F_M,46,WHITE,CX,1520,a,b,alpha=False,box="black@0.38"))
chain.append(txt("Installs in 10 seconds",F_M,44,WHITE,CX,1380,23.7,25.4,alpha=False,box="black@0.55"))
# H. CTA
chain.append(txt("Comment LUCID",F_B,116,WHITE,CX,rise(640,27.2),27.2,30.9))
chain.append(txt("GitHub link in bio",F_M,52,ACC,CX,rise(800,27.35),27.35,30.9))
chain.append(txt("github.com/jedbrnth-eng/",F_M,42,GREY,CX,rise(900,27.5),27.5,30.9))
chain.append(txt("lucid-live-wallpaper",F_M,42,GREY,CX,rise(955,27.5),27.5,30.9))
vf=",".join(chain)+"[v]"
# audio: voice cleanup + normalize, plus synthesized sub hits
hits=[0.1,17.0,21.5,27.2]
af=["[0:a]highpass=f=80,acompressor=threshold=-24dB:ratio=2.5:attack=8:release=120,loudnorm=I=-14:TP=-1.5:LRA=9:measured_I=-26.1:measured_TP=-5.0:measured_LRA=2.5:measured_thresh=-36.1:linear=true[voice]"]
for i,h in enumerate(hits):
    af.append(f"aevalsrc='0.9*sin(2*PI*55*t)*exp(-7*t)+0.45*sin(2*PI*110*t)*exp(-9*t)':d=0.7:s=48000,adelay={int(h*1000)}|{int(h*1000)},volume=0.8[h{i}]")
af.append("[voice]"+"".join(f"[h{i}]" for i in range(len(hits)))+f"amix=inputs={len(hits)+1}:normalize=0:duration=first,alimiter=limit=0.89[a]")
open("filters.txt","w").write(";".join(pre)+";"+vf+";"+";".join(af))
out=sys.argv[1]; preview=len(sys.argv)>2
cmd=["ffmpeg","-y","-v","error","-i","src/raw2.mp4","-i","src/img1339.mov","-i","src/img1341.mov","-filter_complex_script","filters.txt","-map","[v]","-map","[a]",
     "-r","30","-c:v","libx264","-preset","fast" if preview else "slow","-crf","28" if preview else "17","-pix_fmt","yuv420p","-c:a","aac","-b:a","256k","-movflags","+faststart"]
if preview: cmd+=["-t","31"]
subprocess.run(cmd+[out],check=True)
