import re
src=open('make.py').read()
css=re.search(r"html = '''(.*?)<h1>", src, re.S).group(1)
ic=src[src.index('icons = {'):src.index('order =')]
exec(ic)
order=['flash','blur','text','wand','filter','gear']
def btn(k): return f'<div class="gb"><svg viewBox="0 0 24 24" width="17" height="17">{icons[k]}</svg></div>'
msvg='<svg viewBox="0 0 24 24" width="{s}" height="{s}"><path d="M12 3v18" stroke="#fff" stroke-width="1.6" stroke-dasharray="2 2.2" stroke-linecap="round"/><path d="M9.2 7.5v9H3.4z" fill="#fff"/><path d="M14.8 7.5v9h5.8z" fill="none" stroke="#fff" stroke-width="1.6" stroke-linejoin="round"/></svg>'
def mir(cls='',s=19): return f'<div class="gb tm {cls}">{msvg.format(s=s)}</div>'
flipsvg=re.search(r'<div class="flip">(<svg.*?</svg>)</div>', src, re.S).group(1)
widesvg='<svg viewBox="0 0 24 24" width="17" height="17"><path d="M9 5H5v4M15 19h4v-4M5 5l5 5M19 19l-5-5" fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>'
def phone(letter,title,w):
    toprow=f'<div class="top">{"".join(btn(k) for k in order)}</div>'; sheet=''; corner2=''; byzoom=''; aboveflip=''
    if w=='A': toprow=f'<div class="top tight">{"".join(btn(k) for k in order[:5])}{mir()}{btn("gear")}</div>'
    if w=='B': corner2=f'<div class="corner2">{mir()}</div>'
    if w=='C': byzoom=mir('small',16)
    if w=='D': aboveflip=f'<div class="aboveflip">{mir()}</div>'
    if w=='E': sheet='<div class="sheet"><div class="grab"></div><div class="st">Settings</div><div class="rowS"><span>Timer</span><span class="seg"><em class="on">Off</em><em>3s</em><em>10s</em></span></div><div class="rowS hl"><span>Mirror selfies</span><span class="tog on"><i></i></span></div><div class="rowS"><span>Level</span><span class="tog"><i></i></span></div></div>'
    return f'''<div class="cell"><div class="cap"><span class="L">{letter}</span>{title}</div>
<div class="ph"><div class="island"></div>{toprow}<div class="corner"><span class="pill stack plain"><b>4K</b><b>30</b></span></div>{corner2}
<div class="bottom"><div class="zoomrow"><div class="gb">{widesvg}</div>{byzoom}</div>
<div class="row"><div class="thumb"></div><div class="shut"><div></div></div><div class="flipwrap">{aboveflip}<div class="flip">{flipsvg}</div></div></div>
<div class="modewrap"><div class="mode"><span>SLO-MO</span><span class="sel">VIDEO</span><span>PHOTO</span></div></div></div>{sheet}</div></div>'''
cells=[('A','A button in the top row','A'),('B','Top right, under 4K / 30','B'),('C','Beside the wider-view button','C'),('D','Above the switch-camera button','D'),('E','No button: a switch in Settings','E')]
css+='''<style>.tm{box-shadow:0 0 0 2px #ffd60a}.pill.plain{box-shadow:none}
.corner2{position:absolute;top:150px;right:13px}
.zoomrow{display:flex;gap:10px;align-items:center}.gb.small{width:35px;height:35px}
.flipwrap{position:relative}.aboveflip{position:absolute;bottom:54px;left:3.5px}
.sheet{position:absolute;left:0;right:0;bottom:0;height:330px;background:#1c1c1e;border-radius:22px 22px 0 0;padding:10px 16px}
.grab{width:38px;height:5px;border-radius:3px;background:#555;margin:0 auto 12px}.st{font-size:19px;font-weight:700;margin-bottom:12px}
.rowS{display:flex;justify-content:space-between;align-items:center;background:#2c2c2e;border-radius:12px;padding:12px;margin-bottom:8px;font-size:15px}
.rowS.hl{box-shadow:0 0 0 2px #ffd60a}.seg{display:flex;background:#3a3a3c;border-radius:8px;padding:2px;font-size:13px}.seg em{font-style:normal;padding:4px 9px;border-radius:6px}.seg em.on{background:#636366}
.tog{width:40px;height:24px;border-radius:12px;background:#3a3a3c;position:relative}.tog i{position:absolute;top:2px;left:2px;width:20px;height:20px;border-radius:50%;background:#fff}
.tog.on{background:#34c759}.tog.on i{left:18px}</style>'''
html=css+'<h1>Where should the mirror switch go?</h1><p class="sub">Mirror on: a selfie is saved the way you see it on screen (as it is today). Mirror off: it is saved the way other people see you, so writing on a shirt reads the right way. The yellow ring is only here to help you spot the new control.</p><div class="grid">'+''.join(phone(*c) for c in cells)+'</div>'
open('mirror.html','w').write(html)
