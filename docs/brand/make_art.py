BG="#0b1410"; CARD="#101c16"; LINE="#24382d"; TXT="#e8efe9"; MUT="#8aa396"
G="#3ddc84"; A="#f2b84b"; B="#6aa8ff"
FONT='font-family="Inter,Segoe UI,Roboto,Helvetica,Arial,sans-serif"'
MONO='font-family="ui-monospace,SFMono-Regular,Menlo,Consolas,Liberation Mono,monospace"'
GROUPS=[(20,G),(10,A),(6,B)]
def esc(s): return s.replace('&','&amp;').replace('<','&lt;')
def t(x,y,s,size=14,fill=TXT,mono=False,anchor="start",weight=400,extra=""):
    return f'<text x="{x}" y="{y}" {MONO if mono else FONT} font-size="{size}" fill="{fill}" text-anchor="{anchor}" font-weight="{weight}" {extra}>{esc(s)}</text>'
def gpu(x,y,w=170,h=64):
    s=[f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="6" fill="#16241d" stroke="{G}" stroke-width="1.5"/>',
       f'<rect x="{x+14}" y="{y+h}" width="{w*0.55:.0f}" height="7" fill="#c9a548"/>']
    for k in range(2):
        cx=x+w*0.3+k*w*0.4; cy=y+h/2; r=h*0.36
        s.append(f'<circle cx="{cx:.0f}" cy="{cy:.0f}" r="{r:.0f}" fill="#0d1813" stroke="{LINE}" stroke-width="1.5"/>')
        s.append(f'<g><animateTransform attributeName="transform" type="rotate" from="0 {cx:.0f} {cy:.0f}" to="360 {cx:.0f} {cy:.0f}" dur="{1.6+k*0.3}s" repeatCount="indefinite"/>'+''.join(f'<line x1="{cx:.0f}" y1="{cy:.0f}" x2="{cx+r*0.85*__import__("math").cos(a*1.2566):.1f}" y2="{cy+r*0.85*__import__("math").sin(a*1.2566):.1f}" stroke="{MUT}" stroke-width="2"/>' for a in range(5))+'</g>')
        s.append(f'<circle cx="{cx:.0f}" cy="{cy:.0f}" r="4" fill="{MUT}"/>')
    return ''.join(s)
def phone(x,y,col,w=50,h=96):
    return (f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="9" fill="#16241d" stroke="{col}" stroke-width="1.5"/>'
            f'<rect x="{x+4}" y="{y+10}" width="{w-8}" height="{h-22}" rx="3" fill="#0d1813"/>'
            f'<rect x="{x+w/2-7}" y="{y+4}" width="14" height="3" rx="1.5" fill="{LINE}"/>'
            + ''.join(f'<rect x="{x+9}" y="{y+18+i*9}" width="{(w-18)*(0.9 if i%3 else 0.6):.0f}" height="4" rx="2" fill="{col}" opacity=".55"/>' for i in range(6)))
def wifi(x,y,col):
    return ''.join(f'<path d="M{x-r} {y} A{r} {r} 0 0 1 {x+r} {y}" fill="none" stroke="{col}" stroke-width="2" opacity="{o}"><animate attributeName="opacity" values="{o};.15;{o}" dur="1.8s" begin="{i*0.3}s" repeatCount="indefinite"/></path>' for i,(r,o) in enumerate([(6,.9),(12,.7),(18,.5)]))
def strip(x0,y,bw,bh,gap,dur=3.6,label=True):
    """36 layers coloured by device + a cursor stepping through them (one forward pass)."""
    s=[]; i=0; spans=[]
    for n,col in GROUPS:
        st=x0+i*(bw+gap)
        for k in range(n):
            s.append(f'<rect x="{x0+i*(bw+gap)}" y="{y}" width="{bw}" height="{bh}" rx="2" fill="{col}" opacity=".78"/>'); i+=1
        spans.append((st, x0+i*(bw+gap)-gap, col))
    xs=';'.join(str(x0+k*(bw+gap)-2) for k in range(36))
    s.append(f'<rect y="{y-3}" width="{bw+4}" height="{bh+6}" rx="3" fill="none" stroke="{TXT}" stroke-width="2"><animate attributeName="x" values="{xs}" dur="{dur}s" calcMode="discrete" repeatCount="indefinite"/></rect>')
    return ''.join(s), spans
def led(x,y,col,k0,k1,dur=3.6):
    a=k0/36; b=k1/36
    kt=f"0;{a:.4f};{b:.4f};1" if a>0 else f"0;{b:.4f};1"
    vals="0.15;1;0.15;0.15" if a>0 else "1;0.15;0.15"
    return f'<circle cx="{x}" cy="{y}" r="4" fill="{col}"><animate attributeName="opacity" values="{vals}" keyTimes="{kt}" dur="{dur}s" calcMode="discrete" repeatCount="indefinite"/></circle>'

L={'ru':dict(you="Ты",q="Объясни, как работает RAID 5",argus="Argus на твоём ПК",a1="llama-server · порт 8080",a2="делит модель по свободной памяти",
   model="Qwen3 8B · Q4_K_M · 36 слоёв",d=[("GeForce GTX 960","20 слоёв · видеопамять 4 ГБ","в компьютере"),("Galaxy S20","10 слоёв · 8 ГБ","по USB-кабелю"),("Galaxy A52","6 слоёв · 6 ГБ","по Wi-Fi")],
   ans="Argus",ansq="RAID 5 раскладывает данные полосами…",speed="≈7 токенов/с · всё дома, без интернета",
   flow="каждый токен проходит слои по порядку: видеокарта → S20 → A52 → ответ",
   tag1="Видеокарта и старые телефоны —",tag1b="одна нейросеть у тебя дома",tag2="Без интернета · без подписок · без root"),
 'en':dict(you="You",q="Explain how RAID 5 works",argus="Argus on your PC",a1="llama-server · port 8080",a2="splits the model by free memory",
   model="Qwen3 8B · Q4_K_M · 36 layers",d=[("GeForce GTX 960","20 layers · 4 GB VRAM","inside the PC"),("Galaxy S20","10 layers · 8 GB","over USB"),("Galaxy A52","6 layers · 6 GB","over Wi-Fi")],
   ans="Argus",ansq="RAID 5 stripes data and keeps parity…",speed="≈7 tokens/s · at home, offline",
   flow="every token runs through the layers in order: GPU → S20 → A52 → answer",
   tag1="Your GPU and old phones —",tag1b="one LLM, at home",tag2="Offline · no subscriptions · no root")}

def scheme(lang,out):
    l=L[lang]; W,H=1200,560
    s=[f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">',
       f'<rect width="{W}" height="{H}" rx="16" fill="{BG}"/>',
       f'<defs><marker id="ar" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto"><path d="M0 0L10 5L0 10z" fill="{MUT}"/></marker>'
       f'<clipPath id="type"><rect x="830" y="40" height="80" width="0"><animate attributeName="width" values="0;340;340" keyTimes="0;.8;1" dur="7.2s" repeatCount="indefinite"/></rect></clipPath></defs>']
    # chat bubble
    s.append(f'<rect x="40" y="40" width="300" height="72" rx="14" fill="{CARD}" stroke="{LINE}"/>')
    s.append(t(60,66,l['you'],12,MUT,True)); s.append(t(60,94,l['q'],16))
    s.append(f'<line x1="344" y1="76" x2="420" y2="76" stroke="{MUT}" stroke-width="1.5" marker-end="url(#ar)"/>')
    # argus box
    s.append(f'<rect x="426" y="32" width="340" height="90" rx="14" fill="{CARD}" stroke="{G}" stroke-width="1.5"/>')
    s.append(t(448,64,l['argus'],18,TXT,weight=700)); s.append(t(448,88,l['a1'],13,MUT,True)); s.append(t(448,108,l['a2'],13,MUT,True))
    # answer bubble
    s.append(f'<rect x="812" y="40" width="348" height="72" rx="14" fill="#13261c" stroke="{G}" stroke-opacity=".5"/>')
    s.append(t(832,66,l['ans'],12,G,True)); 
    s.append(f'<g clip-path="url(#type)">{t(832,94,l["ansq"],14)}</g>')
    s.append(f'<line x1="770" y1="76" x2="806" y2="76" stroke="{MUT}" stroke-width="1.5" marker-end="url(#ar)"/>')
    # model strip
    x0,bw,gap=60,26,4; y=208
    s.append(t(x0,190,l['model'],14,TXT,True,weight=600))
    s.append(f'<path d="M596 124 V168" stroke="{MUT}" stroke-width="1.5" stroke-dasharray="4 4" marker-end="url(#ar)"/>')
    st,spans=strip(x0,y,bw,40,gap,3.6); s.append(st)
    s.append(t(40,H-28,l['flow'],13,MUT,True))
    # devices
    k=0; dev_x=[]
    for gi,((st_,en_,col),(name,sub,via)) in enumerate(zip(spans,l['d'])):
        cx=(st_+en_)/2
        s.append(f'<path d="M{st_} 256 V262 H{en_} V256" fill="none" stroke="{col}" stroke-width="1.5"/>' if False else '')
        s.append(f'<path d="M{st_} 252 L{st_} 258 L{en_} 258 L{en_} 252" fill="none" stroke="{col}" stroke-width="1.5"/>')
        dy=330
        if gi==0:
            s.append(f'<line x1="{cx}" y1="258" x2="{cx}" y2="{dy}" stroke="{col}" stroke-width="1.5"/>')
            s.append(gpu(cx-95,dy,190,70))
            ty=dy+118
        else:
            if gi==1:
                s.append(f'<path d="M{cx} 258 V300 Q{cx} 318 {cx} {dy}" stroke="{col}" stroke-width="3" fill="none"/>')
            else:
                s.append(f'<line x1="{cx}" y1="258" x2="{cx}" y2="292" stroke="{col}" stroke-width="1.5" stroke-dasharray="3 4"/>')
                s.append(wifi(cx,316,col))
            s.append(phone(cx-27,dy,col,54,100)); ty=dy+130
        n=GROUPS[gi][0]
        s.append(led(cx+ (105 if gi==0 else 40), dy+8, col, k, k+n)); k+=n
        s.append(t(cx,ty,name,16,TXT,anchor="middle",weight=700))
        s.append(t(cx,ty+22,sub,13,col,True,anchor="middle"))
        s.append(t(cx,ty+42,via,13,MUT,anchor="middle"))
    s.append(t(W-40,H-28,l['speed'],13,MUT,True,anchor="end"))
    s.append('</svg>'); open(out,'w').write('\n'.join(s))

def banner(lang,out):
    l=L[lang]; W,H=1280,320
    s=[f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">',
       f'<rect width="{W}" height="{H}" rx="16" fill="{BG}"/>']
    # wordmark: eye mark + text
    s.append(f'<g transform="translate(64 70)"><path d="M0 22 Q26 -4 52 22 Q26 48 0 22Z" fill="none" stroke="{G}" stroke-width="3"/><circle cx="26" cy="22" r="8" fill="{G}"><animate attributeName="cx" values="22;30;22" dur="4s" repeatCount="indefinite"/></circle></g>')
    s.append(t(130,106,"Argus",54,TXT,weight=800,extra='letter-spacing="-1"'))
    s.append(t(64,168,l['tag1'],26,TXT,weight=600)); s.append(t(64,202,l['tag1b'],26,G,weight=600))
    s.append(t(64,244,l['tag2'],16,MUT))
    x=64
    for c in ["Windows","Linux","Android","Raspberry Pi"]:
        w=len(c)*8.2+26
        s.append(f'<rect x="{x}" y="264" width="{w:.0f}" height="26" rx="6" fill="{CARD}" stroke="{LINE}"/>'); s.append(t(x+w/2,281,c,12,TXT,True,anchor="middle")); x+=w+8
    # right: mini diagram
    x0,bw,gap=700,12,3
    s.append(t(x0,74,l['model'],13,MUT,True))
    st,spans=strip(x0,88,bw,30,gap,3.6); s.append(st)
    k=0
    for gi,((a_,b_,col),(name,sub,via)) in enumerate(zip(spans,l['d'])):
        cx=(a_+b_)/2
        s.append(f'<path d="M{a_} 126 L{a_} 132 L{b_} 132 L{b_} 126" fill="none" stroke="{col}" stroke-width="1.5"/>')
        if gi==0: s.append(f'<line x1="{cx}" y1="132" x2="{cx}" y2="160" stroke="{col}" stroke-width="1.5"/>'); s.append(gpu(cx-70,160,140,52)); ly=250
        elif gi==1: s.append(f'<line x1="{cx}" y1="132" x2="{cx}" y2="160" stroke="{col}" stroke-width="3"/>'); s.append(phone(cx-20,160,col,40,76)); ly=262
        else: s.append(f'<line x1="{cx}" y1="132" x2="{cx}" y2="146" stroke="{col}" stroke-width="1.5" stroke-dasharray="3 3"/>'); s.append(wifi(cx,160,col)); s.append(phone(cx-20,166,col,40,76)); ly=262
        n=GROUPS[gi][0]; s.append(led(cx+(80 if gi==0 else 28),168,col,k,k+n)); k+=n
        s.append(t(cx,ly,name,13,TXT,anchor="middle",weight=600)); s.append(t(cx,ly+18,via,11,MUT,anchor="middle"))
    s.append('</svg>'); open(out,'w').write('\n'.join(s))
for lg in ['ru','en']:
    scheme(lg,f'/tmp/argus/docs/brand/scheme-{lg}.svg'); banner(lg,f'/tmp/argus/docs/brand/banner-{lg}.svg')
